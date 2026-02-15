# AI Replication Playbook

This playbook defines exact execution steps for an AI agent to recreate this project.

## 1. Environment prerequisites

- macOS 14+
- Full Xcode installed and selected:
  - `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
- Rust toolchain via rustup.
- XcodeGen installed (`brew install xcodegen`).

Verification:

- `xcodebuild -version`
- `rustc --version`
- `cargo --version`
- `xcodegen --version`

## 2. Bootstrap repository

Create directories:

- `md-engine/src`
- `md-ffi/src`
- `md-ffi/include`
- `md-viewer-macos/{App,Shared,PreviewExtension,ThumbnailExtension,Config,Resources/Assets,Resources/ThirdParty,Vendor}`
- `scripts`
- `tests/fixtures`
- `docs`

## 3. Implement Rust workspace

1. Root Cargo workspace with members:
- `md-engine`
- `md-ffi`

2. `md-engine` dependencies:
- `pulldown-cmark`
- `regex`
- `serde`, `serde_json`
- `thiserror`
- `ammonia`

3. Implement APIs:
- `RenderOptions`
- `RenderedDocument`
- `TocItem`
- `Diagnostic`
- `render_markdown`

4. Implement renderer pipeline exactly in this order:
- Parse markdown.
- Mermaid block rewrite.
- TOC build.
- Local-base resource policy.
- HTML sanitization.
- Heading ID injection.

5. Add Rust unit tests for:
- tables/task lists
- local link blocking
- script sanitization
- mermaid rewrite
- math passthrough
- unique toc anchors

Definition of done:

- `cargo test -p md-engine` passes.

## 4. Implement FFI crate (`md-ffi`)

1. `crate-type = ["cdylib", "staticlib"]`
2. Expose C ABI:
- `md_render`
- `md_free_result`
- `md_last_error`
3. Use JSON request/response payloads.
4. Add thread-safe last-error storage with thread-local snapshot pointer return.
5. Add C header `md_ffi.h`.

Definition of done:

- `cargo build -p md-ffi` succeeds.

## 5. Implement Swift shared layer

Files to create:

- `Shared/RenderModels.swift`
- `Shared/RustMarkdownFFI.swift`
- `Shared/MarkdownRenderService.swift`
- `Shared/MarkdownLinkPolicy.swift`
- `Shared/MarkdownWebView.swift`

Critical requirements:

- FFI bridge uses `@_silgen_name` for C functions.
- Markdown render service returns full HTML document wrapper.
- Resource loader must check both:
  - `Assets/` subdirectory
  - bundle root fallback
- WebView must intercept links and route by type.
- WebView must support anchor navigation without forced reload each state update.

## 6. Implement app target

Files:

- `App/MDGitViewApp.swift`
- `App/ViewerViewModel.swift`
- `App/ContentView.swift`

Requirements:

- File importer for `.md` and `.markdown`.
- Sidebar TOC and diagnostics.
- TOC rows must be clickable and trigger anchor scroll.
- External links open via `NSWorkspace.shared.open`.
- Local markdown links trigger `openDocument(at:)`.
- Fallback raw markdown view when renderer fails.

## 7. Implement Quick Look targets

Preview extension:

- `PreviewExtension/MarkdownPreviewViewController.swift`
- Implement `QLPreviewProvider` + `QLPreviewingController`.
- Reuse same `MarkdownRenderService`.
- Return HTML via `QLPreviewReply` in `providePreview(for:completionHandler:)`.

Thumbnail extension:

- `ThumbnailExtension/MarkdownThumbnailProvider.swift`
- Draw thumbnail from extracted heading/title.

## 8. Configure Xcode project via XcodeGen

Create `md-viewer-macos/project.yml`:

- Targets:
  - `MDGitView` application
  - `MarkdownPreviewExtension` app-extension
  - `MarkdownThumbnailExtension` app-extension
- Add pre-build script for Rust build.
- Add script input/output files so Xcode can track dependency graph.
- Link against `Vendor/libmd_ffi`.

Generate project:

- `cd md-viewer-macos && xcodegen generate`

## 9. Integrate build scripts

Implement:

- `scripts/build_rust.sh`
  - Auto-source `~/.cargo/env` if `cargo` missing in PATH.
  - Build `md-ffi` in debug/release.
  - Copy artifacts to `md-viewer-macos/Vendor`.
- `scripts/notarize.sh`
  - Zip, submit to notarytool, staple, assess.

## 10. Add resources

Add assets:

- `Resources/Assets/github-markdown.css`
- `Resources/Assets/viewer-shell.js`
- `Resources/Assets/mermaid.min.js` (bootstrap stub)
- `Resources/Assets/mathjax.js` (bootstrap stub)

Requirements:

- CSS includes dark mode support.
- JS shell executes Mermaid/MathJax only when enabled via body data attributes.

## 11. Security and entitlements

Local-dev profile:

- Empty entitlements are allowed to reduce WebKit sandbox-denial issues in dev runtime.

Production profile:

- Re-enable app sandbox and required file access entitlements.
- Re-test Quick Look extensions under sandbox.

## 12. Finder Space activation requirements

Ensure Info.plist metadata contains Quick Look extension definitions:

- `NSExtensionPointIdentifier`
- `NSExtensionPrincipalClass`
- `QLSupportedContentTypes`

Ensure Markdown document types are registered for app open-in-viewer behavior.

## 13. Validation commands

Rust:

- `cargo test -p md-engine`
- `./scripts/build_rust.sh`

macOS app build:

- `xcodebuild -project md-viewer-macos/MDGitView.xcodeproj -scheme MDGitView -configuration Debug -sdk macosx -derivedDataPath .deriveddata CODE_SIGNING_ALLOWED=NO build`

Quick Look smoke tests:

- `./tests/integration_quicklook.sh`

## 14. Final acceptance criteria

System is considered equivalent when:

1. Markdown renders in app with light/dark readability.
2. TOC click scrolls to correct heading anchor.
3. Markdown links between local files work.
4. External links open in browser.
5. Diagnostic list displays blocked links/images.
6. Quick Look preview opens via Space.
7. Finder thumbnail appears for markdown files.
8. Rust tests pass.
