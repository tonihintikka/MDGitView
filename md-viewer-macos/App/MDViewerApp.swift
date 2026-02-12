import SwiftUI

@main
struct MDViewerApp: App {
    @StateObject private var viewModel = ViewerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onAppear {
                    guard CommandLine.arguments.count > 1 else { return }
                    let potentialPath = CommandLine.arguments[1]
                    let fileURL = URL(fileURLWithPath: potentialPath)
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        viewModel.openDocument(at: fileURL)
                    }
                }
        }
        .defaultSize(width: 1200, height: 780)
    }
}
