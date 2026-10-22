#!/bin/sh
# Builds dist/Barrel.app: the SwiftUI app, the barrel CLI, the relocatable runtime, recipes, game profiles and the
# license material the GPL/LGPL require (LICENSE, THIRD_PARTY_NOTICES.md, patches/).
# Signing: ad-hoc by default; set SIGN_IDENTITY="Developer ID Application: …" to sign for
# distribution (then run scripts/notarize.sh).
# Usage: scripts/package-app.sh [--skip-runtime]   (reuses dist/runtime when given)
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIST=$ROOT/dist
APP=$DIST/Barrel.app
VERSION=${VERSION:-0.1.0}
SIGN_IDENTITY=${SIGN_IDENTITY:--}

[ "${1:-}" = "--skip-runtime" ] && [ -d "$DIST/runtime" ] || sh "$ROOT/scripts/package-runtime.sh" "$DIST/runtime"

swift build -c release --package-path "$ROOT/barrel" --product barrel
swift build -c release --package-path "$ROOT/app" --product BarrelApp

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/licenses"
cp "$ROOT/app/.build/release/BarrelApp" "$APP/Contents/MacOS/BarrelApp"
cp "$ROOT/barrel/.build/release/barrel" "$APP/Contents/MacOS/barrel"
rsync -a "$DIST/runtime/" "$APP/Contents/Resources/runtime/"
rsync -a "$ROOT/recipes/" "$APP/Contents/Resources/recipes/"
rsync -a "$ROOT/profiles/" "$APP/Contents/Resources/profiles/"
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/licenses/"
rsync -a "$ROOT/patches/" "$APP/Contents/Resources/licenses/patches/"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Barrel</string>
    <key>CFBundleDisplayName</key><string>Barrel</string>
    <key>CFBundleIdentifier</key><string>org.barrel.app</string>
    <key>CFBundleExecutable</key><string>BarrelApp</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>GPL-3.0-or-later. Bundled components: see Resources/licenses.</string>
</dict>
</plist>
EOF

# Sign inside-out: nested Mach-O files first, then the bundle (hardened runtime for Developer ID).
options="--force --timestamp=none --sign"
[ "$SIGN_IDENTITY" = "-" ] || options="--force --timestamp --options runtime --entitlements $ROOT/scripts/barrel.entitlements --sign"
find "$APP/Contents/Resources/runtime" "$APP/Contents/MacOS" -type f | while IFS= read -r f; do
    if file -b "$f" | grep -q '^Mach-O'; then
        # shellcheck disable=SC2086
        codesign $options "$SIGN_IDENTITY" "$f"
    fi
done
# shellcheck disable=SC2086
codesign $options "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
du -sh "$APP"
