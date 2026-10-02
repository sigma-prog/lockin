#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="Lockin.app"

# Find the icon
ICON=""
for p in ../assets/AppIcon.icns assets/AppIcon.icns; do
    if [ -f "$p" ]; then ICON="$p"; break; fi
done
if [ -z "$ICON" ]; then
    echo "Can't find AppIcon.icns (looked in ../assets and ./assets)"
    exit 1
fi

launchctl bootout "gui/$(id -u)/com.lockin.app" 2>/dev/null || true
pkill -x Lockin 2>/dev/null || true

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Lockin</string>
    <key>CFBundleIdentifier</key><string>com.lockin.app</string>
    <key>CFBundleName</key><string>Lockin</string>
    <key>CFBundleDisplayName</key><string>Lockin</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Lockin closes browser tabs that match your website list during a session.</string>
</dict>
</plist>
PLIST

swiftc -parse-as-library -O -o "$APP/Contents/MacOS/Lockin" ui.swift AppBlocker.swift WebsiteBlocker.swift

# Ad-hoc sign so the bundle is valid, then touch it so Finder refreshes the icon
codesign --force --deep --sign - "$APP"
touch "$APP"

echo "Built $(pwd)/$APP"
echo "Run it with: open $APP"