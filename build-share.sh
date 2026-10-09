#!/bin/bash
# Builds the shareable Bro for other Macs:
#   - no voice (no mic, no speech), no API keys inside, works fully offline
#   - Agentic chat is opt-in: the person adds their own API key in Settings
#   - universal binary (Apple Silicon + Intel), packaged as dist/Bro-<version>.dmg
#
#   ./build-share.sh                          bundles Biscuit (default), Bro Denim, Iron Man, Drop, Buddy
#   CHARS="denim hydro biscuit" ./build-share.sh   bundles several (first one is the default + app icon)
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${VERSION:-1.0}"
STICKERS="${STICKERS:-$HOME/Library/Application Support/DesktopBuddy/stickers}"
CHARS="${CHARS:-biscuit denim ironman drop buddy}"
FIRST="${CHARS%% *}"
APP="dist/Bro.app"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

rm -rf ./dist/Bro.app ./dist/*.dmg
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/stickers"

echo "• compiling (Apple Silicon + Intel)"
for arch in arm64 x86_64; do
  swiftc -O -D SHARE_BUILD -target "$arch-apple-macos13.0" Sources/*.swift -o "$WORK/Bro-$arch"
done
lipo -create -output "$APP/Contents/MacOS/Bro" "$WORK/Bro-arm64" "$WORK/Bro-x86_64"

for c in $CHARS; do
  echo "• packing character '$c'"
  swift tools/pack_stickers.swift "$STICKERS/$c" "$APP/Contents/Resources/stickers/$c" 420
  [ -f "$STICKERS/$c/character.json" ] && cp "$STICKERS/$c/character.json" "$APP/Contents/Resources/stickers/$c/"
done
echo "• app icon"
swift tools/make_icon.swift "$STICKERS/$FIRST/idle.png" "$APP/Contents/Resources/Bro.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Bro</string>
  <key>CFBundleDisplayName</key><string>Bro</string>
  <key>CFBundleIdentifier</key><string>com.shaid360.bro</string>
  <key>CFBundleExecutable</key><string>Bro</string>
  <key>CFBundleIconFile</key><string>Bro</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Bro by Shaid · shaid360.com</string>
  <key>NSAppleEventsUsageDescription</key><string>Bro checks whether you're on YouTube, Instagram or a streaming site so he can time you, and closes those tabs when your time is up.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Bro sorts your Downloads into folders when you ask him to tidy it.</string>
  <key>NSDesktopFolderUsageDescription</key><string>Bro sorts your Desktop into folders when you ask him to tidy it.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>Bro sorts your Documents into folders when you ask him to tidy it.</string>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP"

echo "• disk image"
STAGE="$WORK/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp share/READ-ME-FIRST.txt "$STAGE/READ ME FIRST.txt"
DMG="dist/Bro-$VERSION.dmg"
hdiutil create -quiet -volname "Bro" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
echo "Done → $DMG ($(du -h "$DMG" | cut -f1))"
