# MDGitView now

Last updated: 2026-11-17

## Current state

- Repository: `tonihintikka/MDGitView`, branch `main`.
- Current app version: 0.5.2 (`MARKETING_VERSION` in `md-viewer-macos/project.yml`).
- The main viewer uses `MarkdownResourceSchemeHandler` and the `mdgitview:` scheme for generated HTML, bundled runtime assets, and permitted local files.
- The Quick Look preview extension returns a recent PDF from the shared App Group cache when one matches the selected Markdown file. A cache miss uses its HTML flow; it does not share the main app's scheme handler.
- Mermaid diagrams and MathJax inline and display equations were visually checked in the main viewer on 2026-11-17.
- The macOS test scheme passed 5 tests on 2026-11-16.
- Version 0.5.2 is published as GitHub Release `v0.5.2`: https://github.com/tonihintikka/MDGitView/releases/tag/v0.5.2. The attached `MDGitView-v0.5.2-macOS.zip` SHA-256 is `4d00893fe3973dc65ea25f227b62804ced834b535ccb49c77e420556475beb2f`.
- The Quick Look, TOC, and FFI changes are implemented. The Rust suite passes 17 tests, and the macOS test scheme passes 5 tests. The preview extension has sandbox and user-selected read-only entitlements, plus App Group access. It has no network or broad filesystem exception.
- Finder previously selected Obsidian's competing Quick Look extension. Toni approved leaving `md.obsidian.quicklook` disabled and MDGitView enabled. The App Group lookup was approved for the signed preview extension.

- Visual verification: Mermaid flowchart, inline math, and display math render in the main viewer. Quick Look renders sanitized HTML on a cache miss and shows Mermaid/math source notices. Its remote-image test made zero requests to the local HTTP fixture server.
- Use `/usr/bin/log` when diagnosing on zsh: `log` is a shell builtin, so previous unqualified log queries were invalid evidence.

## Current validation gap

The extension launched and received App Group access in the latest `qlmanage` run, but no cache hit/miss message appeared and a cached PDF response has not been visually verified in Finder. The App Group directory is not readable from the shell session. The earlier PDF proof of concept is at `output/pdf/sample-preview.pdf`.

## Immediate next steps

1. Verify cache generation, hit, and miss behavior in Finder. The cache hit remains unconfirmed.
2. The four requested commits are on `main`. Do not publish a release or push without a separate request.

## State hygiene

Keep this file short and factual. Update version, branch, release status, current verification, and next steps when they change. Durable architecture and coding constraints belong in [`docs/agent-context.md`](docs/agent-context.md). Git history and the changelog own the detailed change record.
