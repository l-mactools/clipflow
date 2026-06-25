#!/bin/zsh
set -euo pipefail
export COPYFILE_DISABLE=1

ROOT="${0:A:h:h}"
VERSION="${1:-0.1.0}"
ARCH="arm64"
APP_NAME="Jian"
APP="$ROOT/dist/$APP_NAME.app"
ZIP="$ROOT/dist/$APP_NAME-$VERSION-macos-$ARCH.zip"
DMG="$ROOT/dist/$APP_NAME-$VERSION-macos-$ARCH.dmg"
ICON_SOURCE="$ROOT/Sources/ClipFlow/Resources/JianAppIcon.png"
ICON_PNG="$ROOT/.build/JianAppIcon-normalized.png"
ICONSET="$ROOT/.build/Jian.iconset"
DMG_STAGE="$ROOT/.build/dmg-stage"

cd "$ROOT"
swift build -c release --arch "$ARCH"
BIN_DIR="$(swift build -c release --arch "$ARCH" --show-bin-path)"

rm -rf "$APP" "$ICONSET" "$ZIP" "$ZIP.sha256" "$DMG" "$DMG.sha256" "$DMG_STAGE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET" "$ROOT/dist"

cp "$BIN_DIR/Jian" "$APP/Contents/MacOS/Jian"
cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"

sips -s format png "$ICON_SOURCE" --out "$ICON_PNG" >/dev/null
cp "$ICON_PNG" "$APP/Contents/Resources/JianAppIcon.png"
sips -z 16 16 "$ICON_PNG" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_PNG" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_PNG" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_PNG" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_PNG" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_PNG" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_PNG" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_PNG" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Jian.icns"

codesign --force --deep --sign - "$APP"
(cd "$ROOT/dist" && /usr/bin/zip -qry "${ZIP:t}" "$APP_NAME.app" -x "*/._*" "__MACOSX/*")
(cd "$ROOT/dist" && shasum -a 256 "${ZIP:t}" > "${ZIP:t}.sha256")

mkdir -p "$DMG_STAGE"
cp -R "$APP" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGE" \
  -ov \
  -format UDZO \
  "$DMG"
shasum -a 256 "$DMG" > "$DMG.sha256"

echo "已生成："
echo "  $APP"
echo "  $ZIP"
echo "  $ZIP.sha256"
echo "  $DMG"
echo "  $DMG.sha256"
