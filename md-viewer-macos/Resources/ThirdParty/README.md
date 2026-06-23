# Third-party runtime assets

Offline browser runtimes vendored into `Resources/Assets/`:

| File | Package | Purpose |
|------|---------|---------|
| `mermaid.min.js` | [mermaid](https://www.npmjs.com/package/mermaid) | Diagram rendering |
| `mathjax.js` | [mathjax](https://www.npmjs.com/package/mathjax) | TeX math typesetting (config + `tex-chtml.js`) |

Pinned versions live in [`versions.json`](versions.json).

## Updating

When refreshing project dependencies, **also review these vendored runtimes** — they are not managed by Cargo.

```bash
# Default: mermaid@11.15.0, mathjax@4.1.2
./scripts/update_third_party.sh

# Or pin explicit versions
MERMAID_VERSION=11.15.0 MATHJAX_VERSION=4.1.2 ./scripts/update_third_party.sh
```

Requires `npm`. After updating:

1. Rebuild the app (`./scripts/install.sh` or Xcode).
2. Smoke-test a `.md` file with a Mermaid diagram and inline math (`$E=mc^2$`).
3. Check [Mermaid security advisories](https://github.com/mermaid-js/mermaid/security) for the target version.

See [DEVELOPMENT.md](../../../DEVELOPMENT.md#dependency-updates) for the full maintenance checklist (Rust + Apple SDK + third-party JS).

## Licensing

- **Mermaid** — MIT. Bundled dependencies (e.g. DOMPurify, cytoscape) ship inside `mermaid.min.js`.
- **MathJax** — Apache-2.0.

Credits and version details are also recorded in the root [README.md](../../../README.md).
