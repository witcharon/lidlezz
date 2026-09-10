#!/bin/sh
# Builds dist/Lidlezz.app: menu bar app, the lidlezz CLI, the root helper daemon, resources and icon.
# Signs with $SIGN_IDENTITY, else the first "Developer ID Application" / "Apple Development" identity, else ad hoc.
set -e
cd "$(dirname "$0")/.."
# @executable_path/../Frameworks so the app finds the embedded Sparkle.framework.
swift build -c release -Xlinker -rpath -Xlinker @executable_path/../Frameworks
APP=dist/Lidlezz.app
ID=com.cansincengiz.lidlezz
rm -rf "$APP" dist/icon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchDaemons" "$APP/Contents/Frameworks"
cp .build/release/LidlezzApp .build/release/lidlezz .build/release/LidlezzHelper "$APP/Contents/MacOS/"
cp -R .build/release/lidlezz_LidlezzApp.bundle "$APP/Contents/Resources/"
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework \
      "$APP/Contents/Frameworks/Sparkle.framework"
swift scripts/make-icon.swift Sources/LidlezzApp/Resources/icon.png dist/icon.iconset
iconutil -c icns dist/icon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf dist/icon.iconset

cat > "$APP/Contents/Library/LaunchDaemons/$ID.helper.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$ID.helper</string>
  <key>BundleProgram</key><string>Contents/MacOS/LidlezzHelper</string>
  <key>MachServices</key><dict><key>$ID.helper</key><true/></dict>
  <key>AssociatedBundleIdentifiers</key><array><string>$ID</string></array>
</dict></plist>
PLIST

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Lidlezz</string>
  <key>CFBundleDisplayName</key><string>Lidlezz</string>
  <key>CFBundleIdentifier</key><string>$ID</string>
  <key>CFBundleExecutable</key><string>LidlezzApp</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$(cat VERSION)</string>
  <key>CFBundleVersion</key><string>$(cat VERSION)</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>SUFeedURL</key><string>https://lidlezz.app/appcast.xml</string>
  <key>SUPublicEDKey</key><string>Sl/5iqg8/7A7MfOxoX+E0LbgzwRuRX+VDXc1JIub8dM=</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Lidlezz opens Terminal to resume your Claude Code session.</string>
</dict></plist>
PLIST

cat > dist/app.entitlements <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.automation.apple-events</key><true/>
</dict></plist>
PLIST

# SHA-1 of the identity, so the name's spaces never reach codesign.
IDENTITY=${SIGN_IDENTITY:-$( (security find-identity -v -p codesigning | grep 'Developer ID Application'; security find-identity -v -p codesigning | grep 'Apple Development') | head -1 | awk '{print $2}')}
if [ -n "$IDENTITY" ]; then
  SIGN="codesign --force --timestamp --options runtime --sign $IDENTITY"
else
  SIGN="codesign --force --sign -"
fi
echo "signing as: ${IDENTITY:-ad hoc}"
# Sparkle signs from the inside out: helpers first, then the framework, then the app.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
for part in "$SPARKLE/Versions/B/XPCServices/Downloader.xpc" "$SPARKLE/Versions/B/XPCServices/Installer.xpc" \
            "$SPARKLE/Versions/B/Updater.app" "$SPARKLE/Versions/B/Autoupdate"; do
  $SIGN "$part"
done
$SIGN "$SPARKLE"
$SIGN --identifier "$ID.helper" "$APP/Contents/MacOS/LidlezzHelper"
$SIGN --identifier lidlezz "$APP/Contents/MacOS/lidlezz"
$SIGN --entitlements dist/app.entitlements --identifier "$ID" "$APP"
codesign --verify --deep --strict "$APP"
echo "built $APP  (open dist/Lidlezz.app)"
