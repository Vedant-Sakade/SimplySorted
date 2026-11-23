#!/bin/bash
# Builds build/TidyUp.app (ad-hoc signed, runs only on this Mac).
# Usage: scripts/build_app.sh [--open]
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/TidyUp"

APP="build/TidyUp.app"
rm -rf "$APP"                       # the old build is removed before every new one
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TidyUp"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Geist Mono (SIL Open Font License) travels inside the app.
mkdir -p "$APP/Contents/Resources/Fonts"
cp Resources/Fonts/* "$APP/Contents/Resources/Fonts/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>TidyUp</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>local.tidyup.app</string>
    <key>CFBundleName</key><string>TidyUp</string>
    <key>CFBundleDisplayName</key><string>TidyUp</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSDownloadsFolderUsageDescription</key><string>TidyUp sorts the files in your Downloads folder.</string>
    <key>NSDesktopFolderUsageDescription</key><string>TidyUp sorts the files on your Desktop.</string>
    <key>NSDocumentsFolderUsageDescription</key><string>TidyUp sorts the files in the folders you choose.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warning: ad-hoc signing failed"
touch "$APP"
echo "Built $APP"
[ "${1:-}" = "--open" ] && open "$APP"
exit 0
