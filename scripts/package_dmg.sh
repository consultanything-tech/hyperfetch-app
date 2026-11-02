#!/usr/bin/env bash
set -euo pipefail

# Project root directory (absolute path)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Accepts optional environment variables or arguments:
# Argument 1 can override SIGNING_IDENTITY if provided
# Argument 2 can override NOTARY_PROFILE if provided
SIGNING_IDENTITY="${1:-${SIGNING_IDENTITY:--}}"
NOTARY_PROFILE="${2:-${NOTARY_PROFILE:-}}"

echo "==> Packaging HyperFetch DMG"
echo "    Signing Identity: $SIGNING_IDENTITY"
if [ -n "$NOTARY_PROFILE" ]; then
    echo "    Notary Profile:   $NOTARY_PROFILE"
fi

BUILD_DIR="$PROJECT_ROOT/build"
APP_BUNDLE="$BUILD_DIR/HyperFetch.app"
DMG_STAGING="$BUILD_DIR/dmg_staging"
DMG_OUTPUT="$BUILD_DIR/HyperFetch.dmg"

# Ensure clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# 1. Build release binary
echo "==> Building release binary..."
swift build -c release

# 2. Create App Bundle staging directory
echo "==> Creating App Bundle directory structure..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 3. Copy binary
echo "==> Copying binary..."
cp "$PROJECT_ROOT/.build/release/HyperFetch" "$APP_BUNDLE/Contents/MacOS/HyperFetch"
chmod +x "$APP_BUNDLE/Contents/MacOS/HyperFetch"

# 4. Copy Info.plist and AppIcon
echo "==> Copying Info.plist and Resources..."
cp "$PROJECT_ROOT/Sources/HyperFetchApp/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
if [ -f "$PROJECT_ROOT/Sources/HyperFetchApp/Resources/AppIcon.icns" ]; then
    echo "==> Copying AppIcon.icns..."
    cp "$PROJECT_ROOT/Sources/HyperFetchApp/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# 5. Create PkgInfo with APPL????
echo "==> Creating PkgInfo..."
printf "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# 6. Codesign the .app bundle
echo "==> Codesigning App Bundle..."
if [ "$SIGNING_IDENTITY" = "-" ]; then
    codesign --force --deep --sign - "$APP_BUNDLE"
else
    codesign --force --options runtime --deep --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
fi

# 7. Create DMG staging folder
echo "==> Preparing DMG staging folder..."
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

# Set DMG volume icon if AppIcon.icns exists
if [ -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns" ]; then
    echo "==> Setting DMG volume icon..."
    cp "$APP_BUNDLE/Contents/Resources/AppIcon.icns" "$DMG_STAGING/.VolumeIcon.icns"
    if command -v SetFile &>/dev/null; then
        SetFile -c icnC "$DMG_STAGING/.VolumeIcon.icns" || true
        SetFile -a C "$DMG_STAGING" || true
    fi
fi

# 8. Generate DMG using hdiutil create
echo "==> Creating DMG..."
rm -f "$DMG_OUTPUT"
hdiutil create -volname "HyperFetch" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_OUTPUT"

# Clean up staging folder
rm -rf "$DMG_STAGING"

# 9. Sign the DMG itself
echo "==> Codesigning DMG..."
codesign --force --sign "$SIGNING_IDENTITY" "$DMG_OUTPUT"

# 10. If NOTARY_PROFILE is provided:
if [ -n "$NOTARY_PROFILE" ]; then
    echo "==> Submitting DMG for notarization..."
    xcrun notarytool submit "$DMG_OUTPUT" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "==> Stapling notarization ticket..."
    xcrun stapler staple "$DMG_OUTPUT"
fi

# 11. Output success message with the path to the generated DMG
echo ""
echo "============================================================"
echo "Successfully packaged HyperFetch DMG:"
echo "$DMG_OUTPUT"
echo "============================================================"
