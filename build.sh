#!/bin/bash
set -e

echo "🎨 Converting icon.svg to 1024x1024 PNG..."
swift -e '
import AppKit
if let img = NSImage(contentsOfFile: "icon.svg") {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "icon.png"))
} else {
    print("❌ Could not load icon.svg")
    exit(1)
}
'

echo "📐 Generating Apple iconset..."
mkdir -p AppIcon.iconset
sips -z 16 16     icon.png --out AppIcon.iconset/icon_16x16.png > /dev/null
sips -z 32 32     icon.png --out AppIcon.iconset/icon_16x16@2x.png > /dev/null
sips -z 32 32     icon.png --out AppIcon.iconset/icon_32x32.png > /dev/null
sips -z 64 64     icon.png --out AppIcon.iconset/icon_32x32@2x.png > /dev/null
sips -z 128 128   icon.png --out AppIcon.iconset/icon_128x128.png > /dev/null
sips -z 256 256   icon.png --out AppIcon.iconset/icon_128x128@2x.png > /dev/null
sips -z 256 256   icon.png --out AppIcon.iconset/icon_256x256.png > /dev/null
sips -z 512 512   icon.png --out AppIcon.iconset/icon_256x256@2x.png > /dev/null
sips -z 512 512   icon.png --out AppIcon.iconset/icon_512x512.png > /dev/null
sips -z 1024 1024 icon.png --out AppIcon.iconset/icon_512x512@2x.png > /dev/null

echo "📦 Creating AppIcon.icns..."
iconutil -c icns AppIcon.iconset -o AppIcon.icns
rm -rf AppIcon.iconset icon.png

echo "🔨 Building Lockin.app..."
mkdir -p Lockin.app/Contents/MacOS
mkdir -p Lockin.app/Contents/Resources
swiftc -O -parse-as-library AppBlocker.swift WebsiteBlocker.swift ui.swift -o Lockin.app/Contents/MacOS/Lockin
cp AppIcon.icns Lockin.app/Contents/Resources/AppIcon.icns

# Creates About Panel text with clickable GitHub link
cat <<'CREDITS' > Lockin.app/Contents/Resources/Credits.rtf
{\rtf1\ansi\ansicpg1252\cocoartf2500
{\fonttbl\f0\fswiss\fcharset0 Helvetica;}
{\colortbl;\red255\green255\blue255;\red0\green0\blue238;}
\pard\qc
\f0\fs22 \cf0 By Lucas H\
\
{\field{\*\fldinst{HYPERLINK "https://github.com/sigma-prog/lockin"}}{\fldrslt{\cf2\ul GitHub Repository}}}
}
CREDITS

cat <<PLIST > Lockin.app/Contents/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Lockin</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.lockin.app</string>
    <key>CFBundleName</key>
    <string>Lockin</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>By Lucas H</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "✨ Done! Lockin.app is ready with your icon and GitHub link in About."
