# md-viewer-macos

SwiftUI app + Quick Look extensions for the Rust-based Markdown renderer.

## Generate Xcode project

```bash
cd md-viewer-macos
xcodegen generate
```

The generated project contains targets:

- `MDGitView` (app)
- `MarkdownPreviewExtension` (Space preview)
- `MarkdownThumbnailExtension` (Finder thumbnails)

## Build flow

1. Pre-build script runs `../scripts/build_rust.sh`.
2. Rust `md-ffi` artifacts are copied to `md-viewer-macos/Vendor`.
3. Swift targets link `libmd_ffi` from `Vendor`.

## Resource notes

`Resources/Assets/` currently contains bootstrap CSS/JS and local runtime stubs.
Replace stubs with vendored Mermaid/MathJax distributions for production parity.

## Test Quick Look (Space / thumbnails)

1. Build app target once:
```bash
xcodebuild -project MDGitView.xcodeproj -scheme MDGitView -configuration Debug -derivedDataPath ../.deriveddata CODE_SIGNING_ALLOWED=NO build
```
2. Reset Quick Look plugin cache:
```bash
qlmanage -r
qlmanage -r cache
```
3. Test preview from terminal:
```bash
qlmanage -p /absolute/path/to/file.md
```
4. Test thumbnail generation:
```bash
qlmanage -t -s 512 -o /tmp /absolute/path/to/file.md
```
5. Finder-test:
- Open Finder to a folder with `.md` files.
- Press `Space` on a file.

If Finder still shows stale behavior, quit Finder and reopen:
```bash
killall Finder
```

## App icon

Generate/update app icon assets:
```bash
../scripts/generate_app_icon.sh
```

The script writes:
- `Resources/Assets.xcassets/AppIcon.appiconset/*`

After that, regenerate/build:
```bash
cd md-viewer-macos
xcodegen generate
```
