#!/bin/bash
# Compile Dynamic Island Mac en release et l'emballe dans « build/Dynamic Island Mac.app » (signature ad hoc).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/Dynamic Island Mac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DynamicIslandMac "$APP/Contents/MacOS/DynamicIslandMac"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "OK: $APP"
