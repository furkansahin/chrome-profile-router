#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source_app="$PWD/dist/Chrome Profile Router.app"
destination="/Applications/Chrome Profile Router.app"
if [[ ! -x "$source_app/Contents/MacOS/ChromeProfileRouter" ]]; then
    echo "Build the app first with bash scripts/build.sh" >&2
    exit 1
fi
codesign --verify --strict "$source_app"
if [[ -d "$destination" ]]; then
    installed_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")
    if [[ "$installed_id" != "com.furkansahin.ChromeProfileRouter" ]]; then
        echo "The destination belongs to a different app; leaving it untouched." >&2
        exit 1
    fi
    if pgrep -f '^/Applications/Chrome Profile Router.app/Contents/MacOS/ChromeProfileRouter' >/dev/null; then
        pkill -TERM -f '^/Applications/Chrome Profile Router.app/Contents/MacOS/ChromeProfileRouter'
    fi
    backup="$PWD/dist/Previous-$(date +%Y%m%d-%H%M%S).app"
    ditto "$destination" "$backup"
fi
ditto "$source_app" "$destination"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$destination"
open "$destination"
echo "Installed: $destination"
