# Agent context

Read this file before changing MDGitView. It captures stable product and engineering decisions; use Git history and `now.md` for current work.

## Product

MDGitView is a local-first macOS Markdown viewer. It includes a SwiftUI application, a Rust Markdown renderer, a Quick Look preview extension, and a Quick Look thumbnail extension. It is a viewer, not an editor. Rendering must work offline.

## Repository map

- `md-engine/`: Markdown parsing, HTML generation, resource policy, sanitization, TOC, and diagnostics.
- `md-ffi/`: C ABI around `md-engine`.
- `md-viewer-macos/App/`: SwiftUI app, app delegate, view model, and file opening.
- `md-viewer-macos/Shared/`: Swift FFI wrapper, render models, HTML builder, WebKit view, and main-app resource scheme handler.
- `md-viewer-macos/PreviewExtension/`: Quick Look full preview. It builds an HTML response through Quick Look APIs.
- `md-viewer-macos/ThumbnailExtension/`: Quick Look thumbnail generation.
- `md-viewer-macos/Resources/Assets/`: CSS and vendored Mermaid and MathJax resources, including CHTML fonts.
- `md-viewer-macos/project.yml`: XcodeGen source of truth for targets, bundle identifiers, and app version.
- `scripts/`: Rust build, install, release, notarization, and third-party update workflows.
- `tests/fixtures/`: Markdown fixtures.
- `docs/`: architecture, security, replication, distribution, and status documentation.

## Runtime architecture

1. Swift reads the selected Markdown file as UTF-8 and builds Rust `RenderOptions` with its containing directory and an allowed root (the Git repository root when available).
2. `md-engine` parses Markdown with `pulldown-cmark`, rewrites Mermaid fences when enabled, assigns heading IDs and builds TOC entries from the same parsed event stream, applies local-resource checks, sanitizes HTML with `ammonia`, and returns HTML, TOC entries, and diagnostics.
3. `md-ffi` catches Rust panics at the C boundary and keeps the last error per calling thread. Successful renders clear that error. Swift must free every returned C string with `md_free_result`.
4. `MarkdownRenderService` wraps sanitized HTML with CSP, theme classes, and `mdgitview://runtime/...` asset URLs.
5. In the main app, `MarkdownWebView` registers a per-document identifier with `MarkdownResourceSchemeHandler`. It serves the HTML as `text/html`, bundled CSS/JS/fonts from the app bundle, and local document resources only under the registered allowed root. Generated HTML is not written beside the user's Markdown file.
6. WebKit link policy routes Markdown files back to the app, keeps in-page anchors in the current document, and opens external links through the system browser.

Quick Look is a separate execution environment. The preview extension shares the Rust renderer but provides HTML using `QLPreviewReply`; it does not use the main app's `WKURLSchemeHandler` or runtime JavaScript. Its CSP blocks scripts and remote loads. Rust embeds local PNG, JPEG, GIF, and WebP images only when canonical paths remain under the Markdown file's directory; caps are 2 MiB per image and 10 MiB total. Remote, disallowed, or unreadable images become visible text placeholders. A policy-approved sibling image may still be unreadable under the Quick Look sandbox; canonical containment does not grant OS access. Mermaid and math sources remain visible with notices that point users to the full MDGitView app. The extension's entitlements include the app sandbox, user-selected read-only files, and the shared preview-cache App Group.

After MDGitView renders a Markdown file, `PreviewPDFRenderer` uses the same bundled local CSS, Mermaid, MathJax, and resource scheme to create a PDF. `PreviewPDFCache` stores it under the `8C2T254JY2.mdgitview.preview` App Group. The cache key binds the standardized source path and Markdown bytes; its manifest also checks the build version and a five-minute expiry. Writes use a cross-process file lock and atomic file replacement. Cache writes stop at 250 MiB, so the HTML path remains the fallback when no valid PDF is available. The extension returns a cached PDF through `QLPreviewReply(fileURL:)`; it does not execute JavaScript. Because it cannot inspect sibling image files, an image can change while its PDF remains valid for up to five minutes.

## Security and behavior constraints

- Keep rendering offline. Do not add remote scripts, stylesheets, fonts, or implicit network fetches.
- Treat Markdown as untrusted input. Preserve Rust-side sanitization and diagnostics, the Swift-generated CSP, and the local-resource boundary.
- The main app resource handler must reject path traversal, malformed/encoded paths, symlink escapes, unknown document IDs, and files outside the allowed root. Keep MIME types correct, especially `text/html` for documents and JavaScript, CSS, image, and font types for assets.
- Do not write generated preview HTML into a user-controlled document directory.
- Keep resource registration scoped to a WebView document and unregister it when replaced or when the coordinator is released.
- Preserve Finder file-open queueing through `AppDelegate` and the single-window SwiftUI `Window` scene. Avoid parallel open handlers that can open a file twice.
- Mermaid's interactive controls are opt-in through the Tools UI; preserve Mermaid's responsive native layout by default.
- Bundle MathJax CHTML fonts and dynamic assets locally; test inline and display math after asset updates.

## Build, test, and release

- Requirements: macOS 14+, full Xcode, Rust stable, and XcodeGen 2.38+.
- `scripts/build_rust.sh Debug` builds the Rust static library and copies it to `md-viewer-macos/Vendor/` (generated, ignored output).
- `cd md-viewer-macos && xcodegen generate` creates the ignored Xcode project from `project.yml`.
- Main app tests: `xcodebuild -project md-viewer-macos/MDGitView.xcodeproj -scheme MDGitView -destination 'platform=macOS,arch=arm64' test`.
- `scripts/install.sh` builds Debug and replaces `/Applications/MDGitView.app`.
- Set `MARKETING_VERSION` and increment `CURRENT_PROJECT_VERSION` in `project.yml` before release. Update `CHANGELOG.md` and `now.md` too.
- `scripts/release.sh` builds Release, creates `MDGitView-v<version>-macOS.zip`, and creates a GitHub release/tag using `gh`. It requires an authenticated GitHub CLI and a version tag that does not already exist.
- Do not include generated archives, `default.profraw`, `.deriveddata`, or `Vendor/` build output in source commits unless a release workflow explicitly requires an archive as a release asset.

## Documentation ownership

- `now.md`: short-lived current branch/version/release/verification state.
- This file: durable product, architecture, and safety invariants.
- `docs/ai-implementation-spec.md`: detailed implementation contracts for rebuilding the system.
- `docs/ai-replication-playbook.md`: ordered implementation and verification plan.
- `CHANGELOG.md`: user-visible changes by release.
- Git history: exact code evolution.

When sources disagree, prefer implementation in the current branch, then `project.yml` for version/build settings. Update the affected documentation in the same change.
