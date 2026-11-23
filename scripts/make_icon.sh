#!/bin/bash
# Regenerates Resources/AppIcon.icns from Resources/IconSource.png.
# To change the icon: replace Resources/IconSource.png (a rounded tile on a light
# backdrop), run this, then run scripts/build_app.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/icon
rm -rf "$OUT"
mkdir -p "$OUT/AppIcon.iconset" Resources
swift scripts/icon_from_image.swift Resources/IconSource.png "$OUT/icon-1024.png"

for s in 16 32 128 256 512; do
  sips -z "$s" "$s" "$OUT/icon-1024.png" --out "$OUT/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z "$d" "$d" "$OUT/icon-1024.png" --out "$OUT/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$OUT/AppIcon.iconset" -o Resources/AppIcon.icns
rm -rf "$OUT"
echo "Wrote Resources/AppIcon.icns"
