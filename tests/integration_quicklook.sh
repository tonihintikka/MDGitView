#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAMPLE_FILE="${ROOT_DIR}/tests/fixtures/sample.md"
OUTPUT_DIR="${ROOT_DIR}/tests/output"

mkdir -p "${OUTPUT_DIR}"

if ! command -v qlmanage >/dev/null 2>&1; then
  echo "error: qlmanage not found" >&2
  exit 1
fi

qlmanage -r
qlmanage -r cache
qlmanage -p "${SAMPLE_FILE}" >/dev/null 2>&1 || true
qlmanage -t -s 512 -o "${OUTPUT_DIR}" "${SAMPLE_FILE}" >/dev/null 2>&1 || true

echo "Quick Look integration commands executed. Check ${OUTPUT_DIR} for generated thumbnails."
