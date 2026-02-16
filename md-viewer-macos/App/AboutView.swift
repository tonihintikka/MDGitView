import SwiftUI

struct AboutView: View {
    private let repoURL = URL(string: "https://github.com/tonihintikka/MDGitView")!
    private let releasesURL = URL(string: "https://github.com/tonihintikka/MDGitView/releases")!
    private let issuesURL = URL(string: "https://github.com/tonihintikka/MDGitView/issues")!

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
    }

    private var copyrightYear: String {
        let year = Calendar.current.component(.year, from: Date())
        return "\(year)"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("MDGitView")
                .font(.system(size: 24, weight: .bold))

            Text("Version \(appVersion) (\(buildNumber))")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text("Markdown viewer with Mermaid diagrams,\nMathJax and QuickLook integration.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider()
                .frame(width: 200)

            VStack(spacing: 6) {
                Text("Created by Toni Hintikka")
                    .font(.system(size: 12, weight: .medium))

                Link("github.com/tonihintikka/MDGitView", destination: repoURL)
                    .font(.system(size: 12))
            }

            Divider()
                .frame(width: 200)

            HStack(spacing: 12) {
                Button("Check for Updates") {
                    NSWorkspace.shared.open(releasesURL)
                }
                .controlSize(.small)

                Button("Report Issue") {
                    NSWorkspace.shared.open(issuesURL)
                }
                .controlSize(.small)
            }

            Text("Copyright \(copyrightYear) Toni Hintikka. All rights reserved.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(30)
        .frame(width: 340)
        .fixedSize()
    }
}
