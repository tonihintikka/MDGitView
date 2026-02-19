# Changelog

All notable changes to MDGitView are documented here.

## [Unreleased]

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
