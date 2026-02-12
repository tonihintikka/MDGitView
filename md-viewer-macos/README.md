# md-viewer-macos

SwiftUI app + Quick Look extensions for the Rust-based Markdown renderer.

## Generate Xcode project

```bash
cd md-viewer-macos
xcodegen generate
```

The generated project contains targets:

- `MDViewer` (app)
- `MarkdownPreviewExtension` (Space preview)
- `MarkdownThumbnailExtension` (Finder thumbnails)

## Build flow

1. Pre-build script runs `../scripts/build_rust.sh`.
2. Rust `md-ffi` artifacts are copied to `md-viewer-macos/Vendor`.
3. Swift targets link `libmd_ffi` from `Vendor`.

## Resource notes

`Resources/Assets/` currently contains bootstrap CSS/JS and local runtime stubs.
Replace stubs with vendored Mermaid/MathJax distributions for production parity.
