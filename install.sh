#!/usr/bin/env bash
# HyperFetch macOS 1-Line Installer
# Usage: curl -sSL https://raw.githubusercontent.com/consultanything-tech/hyperfetch-app/main/install.sh | bash

set -euo pipefail

# Colors & Formatting
BOLD="\033[1m"
GREEN="\033[32m"
CYAN="\033[36m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

echo -e "\n${CYAN}${BOLD}⚡ HyperFetch for macOS — Native High-Speed Download Manager${RESET}"
echo -e "${CYAN}================================================================${RESET}\n"

# Verify macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}✖ Error: HyperFetch is a native macOS application and only runs on macOS Sonoma (14.0) or later.${RESET}"
    exit 1
fi

REPO="consultanything-tech/hyperfetch-app"
FALLBACK_TAG="v1.0.9"

echo -e "${CYAN}→${RESET} Resolving latest release..."

# Attempt to query GitHub API for the latest release tag, fallback to $FALLBACK_TAG
LATEST_TAG=$(curl -sSL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || true)

if [[ -z "${LATEST_TAG}" ]]; then
    LATEST_TAG="${FALLBACK_TAG}"
fi

DMG_URL="https://github.com/${REPO}/releases/download/${LATEST_TAG}/HyperFetch.dmg"
echo -e "  Target release: ${GREEN}${BOLD}${LATEST_TAG}${RESET}"
echo -e "${CYAN}→${RESET} Downloading HyperFetch.dmg..."

TMP_DIR=$(mktemp -d -t hyperfetch-install-XXXXXX)
DMG_PATH="${TMP_DIR}/HyperFetch.dmg"
MOUNT_DIR=""

cleanup() {
    if [[ -n "${MOUNT_DIR}" ]] && [[ -d "${MOUNT_DIR}" ]]; then
        hdiutil detach "${MOUNT_DIR}" -quiet -force 2>/dev/null || true
    fi
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT INT TERM

# Download with progress bar
if command -v curl &>/dev/null; then
    curl -fL --progress-bar "${DMG_URL}" -o "${DMG_PATH}"
else
    echo -e "${RED}✖ Error: curl is required to download HyperFetch.${RESET}"
    exit 1
fi

echo -e "${CYAN}→${RESET} Mounting disk image..."
MOUNT_OUTPUT=$(hdiutil attach "${DMG_PATH}" -nobrowse -readonly)
MOUNT_DIR=$(echo "${MOUNT_OUTPUT}" | grep -E '/Volumes/' | awk -F'\t' '{print $NF}' | head -n 1)

if [[ -z "${MOUNT_DIR}" ]] || [[ ! -d "${MOUNT_DIR}" ]]; then
    MOUNT_DIR="/Volumes/HyperFetch"
fi

if [[ ! -d "${MOUNT_DIR}/HyperFetch.app" ]]; then
    echo -e "${RED}✖ Error: Could not locate HyperFetch.app in mounted disk image.${RESET}"
    exit 1
fi

TARGET_APP="/Applications/HyperFetch.app"

# Check if application already exists
if [[ -d "${TARGET_APP}" ]]; then
    echo -e "${YELLOW}! Updating existing HyperFetch installation in /Applications...${RESET}"
    osascript -e 'quit app "HyperFetch"' 2>/dev/null || true
    sleep 0.5
    rm -rf "${TARGET_APP}"
fi

echo -e "${CYAN}→${RESET} Installing to /Applications/HyperFetch.app..."
cp -R "${MOUNT_DIR}/HyperFetch.app" /Applications/

# Remove quarantine attribute to avoid macOS Gatekeeper warning for direct GitHub downloads
xattr -dr com.apple.quarantine "${TARGET_APP}" 2>/dev/null || true

echo -e "\n${GREEN}${BOLD}✔ HyperFetch ${LATEST_TAG} installed successfully!${RESET}"
echo -e "${CYAN}→${RESET} Launching HyperFetch..."
open -a HyperFetch || open "${TARGET_APP}"

echo -e "\n${BOLD}Thank you for installing HyperFetch!${RESET}"
echo -e "Documentation & Chrome Extension: ${CYAN}https://consultanything-tech.github.io/hyperfetch-app/${RESET}\n"
