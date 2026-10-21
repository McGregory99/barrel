#!/bin/sh
# Notarizes and staples dist/Barrel.app. Needs a Developer ID-signed bundle
# (SIGN_IDENTITY=… scripts/package-app.sh) and a notarytool keychain profile created once with:
#   xcrun notarytool store-credentials barrel --apple-id <id> --team-id <team>
# Usage: scripts/notarize.sh [keychain-profile]   (default: barrel)
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP=$ROOT/dist/Barrel.app
ZIP=$ROOT/dist/Barrel.zip
codesign --verify --strict --deep "$APP"
codesign -dv "$APP" 2>&1 | grep -q 'Authority=Developer ID Application' ||
    { echo "Barrel.app is not signed with a Developer ID; see scripts/package-app.sh" >&2; exit 1; }
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "${1:-barrel}" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose "$APP"
