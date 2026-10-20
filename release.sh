#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
DMG="dist/Pulse-${VERSION}.dmg"
[[ ! -e "$DMG" ]] || { echo "Refusing to overwrite $DMG"; exit 1; }
bash build.sh
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/pulse-release.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
cp -R dist/Pulse.app "$STAGE/Pulse.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname Pulse -srcfolder "$STAGE" -format UDZO -quiet "$DMG"
if [[ -n "${PULSE_NOTARY_PROFILE:-}" ]]; then
  [[ -n "${PULSE_SIGN_IDENTITY:-}" && "$PULSE_SIGN_IDENTITY" != '-' ]] || { echo 'Notarization requires Developer ID'; exit 1; }
  xcrun notarytool submit "$DMG" --keychain-profile "$PULSE_NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
else
  echo 'Not notarized. See docs/instalar.md before distribution.'
fi
(cd dist && shasum -a 256 "Pulse-${VERSION}.dmg" > SHA256SUMS)
hdiutil verify "$DMG"
echo "Release ready: $DMG"
