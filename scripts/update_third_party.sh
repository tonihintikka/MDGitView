#!/usr/bin/env bash
# Vendors offline third-party browser runtimes into md-viewer-macos/Resources/Assets/.
# Run after Rust dependency updates (cargo update / cargo audit) — see DEVELOPMENT.md.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="${ROOT_DIR}/md-viewer-macos/Resources/Assets"
THIRD_PARTY_DIR="${ROOT_DIR}/md-viewer-macos/Resources/ThirdParty"
VERSIONS_FILE="${THIRD_PARTY_DIR}/versions.json"

MERMAID_VERSION="${MERMAID_VERSION:-11.15.0}"
MATHJAX_VERSION="${MATHJAX_VERSION:-4.1.2}"

if ! command -v npm >/dev/null 2>&1; then
  echo "error: npm is required to download third-party runtimes." >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

download_npm_package() {
  local name="$1"
  local version="$2"
  pushd "${WORK_DIR}" >/dev/null
  npm pack "${name}@${version}" >/dev/null
  local tarball="${name}-${version}.tgz"
  tar -xzf "${tarball}"
  popd >/dev/null
  echo "${WORK_DIR}/package"
}

echo "==> Downloading mermaid@${MERMAID_VERSION}..."
MERMAID_PKG="$(download_npm_package mermaid "${MERMAID_VERSION}")"
MERMAID_SRC="${MERMAID_PKG}/dist/mermaid.min.js"
if [[ ! -f "${MERMAID_SRC}" ]]; then
  echo "error: ${MERMAID_SRC} not found in mermaid package." >&2
  exit 1
fi
cp "${MERMAID_SRC}" "${ASSETS_DIR}/mermaid.min.js"
echo "    wrote ${ASSETS_DIR}/mermaid.min.js ($(wc -c < "${ASSETS_DIR}/mermaid.min.js") bytes)"

echo "==> Downloading mathjax@${MATHJAX_VERSION}..."
MATHJAX_PKG="$(download_npm_package mathjax "${MATHJAX_VERSION}")"
MATHJAX_SRC="${MATHJAX_PKG}/tex-chtml.js"
if [[ ! -f "${MATHJAX_SRC}" ]]; then
  echo "error: ${MATHJAX_SRC} not found in mathjax package." >&2
  exit 1
fi

cat > "${ASSETS_DIR}/mathjax.js" <<'MATHJAX_CONFIG'
window.MathJax = {
  tex: {
    inlineMath: {'[+]': [['$', '$'], ['\\(', '\\)']]},
    displayMath: {'[+]': [['$$', '$$'], ['\\[', '\\]']]}
  },
  startup: {
    typeset: false
  }
};
MATHJAX_CONFIG
cat "${MATHJAX_SRC}" >> "${ASSETS_DIR}/mathjax.js"
echo "    wrote ${ASSETS_DIR}/mathjax.js ($(wc -c < "${ASSETS_DIR}/mathjax.js") bytes)"

UPDATED_ON="$(date -u +"%Y-%m-%d")"
cat > "${VERSIONS_FILE}" <<EOF
{
  "updated": "${UPDATED_ON}",
  "assets": {
    "mermaid.min.js": {
      "package": "mermaid",
      "version": "${MERMAID_VERSION}",
      "license": "MIT",
      "source": "https://www.npmjs.com/package/mermaid",
      "notes": "Bundled dist/mermaid.min.js; includes DOMPurify and other transitive deps."
    },
    "mathjax.js": {
      "package": "mathjax",
      "version": "${MATHJAX_VERSION}",
      "license": "Apache-2.0",
      "source": "https://www.npmjs.com/package/mathjax",
      "notes": "Local config preamble + tex-chtml.js (TeX input, CHTML output, fonts included)."
    }
  }
}
EOF
echo "    wrote ${VERSIONS_FILE}"

echo ""
echo "==> Third-party runtimes updated."
echo "    Next steps:"
echo "      1. Rebuild: ./scripts/install.sh"
echo "      2. Smoke-test Mermaid diagrams and \$...$ math in the viewer"
echo "      3. Check Mermaid security advisories: https://github.com/mermaid-js/mermaid/security"
