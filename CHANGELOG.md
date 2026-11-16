# Changelog

All notable changes to MDGitView are documented here.

## [0.5.2] - 2026-11-16

### Added
- Serve the main viewer's generated HTML, local resources, and bundled runtime assets through a custom `mdgitview:` URL scheme, without writing preview HTML into user folders.
- Bundle MathJax CHTML font assets locally so math rendering works without network access.

### Fixed
- Double-clicking a Markdown file in Finder now opens it in MDGitView's single main window instead of creating two viewer windows.
- File-open events received during app startup are queued until the main view is ready.
- Local WebKit resources are resolved through the document's allowed root directory and checked for path traversal and symlinks.

### Changed
- Update the vendored MathJax runtime and its update workflow.
- Update Rust dependency lockfile.

## [0.5.1] - 2026-02-19

### Fixed
- Mermaid diagrams now display fully without clipping in the default view
- Default view restores Mermaid's native responsive scaling (`width="100%"`, `max-width` style)
- Interactive zoom/pan mode only activates when the Tools button is pressed
- Closing Tools panel restores the diagram to its original native layout

## [0.5.0] - 2025-01-xx

### Added
- Interactive Mermaid viewport controls: zoom, pan, fit, reset
- Toggleable Tools panel (zoom in/out, directional pan, wheel zoom, fit to viewport)
- Quick Look preview extension
- Default app association support

### Changed
- Mermaid diagrams now render inside a viewport container when Tools are active

## [0.4.0]

### Added
- Quick Look preview with "Open in MDGitView" button
- Toolbar actions (refresh, open in editor, reveal in Finder)

## [0.3.1]

### Security
- Nonce-based CSP headers
- External resource warnings
- WebView lockdown hardening

## [0.3.0]

### Added
- About window and Help menu
- Code signing enabled

## Earlier versions

- 0.2.x: Mermaid diagram support, dark mode theming, install script
- 0.1.x: Initial scaffold, Rust renderer, local image support
