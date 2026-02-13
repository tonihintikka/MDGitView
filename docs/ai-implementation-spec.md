# AI Implementation Specification: macOS Rust Markdown Viewer

## 1. Goal

Build a macOS Markdown viewer with:

- Rust rendering core.
- SwiftUI app UI.
- Finder Space (Quick Look) preview and thumbnail integration.
- GitHub-style Markdown viewing behavior.
- Local-first runtime with no network dependency for rendering.

This document is decision-complete: another AI agent should be able to implement the same functional system from scratch.

## 2. Product scope

## 2.1 In scope

- Markdown rendering from local files.
- GFM-like output (tables, task lists, strikethrough, autolinks, footnotes, smart punctuation).
- Sanitized HTML rendering in WKWebView.
- Mermaid code block rewrite and runtime hook.
- Math text preserved for runtime typesetting hook.
- Table of contents generation.
- Clickable TOC navigation.
- Markdown link navigation between local `.md` files.
- External link opening in browser.
- Quick Look Preview extension (Space).
- Quick Look Thumbnail extension.
- Dark mode CSS support.

## 2.2 Out of scope

- Editing Markdown (viewer only).
- Remote/network asset loading.
- Full syntax highlighting parity with GitHub in current state.
- Full production App Store entitlement profile in local-dev configuration.

## 3. Repository architecture

- `md-engine/`: Rust renderer library.
- `md-ffi/`: Rust C ABI bridge.
- `md-viewer-macos/`: SwiftUI app + Quick Look extensions + XcodeGen spec.
- `scripts/`: Rust build integration + notarization helper.
- `tests/`: fixtures + Quick Look integration script.
- `docs/`: architecture, security, and replication docs.

## 4. Component contracts

## 4.1 Rust renderer (`md-engine`)

Primary API:

- `render_markdown(input: &str, opts: &RenderOptions) -> Result<RenderedDocument, RenderError>`

Data model:

- `RenderOptions`
  - `enable_gfm: bool`
  - `enable_mermaid: bool`
  - `enable_math: bool`
  - `base_dir: Option<PathBuf>`
  - `theme: String`
- `RenderedDocument`
  - `html: String`
  - `toc: Vec<TocItem>`
  - `diagnostics: Vec<Diagnostic>`
- `TocItem`
  - `level: u8`
  - `title: String`
  - `anchor: String`
- `Diagnostic`
  - `code: String`
  - `message: String`
  - `resource: Option<String>`

Implementation detail summary:

1. Parse Markdown with `pulldown-cmark` + GFM options.
2. Rewrite Mermaid fenced blocks in HTML output:
   - `<pre><code class="language-mermaid">...</code></pre>` -> `<div class="mermaid">...</div>`
3. Build TOC from Markdown heading lines.
4. Enforce local resource policy on links/images.
5. Sanitize resulting HTML with `ammonia`.
6. Inject heading IDs into `<h1..h6>` for anchor navigation.

## 4.2 Resource policy

Policy purpose:

- Allow safe local navigation and inline assets while blocking directory traversal and unsafe schemes.

Allow:

- Empty URL and hash-only URL.
- `http`, `https`, `mailto`, `tel`.
- Relative paths inside base directory tree (including nested folders like `docs/file.md`).

Block:

- `file://` URLs.
- Absolute paths (`/...`).
- Parent traversal (`..`).
- Non-whitelisted schemes.

Diagnostic behavior:

- Blocked links are rewritten to `#blocked-resource` and diagnostic is emitted.
- Blocked images have `src` emptied and diagnostic is emitted.

## 4.3 Rust FFI (`md-ffi`)

C ABI surface:

- `char *md_render(const char *markdown_utf8, const char *options_json);`
- `void md_free_result(char *result_ptr);`
- `const char *md_last_error(void);`

Behavior:

- Input options are JSON -> `RenderOptions`.
- Output is JSON string of `RenderedDocument`.
- Caller must release result via `md_free_result`.
- `md_last_error` returns a thread-local snapshot pointer.

## 4.4 Swift rendering bridge

Files:

- `Shared/RustMarkdownFFI.swift`
- `Shared/RenderModels.swift`
- `Shared/MarkdownRenderService.swift`

Flow:

1. Read Markdown file as UTF-8.
2. Build `RenderOptions` with `base_dir` = file parent directory.
3. Call Rust FFI renderer.
4. Wrap sanitized HTML into full HTML document with CSS and local JS assets.
5. Return `RenderedPayload` to view layer.

## 4.5 Web rendering and navigation

File:

- `Shared/MarkdownWebView.swift`

Capabilities:

- Renders HTML string in WKWebView.
- Intercepts link clicks.
- Allows in-page anchor links.
- Routes local Markdown links to app/preview document loader.
- Routes external links to system browser.
- Supports programmatic scroll to TOC anchors via injected JS.

Important behavior:

- Avoid full reload on every SwiftUI update.
- Reload only when HTML or base URL changes.
- Keep pending anchor request and execute after page load.

## 4.6 App UI layer

Files:

- `App/MDGitViewApp.swift`
- `App/ViewerViewModel.swift`
- `App/ContentView.swift`

Features:

- Open Markdown via file importer.
- Render view in detail pane.
- Sidebar sections:
  - Table of Contents (clickable).
  - Diagnostics.
- Raw markdown fallback if renderer fails.
- Optional open-from-CLI argument support.

## 4.7 Quick Look Preview extension

File:

- `PreviewExtension/MarkdownPreviewViewController.swift`

Features:

- Implements `QLPreviewingController`.
- Renders the same HTML pipeline as app.
- Supports local Markdown link navigation inside preview.
- Opens external links in default browser.

## 4.8 Quick Look Thumbnail extension

File:

- `ThumbnailExtension/MarkdownThumbnailProvider.swift`

Features:

- Extract first heading/first non-empty line as title.
- Draw card-style thumbnail via Core Graphics/AppKit.
- Uses request maximum size.

## 5. Finder Space requirements (critical)

To make Space integration work, extension metadata must include Quick Look extension keys in Info.plist output.

Required keys (conceptually):

- For preview extension:
  - `NSExtensionPointIdentifier = com.apple.quicklook.preview`
  - `NSExtensionPrincipalClass = <module>.MarkdownPreviewViewController`
  - `QLSupportedContentTypes` includes Markdown UTI(s)
- For thumbnail extension:
  - `NSExtensionPointIdentifier = com.apple.quicklook.thumbnail`
  - `NSExtensionPrincipalClass = <module>.MarkdownThumbnailProvider`
  - `QLSupportedContentTypes` includes Markdown UTI(s)

Also register app document types for Markdown UTI(s).

If these keys are missing, builds can succeed but Finder Space behavior will not be active.

## 6. Styling and dark mode

Asset:

- `Resources/Assets/github-markdown.css`

Requirements:

- Define CSS variables for light and dark.
- Set `color-scheme: light dark`.
- Ensure body text and background are variable-driven.
- Dark palette must keep contrast readable.

Current implementation includes:

- Separate dark variables for text/background/border/code/table/mermaid blocks.

## 7. Offline assets and JS shell

Assets:

- `Resources/Assets/viewer-shell.js`
- `Resources/Assets/mermaid.min.js` (stub)
- `Resources/Assets/mathjax.js` (stub)

Behavior:

- JS shell reads `data-enable-mermaid` and `data-enable-math` flags from `<body>`.
- Calls Mermaid and MathJax runtimes if present.
- Current Mermaid/MathJax files are bootstrap stubs and must be replaced with real vendored runtime files for production parity.

## 8. Security model

- Rust sanitizes HTML before display.
- CSP in HTML wrapper:
  - `default-src 'none'`
  - `img-src data: file:`
  - `style-src 'unsafe-inline'`
  - `script-src 'unsafe-inline'`
- Local-dev entitlements currently empty to avoid sandbox-denial issues in WebKit/Quick Look runtime.
- Hardened runtime is enabled in project settings.

Distribution profiles:

1. Local/dev profile
- Empty entitlements for easier execution.

2. Store/notarized profile
- Re-enable app sandbox and required file entitlements.
- Re-validate Quick Look and WKWebView behavior under sandbox.

## 9. Build and packaging

Workspace:

- Root `Cargo.toml` workspace: `md-engine`, `md-ffi`.

Rust build integration:

- `scripts/build_rust.sh`
  - Auto-loads `~/.cargo/env` if PATH is minimal (Xcode script phase).
  - Builds `md-ffi` (debug/release).
  - Copies artifacts to `md-viewer-macos/Vendor/`.

Xcode generation:

- `md-viewer-macos/project.yml` with targets:
  - `MDGitView`
  - `MarkdownPreviewExtension`
  - `MarkdownThumbnailExtension`
- `MDGitView` pre-build script executes `../scripts/build_rust.sh`.
- Script phase defines explicit input/output files.

Notarization helper:

- `scripts/notarize.sh` uses `xcrun notarytool`, `stapler`, `spctl`.

## 10. Tests and validation

Rust tests (`md-engine/src/lib.rs`):

- GFM tables and task list rendering.
- Local-base resource blocking behavior.
- Script tag sanitization.
- Mermaid block rewrite.
- Math text preservation.
- Unique TOC anchor generation.

Integration checks:

- `tests/integration_quicklook.sh`
  - Reloads Quick Look cache.
  - Runs preview and thumbnail generation with `qlmanage`.

Manual acceptance checklist:

1. Open `.md` file in app -> rendered output visible.
2. Dark mode text remains readable.
3. TOC click scrolls to heading.
4. Clicking local `.md` link loads target file.
5. Clicking external link opens browser.
6. `qlmanage -p` shows markdown preview.
7. `qlmanage -t` generates thumbnail.

## 11. Known gaps and implementation notes

- Mermaid and MathJax are currently stubs; replace with official offline bundles.
- Full GitHub syntax highlighting is not yet implemented.
- Quick Look activation depends on correct Info.plist extension metadata.
- Current TOC heading parser is line-based and does not parse headings hidden in fenced code blocks; replicate as-is unless intentionally improving behavior.

## 12. Reimplementation invariants

If rewriting the system, preserve these invariants to keep behavior consistent:

1. Rust is source of truth for rendered HTML + diagnostics + TOC.
2. Swift never renders unsanitized markdown directly in WebView.
3. Link policy must block parent traversal and absolute local paths.
4. WKWebView link interception must differentiate:
   - in-page anchor
   - local markdown file
   - external URL
5. TOC navigation must avoid full HTML reload for each anchor click.
6. Finder Space path uses Quick Look extensions, not custom Finder plugins.
