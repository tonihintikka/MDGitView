import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var openFileHandler: ((URL) -> Void)? {
        didSet {
            deliverPendingFiles()
        }
    }

    private var pendingFileURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)

        guard let openFileHandler else {
            for url in fileURLs where !pendingFileURLs.contains(url) {
                pendingFileURLs.append(url)
            }
            return
        }

        fileURLs.forEach(openFileHandler)
    }

    private func deliverPendingFiles() {
        guard let openFileHandler, !pendingFileURLs.isEmpty else { return }

        let urls = pendingFileURLs
        pendingFileURLs.removeAll()
        urls.forEach(openFileHandler)
    }
}

@main
struct MDGitViewApp: App {
    @StateObject private var viewModel = ViewerViewModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("MDGitView", id: "main") {
            ContentView(viewModel: viewModel)
                .onAppear {
                    appDelegate.openFileHandler = { url in
                        viewModel.openDocumentFromPicker(at: url)
                    }

                    viewModel.checkIfDefaultMarkdownViewer()
                }
        }
        .defaultSize(width: 1200, height: 780)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MDGitView") {
                    openWindow(id: "about")
                }
            }

            CommandGroup(replacing: .help) {
                Button("MDGitView Help") {
                    NSWorkspace.shared.open(
                        URL(string: "https://github.com/tonihintikka/MDGitView#readme")!
                    )
                }
                Button("Report an Issue…") {
                    NSWorkspace.shared.open(
                        URL(string: "https://github.com/tonihintikka/MDGitView/issues")!
                    )
                }
                Divider()
                Button("Check for Updates…") {
                    NSWorkspace.shared.open(
                        URL(string: "https://github.com/tonihintikka/MDGitView/releases")!
                    )
                }
            }
        }

        Window("About MDGitView", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
