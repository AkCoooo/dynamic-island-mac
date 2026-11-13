#!/bin/bash
# Compile Dynamic Island Mac en release et l'emballe avec son icône dans « build/Dynamic Island Mac.app ».
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/Dynamic Island Mac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DynamicIslandMac "$APP/Contents/MacOS/DynamicIslandMac"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Icône : un PNG dessiné par script, décliné dans toutes les tailles que macOS attend.
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
swift scripts/make-icon.swift build/icon.png
for s in 16 32 128 256 512; do
    sips -z $s $s build/icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) build/icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"

echo "OK: $APP"
