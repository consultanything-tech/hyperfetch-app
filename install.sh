#!/usr/bin/env bash
# HyperFetch macOS installer. Run without sudo.
set -euo pipefail

fail() {
    echo "HyperFetch: $*" >&2
    exit 1
}

verify_app() {
    codesign --verify --deep --strict "$1" && codesign --verify --strict "-R=$REQUIREMENT" "$1"
}

[[ "$(uname -s)" == Darwin ]] || fail "This installer requires macOS 14 or newer."
macos_major=$(sw_vers -productVersion | cut -d. -f1)
[[ "$macos_major" =~ ^[0-9]+$ && "$macos_major" -ge 14 ]] || fail "This installer requires macOS 14 or newer."

REPO="consultanything-tech/hyperfetch-app"
TARGET_APP="/Applications/HyperFetch.app"
APP_ID="com.hyperfetch.HyperFetch"
REQUIREMENT='identifier "com.hyperfetch.HyperFetch"'
TMP_DIR=$(mktemp -d -t hyperfetch-install)
MOUNT_DIR="$TMP_DIR/mount"
READINESS_MARKER="$TMP_DIR/hyperfetch_update_ready"
STAGING_DIR=""
mounted=false
installing=false
installed=false
was_running=false

cleanup() {
    local status=$?
    trap - EXIT
    if $installing; then
        if $installed; then
            mv "$TARGET_APP" "$STAGING_DIR/Failed.app" || status=1
        fi
        if [[ -e "$STAGING_DIR/Previous.app" ]]; then
            if [[ ! -e "$TARGET_APP" ]] && mv "$STAGING_DIR/Previous.app" "$TARGET_APP"; then
                echo "Restored the previous HyperFetch installation." >&2
                if $was_running; then
                    open "$TARGET_APP" || true
                fi
            else
                echo "The previous installation was kept at $STAGING_DIR/Previous.app." >&2
                STAGING_DIR=""
                status=1
            fi
        fi
    fi
    if ! $mounted || hdiutil detach "$MOUNT_DIR" -quiet; then
        rm -rf "$TMP_DIR"
    else
        echo "Could not detach the installer image at $MOUNT_DIR." >&2
    fi
    if [[ -n "$STAGING_DIR" ]]; then
        rm -rf "$STAGING_DIR"
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo "Checking the latest HyperFetch release..."
manifest="$TMP_DIR/release.json"
curl --fail --silent --show-error --location --max-time 30 \
    "https://api.github.com/repos/$REPO/releases/latest" -o "$manifest" ||
    fail "Could not check GitHub for the latest release. Visit https://github.com/$REPO/releases."

tag=$(/usr/bin/plutil -extract tag_name raw -o - "$manifest") ||
    fail "GitHub did not return a release version."
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || fail "Unexpected release tag: $tag."

digest=""
index=0
while name=$(/usr/bin/plutil -extract "assets.$index.name" raw -o - "$manifest" 2>/dev/null); do
    if [[ "$name" == HyperFetch.dmg ]]; then
        digest=$(/usr/bin/plutil -extract "assets.$index.digest" raw -o - "$manifest" 2>/dev/null || true)
        break
    fi
    index=$((index + 1))
done
[[ "$digest" =~ ^sha256:[0-9a-fA-F]{64}$ ]] || fail "The latest release does not provide a checksum for HyperFetch.dmg."

echo "Downloading HyperFetch $tag..."
image="$TMP_DIR/HyperFetch.dmg"
curl --fail --location --progress-bar --max-time 300 \
    "https://github.com/$REPO/releases/download/$tag/HyperFetch.dmg" -o "$image"
actual=$(/usr/bin/shasum -a 256 "$image" | awk '{print $1}')
expected=$(printf '%s' "${digest#sha256:}" | tr 'A-F' 'a-f')
[[ "$actual" == "$expected" ]] || fail "The download checksum did not match."

mkdir "$MOUNT_DIR"
hdiutil attach "$image" -nobrowse -readonly -mountpoint "$MOUNT_DIR" -quiet
mounted=true
source_app="$MOUNT_DIR/HyperFetch.app"
[[ -d "$source_app" && ! -L "$source_app" ]] || fail "The disk image does not contain HyperFetch.app."
verify_app "$source_app" ||
    fail "The downloaded app did not pass code integrity and bundle identity checks."
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$source_app/Contents/Info.plist")
[[ "$version" == "${tag#v}" ]] || fail "The app version does not match the release."
processor=$(uname -m)
binary_description=$(/usr/bin/file -b "$source_app/Contents/MacOS/HyperFetch")
printf '%s\n' "$binary_description" | /usr/bin/grep -Eq "Mach-O 64-bit executable $processor([^[:alnum:]_]|$)" ||
    fail "This release does not support this Mac's processor."
[[ ! -L "$TARGET_APP" ]] || fail "The current app path is a symbolic link. Install the DMG manually."
if [[ -e "$TARGET_APP" ]]; then
    existing_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$TARGET_APP/Contents/Info.plist" 2>/dev/null || true)
    [[ "$existing_id" == "$APP_ID" ]] || fail "The existing item is not a HyperFetch app. Choose another install location manually."
fi

STAGING_DIR=$(mktemp -d "/Applications/.hyperfetch-install.XXXXXX") ||
    fail "Applications is not writable. Install the DMG manually."
/usr/bin/ditto "$source_app" "$STAGING_DIR/HyperFetch.app"
verify_app "$STAGING_DIR/HyperFetch.app"

if /usr/bin/pgrep -x HyperFetch >/dev/null; then
    was_running=true
    /usr/bin/osascript -e "tell application id \"$APP_ID\" to quit" >/dev/null ||
        fail "Quit HyperFetch before installing the update."
    for ((attempt = 0; attempt < 50; attempt++)); do
        /usr/bin/pgrep -x HyperFetch >/dev/null || break
        sleep 0.1
    done
    ! /usr/bin/pgrep -x HyperFetch >/dev/null || fail "Quit HyperFetch before installing the update."
fi

installing=true
if [[ -e "$TARGET_APP" ]]; then
    mv "$TARGET_APP" "$STAGING_DIR/Previous.app"
fi
mv "$STAGING_DIR/HyperFetch.app" "$TARGET_APP"
installed=true
verify_app "$TARGET_APP"
open "$TARGET_APP" --args --hyperfetch-update-readiness-file "$READINESS_MARKER" ||
    fail "macOS could not open the new installation."
for ((attempt = 0; attempt < 100; attempt++)); do
    [[ ! -s "$READINESS_MARKER" ]] || break
    sleep 0.1
done
[[ -s "$READINESS_MARKER" ]] || fail "The updated app did not finish starting."
installing=false
echo "Installed HyperFetch $tag in Applications."
