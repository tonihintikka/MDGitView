# Quick Look and PDF cache handoff

Updated: 2026-11-17, Europe/Helsinki. Continuation of the task is in progress.

## Start here

Read `now.md`, `docs/agent-context.md`, and the original task `docs/tasks/2026-11-16-quicklook-toc-ffi.md`. This note records findings and the PDF implementation. The original task specifies four commits, tests before each commit, and no release. All four task commits are on `main`. Do not push or release.

Toni approved leaving MDGitView's Quick Look enabled and Obsidian's Quick Look disabled. He also said rendered Mermaid diagrams and math are welcome in Quick Look, superseding the original task's preference for source-only previews as a product goal. Full PDF-cache integration has not been implemented. His final request was to save this handoff and stop implementation until the next session.

## Verified findings

- Finder was selecting **ObsidianQuickLook**, not MDGitView's preview. The system log at 21:12:28 showed `ObsidianQuickLook ... Preview failed`, followed by the plain-text preview.
- `pluginkit -e ignore -i md.obsidian.quicklook`, `pluginkit -e use -i com.toni.mdgitview.preview`, and restarting Finder caused MDGitView's HTML preview to render the same `sample.md` correctly. These choices remain in place with Toni's approval. This does not disable the Obsidian app.
- Earlier empty log results were invalid evidence: in the interactive zsh environment, `log` is a shell builtin. Always use **`/usr/bin/log`**. The temporary log is `/tmp/mdgitview-ql-diagnosis.log`; it may disappear after reboot.
- `project.yml` was restoring the broad preview entitlements when XcodeGen regenerated the plist. Both sources now omit network-client permission and the absolute-path `/` exception. Installed Debug signatures contain sandbox, user-selected read-only, and Xcode's `get-task-allow`.
- The installed main viewer visually rendered a Mermaid flowchart, inline math, and display math after the latest changes. Screenshot: `/tmp/mdgitview-mermaid-math-verified.png` (temporary).
- Quick Look renders styled Markdown, Mermaid source with its notice, and math source with its notice. The math regex had expected `math inline`; pulldown-cmark actually produces `math math-inline` and `math math-display`. This is fixed.
- Enabling Rust math parsing removed delimiters that MathJax's scanner needs. `viewer-shell.js` now restores explicit TeX delimiters in the parsed math spans before typesetting. The current installed viewer was checked after this correction.
- The sibling-image fixture **did not render in Quick Look**: it displayed `Image could not be read: local.png`. The engine's canonical-path policy permits the image, but the sandboxed extension cannot assume access to neighboring files. An exact sandbox-denial/errno trace has not yet been captured; do not claim that step was verified.
- Remote images and outside-directory images displayed placeholders. A dedicated HTTP server at `127.0.0.1:8974` received zero requests while the remote-image fixture was previewed. The server has been stopped. This checks the fixture URL, not every network operation of all system processes.
- `cargo test` passed 17 tests and the Xcode test command passed after the math fixes. `scripts/install.sh` installed that build. No new sandbox crash was observed during these checks.
- `tests/fixtures/large.md` is only 134 bytes. It is not a meaningful performance fixture. Prior measurements that timed an open Quick Look window until dismissal are not rendering timings. No valid before/after large-document benchmark exists.

## PDF proof of concept

The requested PDF was generated successfully:

- `output/pdf/sample-preview.pdf`: one page, 900 × 1090 points, 38,511 bytes, no PDF JavaScript.
- Input: `tests/fixtures/sample.md`.
- Prototype: `.cache/pdf-preview-prototype/main.swift`.
- Executable: `.cache/pdf-preview-prototype/PDFRender.app/Contents/MacOS/PDFRender`.
- Rendered inspection image: `.cache/pdf-preview-prototype/review/sample-preview.png`.

The prototype compiles the actual `MarkdownRenderService`, `RustMarkdownFFI`, `RenderModels`, and `MarkdownResourceSchemeHandler`, links `Vendor/libmd_ffi.a`, and loads the bundled assets. A background, unsandboxed WebKit host renders through the existing `mdgitview:` scheme. It waits for one Mermaid SVG, two MathJax containers, and loaded fonts, then calls `webView.pdf(configuration:)` and writes the result atomically.

The PDF was rasterized with `pdftoppm` and visually inspected: the flowchart, math, and table are present without clipping. The Tools button is still printed because the prototype's hide selector does not match the actual control. Remove interactive controls in a production export. This is a prototype, not a general exporter: its readiness counts are hardcoded to this fixture, its page is continuous rather than A4-paginated, and it has not run inside the Quick Look sandbox or through a shared container. The PDF's local links also need an explicit export policy.

Do not delete the prototype until its useful code has been incorporated or deliberately discarded. `.cache/` is Git-ignored. `output/` is currently untracked. Do not accidentally stage generated binaries, release ZIPs, or `default.profraw`.

## Apple-supported building blocks

The following APIs are documented by Apple. The pipeline below is our proposed composition of those APIs; Apple does not prescribe this exact Markdown cache architecture.

1. Generate PDF data from a rendered `WKWebView` using [`createPDF(configuration:completionHandler:)`](https://developer.apple.com/documentation/webkit/wkwebview/createpdf(configuration:completionhandler:)). The prototype uses the Swift async form `pdf(configuration:)`. Choose the capture rectangle with `WKPDFConfiguration`.
2. Share the resulting file between the main app and its extension through an **App Group**, not an arbitrary path into another target's private container. Apple's [Configuring app groups](https://developer.apple.com/documentation/xcode/configuring-app-groups) explicitly supports sharing between an app and extension, including sandboxed and nonsandboxed macOS apps.
3. On macOS, Apple also documents the group identifier form `<Developer team ID>.<group name>`. The project currently specifies team `8C2T254JY2`; verify the actual signing identity before selecting the group ID. A possible group name is `8C2T254JY2.mdgitview.preview`, but it is not configured or tested. Add the same application-groups entitlement to both targets through `project.yml` and its generated entitlement files. Recheck distribution signing requirements rather than assuming that Debug behavior proves Release access.
4. Locate the shared directory using [`FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`](https://developer.apple.com/documentation/foundation/filemanager/containerurl(forsecurityapplicationgroupidentifier:)). Do not hardcode `~/Library/Group Containers`. On macOS, the API can return a URL even for an invalid group: test actual read/write access from both signed targets. Use a dedicated subdirectory under the group's `Library/Caches`.
5. Return a valid cached PDF from the preview extension with [`QLPreviewReply(fileURL:)`](https://developer.apple.com/documentation/quicklookui/qlpreviewreply/init(fileurl:)). Apple explicitly describes replies from existing image or PDF URLs. The extension would then display already-rendered content without running Mermaid or MathJax itself.

## Original implementation plan

1. Confirm the desired first-preview behavior. An app-produced cache only exists after the document has been rendered in MDGitView. For an unseen document, retain the current sanitized HTML fallback. A cache alone cannot make first-time sibling-image reads available to the extension. Do not silently imply that every fresh Finder preview will contain diagrams and images.
2. Generalize the successful PDF prototype into an app-side export/cache service. Preserve the existing sanitization, CSP, resource-boundary checks, and vendored assets. Await explicit completion of Mermaid, MathJax, fonts, and image decoding; zero diagrams or equations must also succeed. Add cancellation and a timeout with a readable fallback.
3. Configure and verify App Group access independently of PDF rendering. Keep the preview sandbox on. Do not restore network-client permission or the broad `/` exception. Adding a group changes the original task's literal two-entitlement acceptance check; record this intentional change in the security model.
4. Define a versioned cache key and manifest: source identity and content hash, renderer/asset version, theme/export settings, and local-resource dependencies. Write temporary output then atomically publish PDF and manifest. Bound disk usage and clean up old entries without removing files a live preview is using.
5. The extension can hash the selected Markdown file, but may be unable to inspect sibling dependencies. Design freshness around that limitation. Do not promise that unchanged Markdown implies unchanged images. Regenerate dependencies in the main app and choose a documented expiry/fallback policy for cases the extension cannot validate.
6. Add cached-PDF lookup to the provider with the current HTML reply as the miss/failure path. Verify an actual Finder request selects MDGitView and displays the PDF, using `/usr/bin/log` and a screenshot. Exercise cache hit, miss, source change, image change, deleted cache, concurrent reads/writes, signing failure, and cancellation.
7. Review the existing mixed working-tree changes and split the requested four commits without losing later edits. Re-run the required checks for each commit. Do not claim the original task complete until sibling-image behavior, Unicode-anchor UI navigation, and the remaining acceptance criteria have been addressed or explicitly revised with Toni.

Suggested skills: `diagnose` for a reproducible Finder/cache test, `pdf` for PDF visual checks, `english-anti-slop` for repository prose, and `suomi-finnish` for replies. No release or push is authorized by this handoff.

## Continuation status, 2026-11-17

The App Group PDF path is implemented in `PreviewPDFCache.swift`. The signed main app and preview extension use `8C2T254JY2.mdgitview.preview`, matching the Team ID verified from the installed development signatures. The extension's signed entitlements retain the sandbox and user-selected read-only access, add the App Group, and omit network and broad filesystem exceptions. `containermanagerd` approved the extension's App Group lookup during a `qlmanage` request.

The main app starts a hidden WebKit render after opening or refreshing a document. It uses the existing `MarkdownRenderService` and resource scheme, waits for Mermaid, MathJax, and fonts, removes Mermaid controls, then writes a continuous PDF. The cache binds the standardized source path and Markdown content digest, checks the app build version, and expires entries after five minutes. Writes are coordinated with a file lock and atomic file replacement. New entries stop when the cache reaches 250 MiB. A cache miss keeps the current safe HTML reply. Since the extension cannot inspect sibling images, a recent PDF can contain an image that changed during its five-minute lifetime.

`cargo test` passes 17 tests, `xcodebuild ... test` passes 5 tests, and `scripts/install.sh` installed the Debug build. The extension launches and obtains App Group access. When this handoff was first written, the Mac locked during the Finder screenshot check. The earlier independent PDF proof of concept remains visually checked at `output/pdf/sample-preview.pdf`.

On 2026-11-17, the unlocked Mac showed Mermaid, inline math, and display math in MDGitView. A fresh `qlmanage -p tests/fixtures/sample.md` launched the signed preview extension, and system logs confirmed App Group lookup success. No cache hit/miss message appeared in the extension logs; shell access to the group container was denied. The Finder preview did not appear in the captured desktop, so the cached PDF has not been visually verified. Do not describe the cache path as manually validated until a hit is confirmed.

Remaining verification: confirm cache generation in the main app, verify hit and cold-miss behavior in Finder, and capture the Quick Look window. The four signed commits are on `main`; no push or release is authorized by the task.
