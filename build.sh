#!/bin/bash
# Builds Buddy.app and installs it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"
APP=build/Bro.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
python3 make_stickers.py >/dev/null && python3 make_person.py >/dev/null
swiftc -O Sources/*.swift -o "$APP/Contents/MacOS/Buddy"
cp -R stickers "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Bro</string>
  <key>CFBundleDisplayName</key><string>Bro</string>
  <key>CFBundleIdentifier</key><string>com.shaid.desktopbuddy</string>
  <key>CFBundleExecutable</key><string>Buddy</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Bro listens when you tap the mic so you can talk to him.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Bro turns what you say into text so he can understand you.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Bro sorts your Downloads into folders when you ask him to tidy it.</string>
  <key>NSDesktopFolderUsageDescription</key><string>Bro sorts your Desktop into folders when you ask him to tidy it.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>Bro sorts your Documents into folders when you ask him to tidy it.</string>
  <key>NSAppleEventsUsageDescription</key><string>Bro checks whether you're on YouTube or Instagram and closes those tabs when time's up.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
mkdir -p ~/Applications
rm -rf ~/Applications/Buddy.app ~/Applications/Bro.app
cp -R "$APP" ~/Applications/
echo "Installed ~/Applications/Bro.app"
