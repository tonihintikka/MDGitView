# MDGitView now

Last updated: 2026-11-16

## Current state

- Repository: `tonihintikka/MDGitView`, branch `main`.
- Current app version: 0.5.2 (`MARKETING_VERSION` in `md-viewer-macos/project.yml`).
- The main viewer uses `MarkdownResourceSchemeHandler` and the `mdgitview:` scheme for generated HTML, bundled runtime assets, and permitted local files.
- The Quick Look preview extension uses its own `QLPreviewReply` HTML flow. It does not share the main app's scheme handler.
- Mermaid diagrams and MathJax inline and display equations were visually checked in the installed app on 2026-11-16.
- The macOS test scheme passed 5 tests on 2026-11-16.
- Version 0.5.2 is published as GitHub Release `v0.5.2`: https://github.com/tonihintikka/MDGitView/releases/tag/v0.5.2. The attached `MDGitView-v0.5.2-macOS.zip` SHA-256 is `4d00893fe3973dc65ea25f227b62804ced834b535ccb49c77e420556475beb2f`.

## Immediate next steps

1. Decide whether to create a `homebrew-mdgitview` tap for a Homebrew Cask.
2. Keep the Cask version and SHA-256 aligned with the GitHub release.

## State hygiene

Keep this file short and factual. Update version, branch, release status, current verification, and next steps when they change. Durable architecture and coding constraints belong in [`docs/agent-context.md`](docs/agent-context.md). Git history and the changelog own the detailed change record.
