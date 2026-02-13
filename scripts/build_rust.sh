#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-Debug}"
PROFILE="debug"
if [[ "${CONFIGURATION}" == "Release" ]]; then
  PROFILE="release"
fi

# Xcode build phases often run with a minimal PATH, so load rustup env if present.
if ! command -v cargo >/dev/null 2>&1 && [[ -f "${HOME}/.cargo/env" ]]; then
  # shellcheck disable=SC1090
  . "${HOME}/.cargo/env"
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo not found. Install Rust toolchain before building." >&2
  exit 1
fi

CARGO_BIN="$(command -v cargo)"

pushd "${ROOT_DIR}" >/dev/null
if [[ "${PROFILE}" == "release" ]]; then
  "${CARGO_BIN}" build -p md-ffi --release
else
  "${CARGO_BIN}" build -p md-ffi
fi
popd >/dev/null

TARGET_DIR="${ROOT_DIR}/target/${PROFILE}"
VENDOR_DIR="${ROOT_DIR}/md-viewer-macos/Vendor"
mkdir -p "${VENDOR_DIR}"

if [[ -f "${TARGET_DIR}/libmd_ffi.a" ]]; then
  cp "${TARGET_DIR}/libmd_ffi.a" "${VENDOR_DIR}/libmd_ffi.a"
fi
if [[ -f "${TARGET_DIR}/libmd_ffi.dylib" ]]; then
  cp "${TARGET_DIR}/libmd_ffi.dylib" "${VENDOR_DIR}/libmd_ffi.dylib"
fi

cp "${ROOT_DIR}/md-ffi/include/md_ffi.h" "${VENDOR_DIR}/md_ffi.h"

echo "Rust FFI artifacts copied to ${VENDOR_DIR}"
