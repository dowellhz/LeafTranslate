#!/bin/zsh
set -euo pipefail

APP_NAME="LeafTranslate"
BUNDLE_ID="com.linlu.leaftranslate"
VERSION="0.1.0"
MACOS_TARGET="arm64-apple-macos12.0"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$ROOT_DIR/$APP_NAME.app"
LEGACY_APP_DIR="$ROOT_DIR/pdftranslate.app"
SWIFT_SOURCES=("$ROOT_DIR"/Sources/*.swift)

rm -rf "$BUILD_DIR" "$APP_DIR" "$LEGACY_APP_DIR"
mkdir -p "$BUILD_DIR" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

if [ ${#SWIFT_SOURCES[@]} -eq 0 ]; then
  echo "No Swift sources found." >&2
  exit 1
fi

swiftc -target "$MACOS_TARGET" \
  "${SWIFT_SOURCES[@]}" \
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
  <string>__BUNDLE_ID__</string>
  <key>CFBundleName</key>
  <string>LeafTranslate</string>
  <key>CFBundleDisplayName</key>
  <string>LeafTranslate</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>__VERSION__</string>
  <key>CFBundleVersion</key>
  <string>__VERSION__</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

/usr/bin/sed -i '' \
  -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" \
  -e "s/__VERSION__/$VERSION/g" \
  "$APP_DIR/Contents/Info.plist"

if [ -d "$ROOT_DIR/Resources" ]; then
  cp -R "$ROOT_DIR/Resources/." "$APP_DIR/Contents/Resources/"
fi

echo "Built $APP_DIR"
