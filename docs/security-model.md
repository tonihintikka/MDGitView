# Security model (v1)

## Runtime boundaries

- Rendering pipeline is split:
  - Rust (`md-engine`) parses and sanitizes markdown.
  - Swift `WKWebView` displays only sanitized output.
- Local resource policy in Rust permits relative file references within the opened document base directory tree; parent traversal (`..`), absolute paths, and unsafe schemes are blocked.
- Potentially unsafe URLs (`file://`, absolute paths, custom schemes) are blocked and reported as diagnostics.

## Entitlements

- Local development profile currently uses empty entitlements for app and extensions to avoid WebKit WebContent sandbox-denial crashes in Quick Look extension runtime.
- For App Store distribution, re-enable `com.apple.security.app-sandbox` and required file-access entitlements, then re-validate Quick Look behavior under sandbox.

## Hardened runtime and signing

- Hardened runtime is enabled in target build settings.
- Notarization workflow is prepared via `scripts/notarize.sh`.

## No network dependency

- Viewer rendering does not require remote JS/CSS loads.
- Mermaid and MathJax runtimes are vendored and signed inside app resources.
- When updating dependencies, refresh vendored JS with `./scripts/update_third_party.sh` and review [Mermaid security advisories](https://github.com/mermaid-js/mermaid/security). See `md-viewer-macos/Resources/ThirdParty/versions.json`.
