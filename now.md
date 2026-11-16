# MDGitView now

Last updated: 2026-11-16

## Current state

- Repository: `tonihintikka/MDGitView`, branch `main`.
- Current app version: 0.5.2 (`MARKETING_VERSION` in `md-viewer-macos/project.yml`).
- The main viewer uses `MarkdownResourceSchemeHandler` and the `mdgitview:` scheme for generated HTML, bundled runtime assets, and permitted local files.
- The Quick Look preview extension uses its own `QLPreviewReply` HTML flow. It does not share the main app's scheme handler.
- Mermaid diagrams and MathJax inline and display equations were visually checked in the installed app on 2026-11-16.
- The macOS test scheme passed 5 tests on 2026-11-16.
- A GitHub release for 0.5.2 is the next release action after the version and documentation commit is pushed.

## Immediate next steps

1. Commit and push the documentation and version update.
2. Build and publish `v0.5.2` with `scripts/release.sh`, then verify the GitHub release and zip asset.
3. Decide whether to create or use a `homebrew-mdgitview` tap for a Homebrew Cask.

## State hygiene

Keep this file short and factual. Update version, branch, release status, current verification, and next steps when they change. Durable architecture and coding constraints belong in [`docs/agent-context.md`](docs/agent-context.md). Git history and the changelog own the detailed change record.
