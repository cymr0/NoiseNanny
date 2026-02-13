#!/bin/bash
set -euo pipefail

APP_NAME="NoiseNanny"
BUILD_DIR=".build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
INSTALL_DIR="/Applications"

echo "Building $APP_NAME..."
swift build -c release 2>&1

BINARY="$BUILD_DIR/release/$APP_NAME"
if [ ! -f "$BINARY" ]; then
    echo "Error: Binary not found at $BINARY"
    exit 1
fi

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

cp "$BINARY" "$CONTENTS/MacOS/$APP_NAME"
cp "Sources/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

# Info.plist — LSUIElement hides from dock
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>NoiseNanny</string>
    <key>CFBundleIdentifier</key>
    <string>com.noisenanny.app</string>
    <key>CFBundleName</key>
    <string>NoiseNanny</string>
    <key>CFBundleDisplayName</key>
    <string>NoiseNanny</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS doesn't immediately quarantine
codesign --force --sign - "$APP_DIR"

echo "App bundle created at $APP_DIR"

# Create release zip
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
(cd "$BUILD_DIR" && zip -qr "$APP_NAME.zip" "$APP_NAME.app")
echo "Release zip created at $ZIP_PATH"

# Optionally install to /Applications
if [ "${1:-}" = "--install" ]; then
    echo "Installing to $INSTALL_DIR..."
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
    cp -R "$APP_DIR" "$INSTALL_DIR/"
    echo "Installed to $INSTALL_DIR/$APP_NAME.app"
fi

echo ""
echo "Done."
echo "  Run locally:    open $APP_DIR"
echo "  Release zip:    $ZIP_PATH"
echo "  Create release: gh release create v1.0 $ZIP_PATH --title 'v1.0'"
