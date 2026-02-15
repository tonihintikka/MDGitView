import Foundation

struct RenderOptions: Codable {
    let enable_gfm: Bool
    let enable_mermaid: Bool
    let enable_math: Bool
    let base_dir: String?
    let allowed_root_dir: String?
    let theme: String

    static func defaults(baseDirectory: URL?, allowedRootDirectory: URL?) -> RenderOptions {
        RenderOptions(
            enable_gfm: true,
            enable_mermaid: true,
            enable_math: true,
            base_dir: baseDirectory?.path,
            allowed_root_dir: allowedRootDirectory?.path,
            theme: "github-light"
        )
    }
}

struct EngineRenderedDocument: Codable {
    let html: String
    let toc: [TocItem]
    let diagnostics: [RenderDiagnostic]
}

struct TocItem: Codable, Identifiable {
    let level: UInt8
    let title: String
    let anchor: String

    var id: String { anchor }
}

struct RenderDiagnostic: Codable, Identifiable {
    let code: String
    let message: String
    let resource: String?

    var id: String {
        "\(code)::\(resource ?? "")::\(message)"
    }
}

struct RenderedPayload {
    let htmlDocument: String
    let toc: [TocItem]
    let diagnostics: [RenderDiagnostic]
    let baseURL: URL?
    let allowedRootURL: URL?
}
