# Third-party runtime assets

This folder is intentionally included for vendored offline assets required by production parity:

- `mermaid.min.js` (official Mermaid distribution)
- `tex-mml-chtml.js` and related MathJax files

The current `Assets/mermaid.min.js` and `Assets/mathjax.js` files are minimal local stubs so the app runs without network access during bootstrap.
