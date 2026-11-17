# Security model (v1)

## Runtime boundaries

- Rendering pipeline is split:
  - Rust (`md-engine`) parses and sanitizes markdown.
  - Swift `WKWebView` displays only sanitized output.
- Local resource policy in Rust permits relative file references within the opened document base directory tree; parent traversal (`..`), absolute paths, and unsafe schemes are blocked.
- Potentially unsafe URLs (`file://`, absolute paths, custom schemes) are blocked and reported as diagnostics.

## Entitlements

- Main app: no App Sandbox entitlement in the local development build. It reads user-selected Markdown and local resources through its own scoped WebKit resource handler. It also writes rendered PDF previews to `Library/Caches/MDGitView/PreviewPDF` in the shared App Group `8C2T254JY2.mdgitview.preview`.
- Quick Look preview: App Sandbox, `com.apple.security.files.user-selected.read-only`, and access to the same App Group. It has no network-client entitlement and no absolute-path exception. It reads a recent PDF cache entry when the selected Markdown content matches; otherwise it uses its sanitized HTML response. Local images in that response are embedded as data URIs by the Rust renderer after canonical-path, format, and size checks.
- Quick Look thumbnail: App Sandbox plus `com.apple.security.files.user-selected.read-only`.
- Do not add broad filesystem or network exceptions to fix a Quick Look failure. Capture the exact WebContent or extension crash log, identify the access path, and restore the narrowest required permission only if the sandbox design allows it.

## Hardened runtime and signing

- Hardened runtime is enabled in target build settings.
- Notarization workflow is prepared via `scripts/notarize.sh`.

## No network dependency

- Viewer rendering does not require remote JS/CSS loads. The Quick Look preview's CSP blocks all remote loads and scripts.
- PDF cache output is created by the main app's local WebKit renderer. Cache keys include the canonical source path and Markdown content digest; entries include the build version, expire after five minutes, and total cache writes stop at 250 MiB. The extension cannot verify sibling image changes in its sandbox, so cached image output can be stale for up to five minutes. Reopening or refreshing the document regenerates it.
- Mermaid and MathJax runtimes are vendored and signed inside app resources.
- When updating dependencies, refresh vendored JS with `./scripts/update_third_party.sh` and review [Mermaid security advisories](https://github.com/mermaid-js/mermaid/security). See `md-viewer-macos/Resources/ThirdParty/versions.json`.
