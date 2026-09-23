#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Library/Developer/CommandLineTools ]]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
swift build -c release
app="dist/Tabitat.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Tabitat "$app/Contents/MacOS/Tabitat"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift tools/GenerateIcon.swift Resources/AppIcon.png "$app/Contents/Resources/AppIcon.iconset"
iconutil -c icns "$app/Contents/Resources/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier com.furkansahin.ChromeProfileRouter "$app"
codesign --verify --strict "$app"
echo "Built: $PWD/$app"
