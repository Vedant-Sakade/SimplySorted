#!/bin/bash
# Builds the app, then packs it into build/TidyUp.dmg (drag TidyUp onto Applications).
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build_app.sh
STAGE=build/dmg
rm -rf "$STAGE" build/TidyUp.dmg
mkdir -p "$STAGE"
cp -R build/TidyUp.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/How to open.txt" <<'TXT'
1. Drag TidyUp onto the Applications folder.
2. Open Applications, RIGHT-CLICK TidyUp and choose Open, then click Open again.
   (Only needed the first time. macOS asks because the app is not from the App Store.)
TXT
hdiutil create -quiet -volname "TidyUp" -srcfolder "$STAGE" -ov -format UDZO build/TidyUp.dmg
rm -rf "$STAGE"
echo "Built build/TidyUp.dmg"
