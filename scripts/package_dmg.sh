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
DMG_OUTPUT="$BUILD_DIR/HyperFetch.dmg"
RW_DMG="$BUILD_DIR/HyperFetch-rw.dmg"
MOUNT_DIR=""

# Ensure clean staging and detached mounts on exit
cleanup() {
    local exit_code=$?
    if [ -n "${MOUNT_DIR:-}" ] && [ -d "${MOUNT_DIR:-}" ]; then
        echo "==> Detaching temporary DMG mount..."
        hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
    fi
    rm -f "$RW_DMG" 2>/dev/null || true
    exit "$exit_code"
}
trap cleanup EXIT

# 1. Build release binary
echo "==> Building release binary..."
swift build -c release

# 2. Create App Bundle directory structure
echo "==> Creating App Bundle directory structure..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 3. Copy binary
echo "==> Copying binary..."
cp "$PROJECT_ROOT/.build/release/HyperFetch" "$APP_BUNDLE/Contents/MacOS/HyperFetch"
chmod +x "$APP_BUNDLE/Contents/MacOS/HyperFetch"

# 4. Copy Info.plist and Resources
echo "==> Copying Info.plist and Resources..."
cp "$PROJECT_ROOT/Sources/HyperFetchApp/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
if [ -f "$PROJECT_ROOT/Sources/HyperFetchApp/Resources/AppIcon.icns" ]; then
    echo "==> Copying AppIcon.icns..."
    cp "$PROJECT_ROOT/Sources/HyperFetchApp/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi
if [ -d "$PROJECT_ROOT/extensions" ]; then
    echo "==> Copying extension resources..."
    cp -R "$PROJECT_ROOT/extensions" "$APP_BUNDLE/Contents/Resources/"
fi

# 5. Create PkgInfo with APPL????
echo "==> Creating PkgInfo..."
printf "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# 6. Codesign the .app bundle
echo "==> Codesigning App Bundle..."
ENTITLEMENTS="$PROJECT_ROOT/Sources/HyperFetchApp/HyperFetch.entitlements"
if [ "$SIGNING_IDENTITY" = "-" ]; then
    codesign --force --entitlements "$ENTITLEMENTS" --sign - "$APP_BUNDLE"
else
    codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
fi

echo "==> Verifying App Bundle signature..."
codesign --verify --strict "$APP_BUNDLE"

# 7. Generate Retina DMG background image
echo "==> Generating branded DMG background image..."
APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PROJECT_ROOT/Sources/HyperFetchApp/Info.plist" 2>/dev/null || echo "1.0.0")
echo "    App Version:      $APP_VERSION"
swift "$PROJECT_ROOT/scripts/generate_dmg_background.swift" "$BUILD_DIR/dmg_background.png" "$APP_VERSION"

# 8. Create temporary read-write DMG image
echo "==> Creating temporary read-write DMG (450 MB)..."
rm -f "$RW_DMG"
hdiutil create -size 450m -fs HFS+ -volname "HyperFetch" "$RW_DMG"

# 9. Mount read-write DMG
echo "==> Mounting read-write DMG..."
if [ -d "/Volumes/HyperFetch" ]; then
    hdiutil detach "/Volumes/HyperFetch" -force 2>/dev/null || true
fi

ATTACH_OUT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG")
MOUNT_DIR=$(echo "$ATTACH_OUT" | grep -o '/Volumes/.*' | head -n 1)

if [ -z "$MOUNT_DIR" ] || [ ! -d "$MOUNT_DIR" ]; then
    echo "Error: Failed to mount read-write DMG: $ATTACH_OUT" >&2
    exit 1
fi
echo "    Mounted at: $MOUNT_DIR"

# 10. Copy HyperFetch.app and setup Applications link
echo "==> Populating DMG volume..."
cp -R "$APP_BUNDLE" "$MOUNT_DIR/"
ln -s /Applications "$MOUNT_DIR/Applications"

# Create hidden .background folder and copy background images (multi-res TIFF and fallback PNG)
mkdir -p "$MOUNT_DIR/.background"
cp "$BUILD_DIR/dmg_background.tiff" "$MOUNT_DIR/.background/background.tiff"
cp "$BUILD_DIR/dmg_background.png" "$MOUNT_DIR/.background/background.png"
if command -v SetFile &>/dev/null; then
    SetFile -a V "$MOUNT_DIR/.background" || true
fi

# Set DMG volume icon if AppIcon.icns exists
if [ -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns" ]; then
    echo "==> Setting DMG volume icon..."
    cp "$APP_BUNDLE/Contents/Resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
    if command -v SetFile &>/dev/null; then
        SetFile -c icnC "$MOUNT_DIR/.VolumeIcon.icns" || true
        SetFile -a C "$MOUNT_DIR" || true
    fi
fi

# 11. Run AppleScript via osascript telling Finder to configure the window
echo "==> Configuring Finder window view and layout..."
VOL_NAME=$(basename "$MOUNT_DIR")
osascript <<EOF
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 200 + 660, 120 + 420}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set text size of theViewOptions to 13
        set background picture of theViewOptions to file ".background:background.tiff"
        set position of item "HyperFetch.app" of container window to {180, 210}
        set position of item "Applications" of container window to {480, 210}
        try
            update without registering applications
        end try
        delay 2
        close
    end tell
end tell
EOF

# Ensure .VolumeIcon.icns and volume icon attributes are preserved on disk
if [ -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns" ]; then
    cp "$APP_BUNDLE/Contents/Resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
    if command -v SetFile &>/dev/null; then
        SetFile -c icnC "$MOUNT_DIR/.VolumeIcon.icns" || true
        SetFile -a C "$MOUNT_DIR" || true
    fi
fi

# 12. Sync and unmount
echo "==> Syncing and detaching DMG..."
sleep 2
sync
hdiutil detach "$MOUNT_DIR" || (sleep 2 && hdiutil detach "$MOUNT_DIR" -force)
MOUNT_DIR=""

# 13. Convert to final compressed read-only DMG (UDZO with max compression)
echo "==> Converting to final compressed read-only DMG (UDZO zlib-9)..."
rm -f "$DMG_OUTPUT"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_OUTPUT"
rm -f "$RW_DMG"

# 14. Sign the DMG itself
echo "==> Codesigning DMG..."
if [ "$SIGNING_IDENTITY" = "-" ]; then
    codesign --force --sign - "$DMG_OUTPUT"
else
    codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_OUTPUT"
fi

# 15. If NOTARY_PROFILE is provided, notarize and staple
if [ -n "$NOTARY_PROFILE" ]; then
    echo "==> Submitting DMG for notarization..."
    xcrun notarytool submit "$DMG_OUTPUT" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "==> Stapling notarization ticket..."
    xcrun stapler staple "$DMG_OUTPUT"
fi

# 16. Output success message with the path to the generated DMG
echo ""
echo "============================================================"
echo "Successfully packaged HyperFetch DMG:"
echo "$DMG_OUTPUT"
echo "============================================================"
