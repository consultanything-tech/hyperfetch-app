#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "======================================================="
echo "HyperFetch Native Messaging Host Registration (Unix)"
echo "======================================================="

# Determine binary path
HOST_BIN="${1:-}"
if [[ -z "$HOST_BIN" ]]; then
    CANDIDATES=(
        "$PROJECT_ROOT/desktop/src-tauri/target/release/hyperfetch-native-host"
        "$PROJECT_ROOT/desktop/src-tauri/target/debug/hyperfetch-native-host"
        "/Applications/HyperFetch.app/Contents/MacOS/hyperfetch-native-host"
        "/Applications/HyperFetch.app/Contents/MacOS/hyperfetch-host"
        "/usr/local/bin/hyperfetch-native-host"
    )
    for c in "${CANDIDATES[@]}"; do
        if [[ -x "$c" ]]; then
            HOST_BIN="$c"
            break
        fi
    done
fi

if [[ -z "$HOST_BIN" || ! -x "$HOST_BIN" ]]; then
    # Fallback to current build or placeholder path
    HOST_BIN="$PROJECT_ROOT/desktop/src-tauri/target/debug/hyperfetch-native-host"
    echo "[INFO] Using binary path: $HOST_BIN (run cargo build --bin hyperfetch-native-host if not yet built)"
else
    echo "[INFO] Detected binary: $HOST_BIN"
fi

HOST_BIN_ESCAPED="$(echo "$HOST_BIN" | sed 's/\\/\\\\/g')"

generate_manifest() {
    local name="$1"
    cat <<EOF
{
  "name": "$name",
  "description": "HyperFetch Chrome Native Messaging Host",
  "path": "$HOST_BIN_ESCAPED",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://chhljomijnngbgaglihlgjdbebebfijl/",
    "chrome-extension://*/",
    "chrome-extension://*",
    "edge-extension://*"
  ]
}
EOF
}

OS="$(uname -s)"
TARGET_DIRS=()

if [[ "$OS" == "Darwin" ]]; then
    APP_SUPPORT="$HOME/Library/Application Support"
    TARGET_DIRS=(
        "$APP_SUPPORT/Google/Chrome/NativeMessagingHosts"
        "$APP_SUPPORT/Chromium/NativeMessagingHosts"
        "$APP_SUPPORT/Microsoft Edge/NativeMessagingHosts"
        "$APP_SUPPORT/BraveSoftware/Brave-Browser/NativeMessagingHosts"
        "$APP_SUPPORT/Arc/User Data/NativeMessagingHosts"
        "$APP_SUPPORT/Vivaldi/NativeMessagingHosts"
    )
else
    TARGET_DIRS=(
        "$HOME/.config/google-chrome/NativeMessagingHosts"
        "$HOME/.config/chromium/NativeMessagingHosts"
        "$HOME/.config/microsoft-edge/NativeMessagingHosts"
        "$HOME/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts"
        "$HOME/.mozilla/native-messaging-hosts"
    )
fi

COUNT=0
for dir in "${TARGET_DIRS[@]}"; do
    # Create directory if parent browser directory exists or create anyway
    parent_browser_dir="$(dirname "$dir")"
    if [[ -d "$parent_browser_dir" || "$dir" == *"Google/Chrome"* || "$dir" == *"google-chrome"* ]]; then
        mkdir -p "$dir"
        generate_manifest "com.hyperfetch.native_host" > "$dir/com.hyperfetch.native_host.json"
        generate_manifest "com.hyperfetch.native" > "$dir/com.hyperfetch.native.json"
        echo "  [OK] Installed manifests to: $dir"
        COUNT=$((COUNT + 1))
    fi
done

echo ""
echo "Installed HyperFetch Native Messaging Host manifests in $COUNT browser locations."
exit 0
