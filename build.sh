#!/bin/zsh
set -euo pipefail

APP_NAME="LeafTranslate"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$ROOT_DIR/$APP_NAME.app"
LEGACY_APP_DIR="$ROOT_DIR/pdftranslate.app"

rm -rf "$BUILD_DIR" "$APP_DIR" "$LEGACY_APP_DIR"
mkdir -p "$BUILD_DIR" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

swiftc -target arm64-apple-macos12.0 \
  "$ROOT_DIR"/Sources/*.swift \
  -o "$APP_DIR/Contents/MacOS/$APP_NAME" \
  -framework Cocoa \
  -framework PDFKit \
  -framework CoreGraphics

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>LeafTranslate</string>
  <key>CFBundleIdentifier</key>
  <string>com.linlu.leaftranslate</string>
  <key>CFBundleName</key>
  <string>LeafTranslate</string>
  <key>CFBundleDisplayName</key>
  <string>LeafTranslate</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>0.1.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

if [ -d "$ROOT_DIR/Resources" ]; then
  cp -R "$ROOT_DIR/Resources/." "$APP_DIR/Contents/Resources/"
fi

echo "Built $APP_DIR"
