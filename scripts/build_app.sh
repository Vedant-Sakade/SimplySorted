#!/bin/bash
# Builds "build/Simply Sorted.app": a universal app (Apple Silicon + Intel), ad-hoc signed.
# Usage: scripts/build_app.sh [--open]
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHS="--arch arm64 --arch x86_64"
swift build -c release $ARCHS
BIN="$(swift build -c release $ARCHS --show-bin-path)/TidyUp"

# The bundle id stays local.tidyup.app on purpose so settings saved by earlier versions carry over.
APP="build/Simply Sorted.app"
rm -rf "$APP"                       # the old build is removed before every new one
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SimplySorted"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Geist Mono (SIL Open Font License) travels inside the app.
mkdir -p "$APP/Contents/Resources/Fonts"
cp Resources/Fonts/* "$APP/Contents/Resources/Fonts/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>SimplySorted</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>local.tidyup.app</string>
    <key>CFBundleName</key><string>Simply Sorted</string>
    <key>CFBundleDisplayName</key><string>Simply Sorted</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.3.2</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSDownloadsFolderUsageDescription</key><string>Simply Sorted sorts the files in your Downloads folder.</string>
    <key>NSDesktopFolderUsageDescription</key><string>Simply Sorted sorts the files on your Desktop.</string>
    <key>NSDocumentsFolderUsageDescription</key><string>Simply Sorted sorts the files in the folders you choose.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warning: ad-hoc signing failed"
touch "$APP"
echo "Built $APP"
[ "${1:-}" = "--open" ] && open "$APP"
exit 0
