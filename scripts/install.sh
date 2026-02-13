#!/bin/bash
set -euo pipefail

# NoiseNanny installer — downloads pre-built .app from GitHub Releases
# Usage: curl -fsSL https://raw.githubusercontent.com/OWNER/NoiseNanny/main/scripts/install.sh | bash

REPO="CYMR0/NoiseNanny"
APP_NAME="NoiseNanny"
INSTALL_DIR="/Applications"
ASSET_NAME="NoiseNanny.zip"
TMP_DIR="$(mktemp -d)"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

echo "Fetching latest release..."
RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest")

if command -v jq >/dev/null 2>&1; then
    TAG=$(echo "$RELEASE_JSON" | jq -r '.tag_name')
    DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jq -r ".assets[] | select(.name == \"$ASSET_NAME\") | .browser_download_url")
else
    # Fallback for systems without jq
    TAG=$(echo "$RELEASE_JSON" | grep '"tag_name"' | head -1 | sed 's/.*: *"//;s/".*//')
    DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep '"browser_download_url"' | grep "$ASSET_NAME" | head -1 | sed 's/.*: *"//;s/".*//')
fi

if [ -z "$DOWNLOAD_URL" ]; then
    echo "Error: Could not find $ASSET_NAME in release $TAG"
    echo "Available assets:"
    echo "$RELEASE_JSON" | grep '"browser_download_url"' | sed 's/.*: *"//;s/".*//'
    exit 1
fi

echo "Downloading $APP_NAME $TAG..."
curl -fsSL -o "$TMP_DIR/$ASSET_NAME" "$DOWNLOAD_URL"

echo "Extracting..."
unzip -q "$TMP_DIR/$ASSET_NAME" -d "$TMP_DIR"

if [ ! -d "$TMP_DIR/$APP_NAME.app" ]; then
    echo "Error: $APP_NAME.app not found in archive"
    exit 1
fi

echo "Installing to $INSTALL_DIR (may require password)..."
if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    # Kill running instance first
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 1
    sudo rm -rf "$INSTALL_DIR/$APP_NAME.app"
fi
sudo cp -R "$TMP_DIR/$APP_NAME.app" "$INSTALL_DIR/"

echo ""
echo "Installed $APP_NAME $TAG to $INSTALL_DIR/$APP_NAME.app"
echo ""
echo "NOTE: On first launch, macOS may block the app because it is not code-signed."
echo "If that happens: right-click the app → Open → click Open in the dialog."
echo ""

# Offer to launch
read -r -p "Launch now? [Y/n] " response < /dev/tty || response="y"
case "$response" in
    [nN]*) echo "Done." ;;
    *)     open "$INSTALL_DIR/$APP_NAME.app"; echo "Launched." ;;
esac
