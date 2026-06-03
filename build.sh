#!/bin/bash
#
# Builds "Metadata Cleaner.app" from the Swift sources — no Xcode required.
# Run on macOS 15.7+ with the Xcode command line tools installed
# (xcode-select --install).
#
set -euo pipefail

APP_NAME="Metadata Cleaner"
BINARY="MetadataCleaner"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
ARCH="$(uname -m)"

echo "Cleaning previous build…"
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"

echo "Compiling Swift sources ($ARCH, macOS 15.7)…"
SOURCES=$(find . -name '*.swift')
swiftc -O -parse-as-library \
    -target "${ARCH}-apple-macos15.7" \
    $SOURCES \
    -o "$MACOS_DIR/$BINARY"

echo "Assembling app bundle…"
cp Info.plist "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

echo "Code signing (ad-hoc)…"
mkdir -p "$APP_DIR/Contents/Resources" AppIcon.iconset
for s in 16 32 64 128 256 512 1024; do
  sips -z $s $s icon.png --out "AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
done
iconutil -c icns AppIcon.iconset -o "$APP_DIR/Contents/Resources/AppIcon.icns"
rm -rf AppIcon.iconset
codesign --force --deep --sign - "$APP_DIR"

echo ""
echo "Done → $APP_DIR"
echo "Move it to /Applications, then right-click → Open on first launch."
