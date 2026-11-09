#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="build/Input Pilot.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
for arch in arm64 x86_64; do
  swiftc -swift-version 5 -Osize -target "$arch-apple-macos13.0" -framework AppKit -framework Carbon -framework UniformTypeIdentifiers Sources/main.swift -o "build/PinyinPilot-$arch"
done
lipo -create build/PinyinPilot-arm64 build/PinyinPilot-x86_64 -output "$app/Contents/MacOS/InputPilot"
strip -x "$app/Contents/MacOS/InputPilot"
swift scripts/create-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign - --entitlements PinyinPilot.entitlements "$app"
echo "Built: $PWD/$app"
