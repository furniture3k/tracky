#!/bin/bash
# Builds a stripped, ad-hoc signed Tracky.app in ./build.
#   --install   copy it to /Applications and launch it
#   --release   universal (Apple Silicon + Intel) build, zipped to build/Tracky.zip for distribution
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHS=()
[[ "${1:-}" == "--release" ]] && ARCHS=(--arch arm64 --arch x86_64)
swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/Tracky"
APP="build/Tracky.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ ! -f Resources/AppIcon.icns ]]; then
  TMP="$(mktemp -d)"
  swiftc -O scripts/make-icon.swift -o "$TMP/make-icon"
  "$TMP/make-icon" "$TMP/AppIcon.iconset"
  iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
  rm -rf "$TMP"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN" "$APP/Contents/MacOS/Tracky"
strip -S -x "$APP/Contents/MacOS/Tracky"
# SwiftPM stamps the deployment target as the SDK version, which makes macOS 26+ run the app in
# compatibility mode with the old pre-Liquid Glass look. Stamp the real SDK version instead.
vtool -set-build-version macos 14.0 "$(xcrun --show-sdk-version)" -replace \
  -output "$APP/Contents/MacOS/Tracky" "$APP/Contents/MacOS/Tracky" 2>/dev/null
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP ($(du -sh "$APP" | cut -f1), binary $(du -h "$APP/Contents/MacOS/Tracky" | cut -f1))"

if [[ "${1:-}" == "--release" ]]; then
  rm -f build/Tracky.zip
  ditto -c -k --keepParent "$APP" build/Tracky.zip
  echo "Packaged build/Tracky.zip ($(du -h build/Tracky.zip | cut -f1), $(lipo -archs "$APP/Contents/MacOS/Tracky"))"
fi

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Tracky 2>/dev/null || true
  rm -rf /Applications/Tracky.app
  cp -R "$APP" /Applications/
  rm -rf "$APP" # keep a single copy so Spotlight/Launchpad always open the installed one
  echo "Installed to /Applications/Tracky.app"
  open /Applications/Tracky.app
fi
