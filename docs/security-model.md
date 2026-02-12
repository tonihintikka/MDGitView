# Security model (v1)

## Runtime boundaries

- Rendering pipeline is split:
  - Rust (`md-engine`) parses and sanitizes markdown.
  - Swift `WKWebView` displays only sanitized output.
- Local resource policy in Rust permits relative file references only when the path resolves to the same directory as the opened markdown file.
- Potentially unsafe URLs (`file://`, absolute paths, custom schemes) are blocked and reported as diagnostics.

## Entitlements

- App target (`MDViewer`) uses:
  - `com.apple.security.app-sandbox = true`
  - `com.apple.security.files.user-selected.read-only = true`
- Quick Look extensions use sandbox entitlement and no network entitlement.

## Hardened runtime and signing

- Hardened runtime is enabled in target build settings.
- Notarization workflow is prepared via `scripts/notarize.sh`.

## No network dependency

- Viewer rendering does not require remote JS/CSS loads.
- Mermaid/Math runtimes are expected to be vendored and signed inside app resources.
