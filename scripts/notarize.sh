#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 5 ]]; then
  cat <<USAGE
Usage: $0 <app-path> <bundle-id> <apple-id> <team-id> <app-password>

Example:
  $0 build/MDViewer.app com.toni.mdviewer you@example.com TEAM1234 abcd-efgh-ijkl-mnop
USAGE
  exit 1
fi

APP_PATH="$1"
BUNDLE_ID="$2"
APPLE_ID="$3"
TEAM_ID="$4"
APP_PASSWORD="$5"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "error: xcrun not found" >&2
  exit 1
fi

ZIP_PATH="${APP_PATH%/}.zip"

ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

xcrun notarytool submit "$ZIP_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_PASSWORD" \
  --wait

xcrun stapler staple "$APP_PATH"

spctl --assess --type execute --verbose "$APP_PATH"

echo "Notarization and stapling completed for ${APP_PATH}"
