#!/bin/bash
# Regenerates Resources/AppIcon.icns from the SwiftUI drawing in Sources/TidyUp/IconRenderer.swift.
# Run this after changing the icon, then run scripts/build_app.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/TidyUp"

OUT=build/icon
rm -rf "$OUT"
mkdir -p "$OUT/AppIcon.iconset" Resources
"$BIN" --render-icon "$OUT"

for s in 16 32 128 256 512; do
  sips -z "$s" "$s" "$OUT/icon-1024.png" --out "$OUT/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z "$d" "$d" "$OUT/icon-1024.png" --out "$OUT/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$OUT/AppIcon.iconset" -o Resources/AppIcon.icns
rm -rf "$OUT"
echo "Wrote Resources/AppIcon.icns"
