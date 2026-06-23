# Implementation status

## Done in this repository

- Rust markdown rendering engine with structured output (`html`, `toc`, `diagnostics`).
- C ABI wrapper for Swift integration.
- SwiftUI macOS app scaffold with markdown rendering and fallback behavior.
- Quick Look preview and thumbnail extension scaffolds.
- Security-oriented defaults: sandbox entitlements, no network entitlements, hardened runtime flag.
- Notarization helper script and setup docs.

## Remaining for full production parity

- Install missing toolchains and run full build/test loop (`cargo`, full Xcode, xcodegen).
- Add syntax highlighting runtime/theme parity with GitHub (e.g. Prism/Highlight.js assets vendored offline).
- Validate extension registration and behavior in a signed app build on target macOS versions.

## Vendored third-party runtimes (maintained)

- Mermaid and MathJax are vendored offline under `md-viewer-macos/Resources/Assets/`.
- Pinned versions: `md-viewer-macos/Resources/ThirdParty/versions.json`.
- Refresh with `./scripts/update_third_party.sh` whenever Rust deps or security advisories are reviewed — see [DEVELOPMENT.md](../DEVELOPMENT.md#dependency-updates).
