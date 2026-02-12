import Foundation

@_silgen_name("md_render")
private func md_render(
    _ markdownUTF8: UnsafePointer<CChar>,
    _ optionsJSON: UnsafePointer<CChar>
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("md_free_result")
private func md_free_result(_ pointer: UnsafeMutablePointer<CChar>?)

@_silgen_name("md_last_error")
private func md_last_error() -> UnsafePointer<CChar>?

enum RustMarkdownFFIError: LocalizedError {
    case serialization(Error)
    case ffiFailure(String)
    case decode(Error)

    var errorDescription: String? {
        switch self {
        case .serialization(let error):
            return "Failed to serialize render options: \(error.localizedDescription)"
        case .ffiFailure(let message):
            return "Rust renderer failed: \(message)"
        case .decode(let error):
            return "Failed to decode renderer output: \(error.localizedDescription)"
        }
    }
}

enum RustMarkdownFFI {
    static func render(markdown: String, options: RenderOptions) throws -> EngineRenderedDocument {
        let encoder = JSONEncoder()
        let optionsData: Data
        do {
            optionsData = try encoder.encode(options)
        } catch {
            throw RustMarkdownFFIError.serialization(error)
        }

        guard let optionsString = String(data: optionsData, encoding: .utf8) else {
            throw RustMarkdownFFIError.ffiFailure("Could not encode options to UTF-8")
        }

        let payloadJSONString: String? = markdown.withCString { markdownCString in
            optionsString.withCString { optionsCString in
                guard let rawResult = md_render(markdownCString, optionsCString) else {
                    return nil
                }

                defer { md_free_result(rawResult) }
                return String(cString: rawResult)
            }
        }

        guard let payloadJSONString else {
            let ffiMessage = md_last_error().map { String(cString: $0) } ?? "unknown ffi failure"
            throw RustMarkdownFFIError.ffiFailure(ffiMessage)
        }

        do {
            let data = Data(payloadJSONString.utf8)
            return try JSONDecoder().decode(EngineRenderedDocument.self, from: data)
        } catch {
            throw RustMarkdownFFIError.decode(error)
        }
    }
}
