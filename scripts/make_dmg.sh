#!/bin/bash
# Builds the app, then packs it into build/SimplySorted.dmg (drag Simply Sorted onto Applications).
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build_app.sh
STAGE=build/dmg
rm -rf "$STAGE" build/SimplySorted.dmg
mkdir -p "$STAGE"
cp -R "build/Simply Sorted.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/How to open.txt" <<'TXT'
1. Drag Simply Sorted onto the Applications folder.
2. Open Applications, RIGHT-CLICK Simply Sorted and choose Open, then click Open again.
   (Only needed the first time. macOS asks because the app is not from the App Store.)
TXT
hdiutil create -quiet -volname "Simply Sorted" -srcfolder "$STAGE" -ov -format UDZO build/SimplySorted.dmg
rm -rf "$STAGE"
echo "Built build/SimplySorted.dmg"
