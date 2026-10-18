#!/bin/bash
# Build, sign (Developer ID), notarize and staple build/HyprMux.dmg.
# Needs: zig 0.16, a "Developer ID Application" identity, and a notarytool
# keychain profile named "hyprmux" (xcrun notarytool store-credentials hyprmux).
# Signs with hyprmux.entitlements (no provisioning profile, so none of the
# restricted entitlements), then launches the app once before packaging.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/opt/zig@0.16/bin:$PATH"
TEAM="${TEAM:-RL4G6WZ65Q}"
ID="${ID:-Developer ID Application: Ravikant Cherukuri ($TEAM)}"
rm -rf build/HyprMux.xcarchive build/dist build/dmg build/HyprMux.dmg
mkdir -p build/dist
xcodebuild archive -project cmux.xcodeproj -scheme cmux -configuration Release \
  -archivePath build/HyprMux.xcarchive -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic > build/archive.log 2>&1
ditto build/HyprMux.xcarchive/Products/Applications/HyprMux.app build/dist/HyprMux.app
xattr -cr build/dist/HyprMux.app
find build/dist/HyprMux.app -name embedded.provisionprofile -delete
./scripts/sign-cmux-bundle.sh build/dist/HyprMux.app hyprmux.entitlements "$ID"
codesign --verify --deep --strict build/dist/HyprMux.app
# Smoke test: the signed app must start (restricted entitlements make launchd refuse it).
# Done on a copy: a launched bundle becomes write-protected.
cp -R build/dist/HyprMux.app /tmp/HyprMux-smoke.app
open -n /tmp/HyprMux-smoke.app; sleep 10
pgrep -f "/tmp/HyprMux-smoke.app/Contents/MacOS" >/dev/null || { echo "signed app did not launch" >&2; exit 1; }
pkill -f "/tmp/HyprMux-smoke.app/Contents/MacOS"; rm -rf /tmp/HyprMux-smoke.app
mkdir build/dmg
ditto build/dist/HyprMux.app build/dmg/HyprMux.app
ln -s /Applications build/dmg/Applications
hdiutil create -volname HyprMux -srcfolder build/dmg -ov -format UDZO build/HyprMux.dmg
codesign --sign "$ID" --timestamp build/HyprMux.dmg
xcrun notarytool submit build/HyprMux.dmg --keychain-profile hyprmux --wait
xcrun stapler staple build/HyprMux.dmg
xcrun stapler validate build/HyprMux.dmg
echo "build/HyprMux.dmg ready"
