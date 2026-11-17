# Task: fix Quick Look preview, TOC anchors and FFI robustness

Written 2026-11-16 from a code review in Claude Code. Read `docs/agent-context.md` and `now.md` first. Findings below cite files; the ones marked **verified** were checked on the installed app, the rest come from reading the code and must be reproduced before fixing.

Toni's own Quick Look symptoms (fill in before starting): ...

Work in four separate commits, in this order. Do not publish a release; Toni decides when 0.5.3 ships.

## 1. Quick Look preview extension

### Findings

- **Verified** (`codesign -d --entitlements - /Applications/MDGitView.app/Contents/PlugIns/MarkdownPreviewExtension.appex`): the preview extension has `com.apple.security.network.client` and `com.apple.security.temporary-exception.files.absolute-path.read-only = ["/"]`. Source: `md-viewer-macos/Config/MarkdownPreviewExtension.entitlements`. An offline viewer has no use for network access, and the `/` exception makes the sandbox meaningless.
- `docs/security-model.md` says the extensions use empty entitlements. That is wrong for the current build.
- `PreviewExtension/MarkdownPreviewViewController.swift` builds HTML without a Content-Security-Policy. The main app has `default-src 'none'` (`Shared/MarkdownRenderService.swift`).
- `md-engine` allows `http(s)` image URLs (`is_allowed_resource`). Together with the points above, pressing Space on an untrusted `.md` file may fetch remote images (tracking pixel, IP leak). Not yet tested whether Quick Look actually performs the fetch.
- The preview reply is a `data:` HTML blob with no base URL, so relative images (`![x](img/a.png)`) cannot resolve. Mermaid and MathJax are disabled in the preview (`enable_mermaid: false`, `enable_math: false`), so diagrams show as raw text without explanation. The `.ql-mermaid-notice` CSS class exists but nothing uses it.
- `contentSize` is fixed at 1200 × 2400.

### What to do

1. Reproduce first. Run `qlmanage -p tests/fixtures/sample.md` and `qlmanage -p tests/fixtures/large.md`, plus a new fixture with a remote image, a relative image, a Mermaid block and math. Watch network activity during the remote-image preview (`nettop -p <QuickLookUIService pid>` or similar). Write down what you see before changing anything.
2. Remove `network.client` and the `/` exception from the preview entitlements. Keep the sandbox on.
3. Add a CSP meta tag to the preview HTML: no scripts, no remote loads; `img-src data:`; inline styles allowed.
4. Relative images: embed permitted local images as `data:` URIs, limited to files under the document's directory (reuse the engine's resource policy) with a size cap (suggest 2 MB per image, 10 MB total). Remote images: replace with a visible placeholder showing the URL. Decide whether embedding belongs in Rust (preferred, testable) or Swift, and explain the choice in the commit message.
5. Mermaid and math: show the source in a code block with the existing `.ql-mermaid-notice` text ("Diagram rendered in MDGitView app"). Do not load JavaScript in the preview.
6. If removing the entitlements brings back the WebKit WebContent sandbox crashes that `security-model.md` mentions, stop and report the exact crash log instead of re-adding broad exceptions.
7. Update `docs/security-model.md` to match the real entitlements of all three targets.

### Done when

- `codesign` output for the preview extension shows only the sandbox and `files.user-selected.read-only` (or less).
- No network activity during preview of the remote-image fixture.
- Relative images inside the document folder render in the preview; images outside it do not.
- `sample.md` and `large.md` preview without crash. Record preview time for `large.md` before and after.

## 2. TOC and heading anchors

### Findings (from code, not yet tested)

`md-engine/src/lib.rs`, `collect_toc` scans raw lines starting with `#`, and `inject_heading_ids` matches TOC entries to HTML headings by order and level. Consequences:

- A `# comment` line inside a fenced code block becomes a TOC entry; later headings of the same level can receive the wrong `id`.
- Setext headings (`Title` + `----` or `====`) are missing from the TOC, and can receive a duplicate `id`.
- `slugify` drops all non-ASCII characters: "Käyttö" becomes `kytt`, "Äänestys" becomes `nestys`. GitHub keeps Unicode letters, so GitHub-style links to Finnish headings (`#käyttö`) do not work.
- `#hashtag` without a space is counted as a heading although CommonMark does not treat it as one.

### What to do

1. Add failing tests for each case above first.
2. Collect headings from pulldown-cmark events (`Event::Start(Tag::Heading)` … `End`) in the same pass that produces HTML, and set the `id` there. Remove the regex-based `inject_heading_ids`.
3. Make slugs GitHub-compatible: lowercase, keep Unicode letters and digits, spaces to `-`, drop other punctuation, `-1`, `-2` suffixes for duplicates. Keep the `user-content-` prefix as now.
4. Check that `viewer-shell.js` anchor handling still works with non-ASCII anchors (percent-encoded fragments).

### Done when

All new tests pass, the existing 8 engine tests pass, and a document with Finnish headings and bash code comments has a correct TOC in the app.

## 3. FFI robustness

`md-ffi/src/lib.rs`:

- Wrap the body of `md_render` in `std::panic::catch_unwind`; on panic, set the last error and return null. Today a renderer panic aborts the app or the Quick Look process.
- Make the last error per thread (the preview and thumbnail extensions can render concurrently) and clear it on success.
- Add a Rust test that a panic inside rendering returns null with an error message (use a test-only hook if needed).

## 4. Small cleanups

- `App/ViewerViewModel.swift`: the doc comment on `requestFolderAccess` still talks about writing a temp file. Update it to describe the scheme-handler access-denied path, or remove the flow if it can no longer trigger in the non-sandboxed app (check and say which).
- `ViewerViewModel`: `openDocument` and `reloadCurrentDocument` duplicate the code that applies a render result. Extract one method.
- `RenderOptions.enable_math` has no effect in `md-engine`. Either use it or document that math is client-side only.
- `ENABLE_SMART_PUNCTUATION` turns `--` and quotes into typographic characters, which GitHub does not do. Turn it off to match GitHub rendering.

## Out of scope

- Auto-reload on file change (separate task).
- Sandboxing the main app.
- Homebrew tap.

## Process

- Run `cargo test` and `xcodebuild -project md-viewer-macos/MDGitView.xcodeproj -scheme MDGitView -destination 'platform=macOS,arch=arm64' test` before each commit.
- Install with `scripts/install.sh` and check Quick Look by hand after task 1.
- Update `CHANGELOG.md` (Unreleased section), `now.md` and `docs/agent-context.md` where invariants change.
- Report back: what the Quick Look reproduction showed, what changed, what you could not verify.
