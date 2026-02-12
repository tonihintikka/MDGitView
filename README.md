# md_viewer_editor_rust

macOS Markdown viewer v1 with a Rust rendering core and SwiftUI + Quick Look integration.

## Implemented scope

- Rust renderer (`md-engine`) with:
  - GFM-oriented parsing (tables, task lists, autolinks, fenced code)
  - HTML sanitization
  - same-directory local resource policy for links/images
  - TOC generation and diagnostics
  - Mermaid code block rewrite hooks
- Rust C-ABI bridge (`md-ffi`):
  - `md_render`
  - `md_free_result`
  - `md_last_error`
- macOS app scaffold (`md-viewer-macos`) with:
  - SwiftUI viewer and file import
  - `WKWebView` rendering
  - raw markdown fallback on render errors
- Finder integration scaffold:
  - Quick Look Preview extension
  - Quick Look Thumbnail extension
- Security and release scaffolding:
  - sandbox entitlements
  - hardened runtime enabled in project config
  - notarization helper script (`scripts/notarize.sh`)

## Current limitations

- This repository includes minimal local stubs for Mermaid and MathJax runtime scripts.
- For production parity, replace them with official vendored offline distributions (see `md-viewer-macos/Resources/ThirdParty/README.md`).
- Toolchains are not currently installed in this environment (`cargo` missing, full Xcode missing), so build/test execution is not completed here.

## Project layout

- `md-engine/`: Rust markdown rendering library
- `md-ffi/`: Rust C ABI for Swift integration
- `md-viewer-macos/`: SwiftUI app + Quick Look extensions + XcodeGen config
- `scripts/`: build and notarization helper scripts
- `docs/`: security and packaging notes
- `tests/fixtures/`: markdown fixtures for manual and integration validation

## Local setup

1. Install Rust toolchain:
   - `rustup toolchain install stable`
2. Install full Xcode (not only CLT) and select it:
   - `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
3. Install XcodeGen:
   - `brew install xcodegen`
4. Build Rust artifacts:
   - `./scripts/build_rust.sh Debug`
5. Generate Xcode project:
   - `cd md-viewer-macos && xcodegen generate`
6. Open generated project and run `MDViewer` target.

## Quick Look checks

After building/installing the app and extensions:

- Preview: `qlmanage -p /path/to/file.md`
- Thumbnail: `qlmanage -t -s 512 -o /tmp /path/to/file.md`

If changes do not appear, reload Quick Look cache:

- `qlmanage -r`
- `qlmanage -r cache`
