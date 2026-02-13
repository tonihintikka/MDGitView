import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var openFileHandler: ((URL) -> Void)?

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        openFileHandler?(URL(fileURLWithPath: filename))
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.isFileURL {
            openFileHandler?(url)
        }
    }
}

@main
struct MDGitViewApp: App {
    @StateObject private var viewModel = ViewerViewModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onAppear {
                    appDelegate.openFileHandler = { url in
                        viewModel.openDocumentFromPicker(at: url)
                    }

                    guard CommandLine.arguments.count > 1 else { return }
                    let potentialPath = CommandLine.arguments[1]
                    let fileURL = URL(fileURLWithPath: potentialPath)
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        viewModel.openDocumentFromPicker(at: fileURL)
                    }
                }
                .onOpenURL { url in
                    guard url.isFileURL else { return }
                    viewModel.openDocumentFromPicker(at: url)
                }
        }
        .defaultSize(width: 1200, height: 780)
    }
}
