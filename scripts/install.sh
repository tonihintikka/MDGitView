#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MDGitView.app"
DERIVED_DATA="${ROOT_DIR}/.deriveddata"
BUILD_DIR="${DERIVED_DATA}/Build/Products/Debug"
SOURCE_APP="${BUILD_DIR}/${APP_NAME}"
DEST_DIR="/Applications"
DEST_APP="${DEST_DIR}/${APP_NAME}"
CODE_SIGNING_ALLOWED_VALUE="${CODE_SIGNING_ALLOWED:-NO}"

# Build Rust FFI first
echo "==> Building Rust FFI..."
"${ROOT_DIR}/scripts/build_rust.sh" Debug

# Generate Xcode project
echo "==> Generating Xcode project..."
pushd "${ROOT_DIR}/md-viewer-macos" >/dev/null
xcodegen generate
popd >/dev/null

# Build the app
echo "==> Building MDGitView..."
XCODEBUILD_ARGS=(
  -project "${ROOT_DIR}/md-viewer-macos/MDGitView.xcodeproj"
  -scheme MDGitView
  -configuration Debug
  -derivedDataPath "${DERIVED_DATA}"
  "CODE_SIGNING_ALLOWED=${CODE_SIGNING_ALLOWED_VALUE}"
)

if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  XCODEBUILD_ARGS+=("DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM}")
fi

if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
  XCODEBUILD_ARGS+=("CODE_SIGN_IDENTITY=${CODE_SIGN_IDENTITY}")
fi

if [[ -n "${CODE_SIGN_STYLE:-}" ]]; then
  XCODEBUILD_ARGS+=("CODE_SIGN_STYLE=${CODE_SIGN_STYLE}")
fi

xcodebuild \
  "${XCODEBUILD_ARGS[@]}" \
  build 2>&1 | tail -5

if [ ! -d "${SOURCE_APP}" ]; then
  echo "error: Build failed — ${SOURCE_APP} not found." >&2
  exit 1
fi

# Remove old version if present
if [ -d "${DEST_APP}" ]; then
  echo "==> Removing old ${APP_NAME} from ${DEST_DIR}..."
  rm -rf "${DEST_APP}"
fi

# Copy to /Applications
echo "==> Installing ${APP_NAME} to ${DEST_DIR}..."
cp -R "${SOURCE_APP}" "${DEST_APP}"

# Reset QuickLook extensions so macOS picks up the new version
echo "==> Resetting QuickLook extension cache..."
qlmanage -r 2>/dev/null || true

echo "==> Done! ${APP_NAME} installed to ${DEST_DIR}."
echo "    Open Finder, select a .md file and press Space to test QuickLook."
