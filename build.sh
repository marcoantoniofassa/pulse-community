#!/bin/bash
# Builds locally. Never installs or touches the user's Pulse data.
set -euo pipefail
cd "$(dirname "$0")"
[[ "$(uname -m)" == arm64 ]] || { echo 'Apple Silicon required'; exit 1; }
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build -c release --disable-sandbox -Xswiftc -debug-prefix-map -Xswiftc "$PWD=/Pulse" -Xswiftc -file-prefix-map -Xswiftc "$PWD=/Pulse"
APP=dist/Pulse.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/sounds"
cp .build/release/Pulse "$APP/Contents/MacOS/Pulse"
strip -S -x "$APP/Contents/MacOS/Pulse"
cp Resources/Info.plist "$APP/Contents/Info.plist"
for icon in AppIcon.icns StatusBarIcon.png StatusBarIcon@2x.png StatusIcon.png; do
  cp "Resources/$icon" "$APP/Contents/Resources/$icon"
done
for sound in Start1 Stop1 noResult1; do
  cp "Resources/sounds/$sound.wav" "$APP/Contents/Resources/sounds/$sound.wav"
done
IDENTITY="${PULSE_SIGN_IDENTITY:--}"
if [[ "$IDENTITY" == '-' ]]; then
  codesign --force --sign - --entitlements Entitlements.plist "$APP"
else
  codesign --force --options runtime --timestamp --sign "$IDENTITY" --entitlements Entitlements.plist "$APP"
fi
codesign --verify --strict "$APP"
python3 tests/check_distribution.py "$APP"
echo "Build ready: $APP (not installed)"
