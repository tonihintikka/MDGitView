#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCE_DIR="${ROOT_DIR}/md-viewer-macos/Resources"
ASSETCATALOG_DIR="${RESOURCE_DIR}/Assets.xcassets"
APPICONSET_DIR="${ASSETCATALOG_DIR}/AppIcon.appiconset"
BASE_PNG="${APPICONSET_DIR}/icon_512x512@2x.png"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-${ROOT_DIR}/.cache/clang}"
export SWIFT_MODULE_CACHE_PATH="${SWIFT_MODULE_CACHE_PATH:-${CLANG_MODULE_CACHE_PATH}}"
mkdir -p "${CLANG_MODULE_CACHE_PATH}"

mkdir -p "${APPICONSET_DIR}"

SWIFT_FILE="$(mktemp /tmp/mdgitview-icon.XXXXXX)"
cat > "${SWIFT_FILE}" <<'EOF'
import AppKit

let side: CGFloat = 1024
let image = NSImage(size: NSSize(width: side, height: side))
image.lockFocus()

let full = NSRect(x: 0, y: 0, width: side, height: side)
let background = NSBezierPath(roundedRect: full, xRadius: 224, yRadius: 224)

NSColor(calibratedRed: 0.05, green: 0.10, blue: 0.18, alpha: 1.0).setFill()
background.fill()

let inset = full.insetBy(dx: 120, dy: 120)
let card = NSBezierPath(roundedRect: inset, xRadius: 120, yRadius: 120)
NSColor(calibratedRed: 0.16, green: 0.56, blue: 0.97, alpha: 1.0).setFill()
card.fill()

let title = "MD"
let style = NSMutableParagraphStyle()
style.alignment = .center

let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 370, weight: .black),
    .foregroundColor: NSColor.white,
    .paragraphStyle: style
]

let textRect = NSRect(x: 0, y: 290, width: side, height: 420)
title.draw(in: textRect, withAttributes: attrs)

let dot = NSBezierPath(ovalIn: NSRect(x: 760, y: 220, width: 84, height: 84))
NSColor.white.withAlphaComponent(0.92).setFill()
dot.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to generate icon PNG\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
EOF

swift "${SWIFT_FILE}" "${BASE_PNG}"
rm -f "${SWIFT_FILE}"

sips -z 16 16     "${BASE_PNG}" --out "${APPICONSET_DIR}/icon_16x16.png" >/dev/null
sips -z 32 32     "${BASE_PNG}" --out "${APPICONSET_DIR}/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "${BASE_PNG}" --out "${APPICONSET_DIR}/icon_32x32.png" >/dev/null
sips -z 64 64     "${BASE_PNG}" --out "${APPICONSET_DIR}/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "${BASE_PNG}" --out "${APPICONSET_DIR}/icon_128x128.png" >/dev/null
sips -z 256 256   "${BASE_PNG}" --out "${APPICONSET_DIR}/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "${BASE_PNG}" --out "${APPICONSET_DIR}/icon_256x256.png" >/dev/null
sips -z 512 512   "${BASE_PNG}" --out "${APPICONSET_DIR}/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "${BASE_PNG}" --out "${APPICONSET_DIR}/icon_512x512.png" >/dev/null

cat > "${ASSETCATALOG_DIR}/Contents.json" <<'EOF'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

cat > "${APPICONSET_DIR}/Contents.json" <<'EOF'
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo "Generated ${APPICONSET_DIR}"
