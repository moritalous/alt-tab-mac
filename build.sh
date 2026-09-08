#!/bin/bash
# AltTabMac.app をビルドする。出力: build/AltTabMac.app
set -euo pipefail
cd "$(dirname "$0")"

APP="build/AltTabMac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 \
  -framework Cocoa -framework ApplicationServices -framework ServiceManagement \
  -F /System/Library/PrivateFrameworks -framework SkyLight \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/AltTabMac"

cp Info.plist "$APP/Contents/Info.plist"
cp icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --sign - "$APP" 2>/dev/null

echo "built: $APP"
