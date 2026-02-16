import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @ObservedObject var viewModel: ViewerViewModel
    @State private var showImporter = false

    var body: some View {
        NavigationSplitView {
            List {
                Section("Table of Contents") {
                    if viewModel.toc.isEmpty {
                        Text("No headings")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.toc) { item in
                            Button {
                                viewModel.navigateToAnchor(item.anchor)
                            } label: {
                                Text(String(repeating: "  ", count: max(Int(item.level) - 1, 0)) + item.title)
                                    .font(.system(size: 12))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Diagnostics") {
                    if viewModel.diagnostics.isEmpty {
                        Text("No warnings")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.diagnostics) { diagnostic in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(diagnostic.message)
                                    .font(.system(size: 12, weight: .semibold))
                                if let resource = diagnostic.resource {
                                    Text(resource)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Markdown")
        } detail: {
            Group {
                if viewModel.isLoading {
                    ProgressView("Rendering…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !viewModel.htmlDocument.isEmpty {
                    MarkdownWebView(
                        htmlDocument: viewModel.htmlDocument,
                        baseURL: viewModel.baseURL,
                        allowedRootURL: viewModel.allowedRootURL,
                        currentFileURL: viewModel.fileURL,
                        navigateToAnchor: viewModel.requestedAnchor,
                        onOpenMarkdownLink: { linkURL in
                            viewModel.openDocument(at: linkURL)
                        },
                        onOpenExternalLink: { linkURL in
                            NSWorkspace.shared.open(linkURL)
                        },
                        onDidNavigateToAnchor: {
                            viewModel.clearAnchorRequest()
                        },
                        onRequestFolderAccess: {
                            viewModel.requestFolderAccess()
                        }
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !viewModel.rawMarkdown.isEmpty {
                    ScrollView {
                        Text(viewModel.rawMarkdown)
                            .textSelection(.enabled)
                            .font(.system(size: 13, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                    }
                } else {
                    ContentUnavailableView("Open a Markdown file", systemImage: "doc.plaintext")
                }
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    if viewModel.needsFolderAccess {
                        HStack(spacing: 8) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .foregroundStyle(.orange)
                            Text("Images cannot be displayed.")
                                .font(.system(size: 12, weight: .semibold))
                            Button("Grant Folder Access") {
                                viewModel.grantFolderAccess()
                            }
                            .font(.system(size: 12))
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding(8)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(8)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(12)
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button {
                        viewModel.goBack()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .help("Back")
                    .disabled(!viewModel.canGoBack)
                    .keyboardShortcut("[", modifiers: [.command])

                    Button {
                        viewModel.goForward()
                    } label: {
                        Image(systemName: "chevron.forward")
                    }
                    .help("Forward")
                    .disabled(!viewModel.canGoForward)
                    .keyboardShortcut("]", modifiers: [.command])
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.refreshDocument()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh (⌘R)")
                    .disabled(viewModel.fileURL == nil)
                    .keyboardShortcut("r", modifiers: [.command])
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.openInExternalEditor()
                    } label: {
                        Image(systemName: "pencil.line")
                    }
                    .help("Open in External Editor (⌘E)")
                    .disabled(viewModel.fileURL == nil)
                    .keyboardShortcut("e", modifiers: [.command])
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.revealInFinder()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Reveal in Finder (⇧⌘R)")
                    .disabled(viewModel.fileURL == nil)
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Open…") {
                        showImporter = true
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [
                UTType(filenameExtension: "md") ?? .plainText,
                UTType(filenameExtension: "markdown") ?? .plainText,
                .plainText
            ],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let selected = urls.first else { return }
                viewModel.openDocumentFromPicker(at: selected)
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }
}
