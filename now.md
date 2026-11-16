# MDGitView now

Last updated: 2026-11-16

## Current state

- Repository: `tonihintikka/MDGitView`, branch `main`.
- Current app version: 0.5.2 (`MARKETING_VERSION` in `md-viewer-macos/project.yml`).
- The main viewer uses `MarkdownResourceSchemeHandler` and the `mdgitview:` scheme for generated HTML, bundled runtime assets, and permitted local files.
- The Quick Look preview extension uses its own `QLPreviewReply` HTML flow. It does not share the main app's scheme handler.
- Mermaid diagrams and MathJax inline and display equations were visually checked in the installed app on 2026-11-16.
- The macOS test scheme passed 5 tests on 2026-11-16.
- Source and documentation for 0.5.2 are pushed (`cda44ec`). The Release build and ZIP package succeeded, but GitHub rejected release creation because the active `gh` account has read access to the repository. The local ZIP is `MDGitView-v0.5.2-macOS.zip` (SHA-256: `f941a51dc082e3e1f764b0469be7b3bc24bcbb940f1931ed65432c1f32baeb04`).

## Immediate next steps

1. Authenticate `gh` as an account with write access to `tonihintikka/MDGitView`, then create the `v0.5.2` release and upload the existing ZIP (or rerun `scripts/release.sh`).
2. Verify the GitHub release and ZIP asset.
3. Decide whether to create or use a `homebrew-mdgitview` tap for a Homebrew Cask.

## State hygiene

Keep this file short and factual. Update version, branch, release status, current verification, and next steps when they change. Durable architecture and coding constraints belong in [`docs/agent-context.md`](docs/agent-context.md). Git history and the changelog own the detailed change record.
