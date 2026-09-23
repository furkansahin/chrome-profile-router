#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source_app="$PWD/dist/Tabitat.app"
destination="/Applications/Tabitat.app"
legacy_destination="/Applications/Chrome Profile Router.app"
bundle_id="com.furkansahin.ChromeProfileRouter"
lsregister='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
if [[ ! -x "$source_app/Contents/MacOS/Tabitat" ]]; then
    echo "Build the app first with bash scripts/build.sh" >&2
    exit 1
fi
codesign --verify --strict "$source_app"
# Validate both destinations before moving either one.
for installed_app in "$destination" "$legacy_destination"; do
    [[ -e "$installed_app" ]] || continue
    installed_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$installed_app/Contents/Info.plist")
    if [[ "$installed_id" != "$bundle_id" ]]; then
        echo "A destination belongs to a different app; leaving it untouched: $installed_app" >&2
        exit 1
    fi
done
process_pattern='^/Applications/(Tabitat|Chrome Profile Router)[.]app/Contents/MacOS/(Tabitat|ChromeProfileRouter)( |$)'
if pgrep -f "$process_pattern" >/dev/null; then
    pkill -TERM -f "$process_pattern"
fi
backup_root="$PWD/dist/Previous-$(date +%Y%m%d-%H%M%S)-$$"
for installed_app in "$destination" "$legacy_destination"; do
    [[ -d "$installed_app" ]] || continue
    mkdir -p "$backup_root"
    "$lsregister" -u "$installed_app"
    mv "$installed_app" "$backup_root/$(basename "$installed_app")"
done
ditto "$source_app" "$destination"
codesign --verify --strict "$destination"
"$lsregister" -f "$destination"
open "$destination"
echo "Installed: $destination"
