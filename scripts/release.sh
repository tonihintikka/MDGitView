#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_YML="${ROOT_DIR}/md-viewer-macos/project.yml"

# Read version from project.yml
VERSION=$(grep 'MARKETING_VERSION:' "${PROJECT_YML}" | head -1 | awk '{print $2}')
if [ -z "${VERSION}" ]; then
  echo "error: Could not read MARKETING_VERSION from project.yml" >&2
  exit 1
fi

TAG="v${VERSION}"
APP_NAME="MDGitView"
ZIP_NAME="${APP_NAME}-v${VERSION}-macOS.zip"
DERIVED_DATA="${ROOT_DIR}/.deriveddata"
BUILD_DIR="${DERIVED_DATA}/Build/Products/Release"

echo "==> Releasing ${APP_NAME} ${TAG}"

# Check gh is authenticated
if ! gh auth status >/dev/null 2>&1; then
  echo "error: GitHub CLI not authenticated. Run: gh auth login" >&2
  exit 1
fi

# Check if tag already exists
if gh release view "${TAG}" >/dev/null 2>&1; then
  echo "error: Release ${TAG} already exists. Bump MARKETING_VERSION in project.yml first." >&2
  exit 1
fi

# Build Release
echo "==> Building Rust FFI (Release)..."
"${ROOT_DIR}/scripts/build_rust.sh" Release

echo "==> Generating Xcode project..."
pushd "${ROOT_DIR}/md-viewer-macos" >/dev/null
xcodegen generate
popd >/dev/null

echo "==> Building ${APP_NAME} (Release)..."
xcodebuild \
  -project "${ROOT_DIR}/md-viewer-macos/${APP_NAME}.xcodeproj" \
  -scheme "${APP_NAME}" \
  -configuration Release \
  -derivedDataPath "${DERIVED_DATA}" \
  build 2>&1 | tail -3

if [ ! -d "${BUILD_DIR}/${APP_NAME}.app" ]; then
  echo "error: Build failed — ${APP_NAME}.app not found." >&2
  exit 1
fi

# Create zip
echo "==> Packaging ${ZIP_NAME}..."
cd "${BUILD_DIR}"
ditto -c -k --keepParent "${APP_NAME}.app" "${ROOT_DIR}/${ZIP_NAME}"

# Generate release notes from commits since last tag
echo "==> Generating release notes..."
PREV_TAG=$(git -C "${ROOT_DIR}" describe --tags --abbrev=0 2>/dev/null || echo "")
if [ -n "${PREV_TAG}" ]; then
  CHANGELOG=$(git -C "${ROOT_DIR}" log "${PREV_TAG}..HEAD" --pretty=format:"- %s" --no-merges)
else
  CHANGELOG=$(git -C "${ROOT_DIR}" log --pretty=format:"- %s" --no-merges)
fi

NOTES=$(cat <<EOF
## ${APP_NAME} ${TAG}

macOS Markdown viewer with Rust rendering core, QuickLook integration and Mermaid diagram support.

### Changes
${CHANGELOG}

### Install
1. Download \`${ZIP_NAME}\` below
2. Unzip and move \`${APP_NAME}.app\` to \`/Applications\`
3. Open the app once, then QuickLook (Space) works for \`.md\` files in Finder

### Requirements
- macOS 14.0 (Sonoma) or later

---
Created by **Toni Hintikka** together with **Codex 5.3** and **Claude Code (Opus 4.6)**.
EOF
)

# Create GitHub Release
echo "==> Creating GitHub Release ${TAG}..."
gh release create "${TAG}" \
  --title "${APP_NAME} ${TAG}" \
  --notes "${NOTES}" \
  "${ROOT_DIR}/${ZIP_NAME}"

echo ""
echo "==> Done! Release ${TAG} published:"
gh release view "${TAG}" --json url -q '.url'
