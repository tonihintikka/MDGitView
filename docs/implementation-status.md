# Implementation status

Last reviewed: 2026-11-16

## Implemented

- SwiftUI macOS viewer with single-window Finder file opening, navigation history, TOC, diagnostics, refresh, editor, and Finder actions.
- Rust renderer and C ABI bridge.
- GFM tables, task lists, strikethrough, footnotes, smart punctuation, Mermaid fence conversion, heading anchors, HTML sanitization, and local-resource diagnostics.
- Main-app WebKit resource serving through `MarkdownResourceSchemeHandler` and `mdgitview:` URLs. Generated preview HTML is kept out of user folders.
- Bundled Mermaid and MathJax runtimes, with MathJax CHTML fonts available locally.
- Quick Look preview and thumbnail extension targets.
- Debug install and GitHub zip release scripts.

## Verified on 2026-11-16

- Xcode test scheme: 5 tests passed.
- Installed app launched successfully.
- Mermaid flowchart, MathJax inline equation, and display integral rendered in the installed app with no diagnostics warnings.

## Distribution notes

- App version: see `MARKETING_VERSION` in `md-viewer-macos/project.yml`.
- GitHub Releases are produced by `scripts/release.sh`.
- A Homebrew Cask tap has not been created yet.
- `scripts/release.sh` does not sign, notarize, or staple a Developer ID release.
