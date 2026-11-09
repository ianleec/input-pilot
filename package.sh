#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ "${1:-}" != "--no-build" ]]; then bash build.sh; fi
app="build/Input Pilot.app"
codesign --verify --strict "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
mkdir -p "build/releases/$version"
stage=$(mktemp -d "$PWD/build/dmg-stage.XXXXXX")
ditto "$app" "$stage/Input Pilot.app"
cp INSTALL.txt "$stage/安装说明.txt"
ln -s /Applications "$stage/Applications"
dmg="$PWD/build/releases/$version/Input-Pilot-$version-universal.dmg"
zip="$PWD/build/releases/$version/Input-Pilot-$version-universal.zip"
hdiutil create -ov -volname "Input Pilot $version" -srcfolder "$stage" -format UDZO "$dmg"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
hdiutil verify "$dmg"
codesign --verify --strict "$app"
echo "Application files (bytes):"
find "$app" -type f -exec stat -f '%z' {} \; | awk '{total += $1} END {print total}'
echo "Application disk allocation:"
du -sh "$app"
stat -f '%N: %z bytes' "$dmg" "$zip"
shasum -a 256 "$dmg" "$zip"
