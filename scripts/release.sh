#!/bin/sh
# Makes a notarized dist/Lidlezz-<version>.dmg (plus a stable-named copy), the appcast and dist/latest.json. See RELEASING.md.
# One-time setup: a "Developer ID Application" certificate in the keychain and
#   xcrun notarytool store-credentials lidlezz --apple-id <id> --team-id <team> --password <app-specific password>
set -e
cd "$(dirname "$0")/.."
DOWNLOAD_BASE=${DOWNLOAD_BASE:-https://github.com/witcharon/lidlezz/releases/download}
HOMEPAGE=${HOMEPAGE:-https://lidlezz.app}
security find-identity -v -p codesigning | grep -q "Developer ID Application" || { echo "need a Developer ID Application certificate"; exit 1; }
export SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk '{print $2}')
./scripts/bundle.sh
V=$(cat VERSION)
DMG=dist/Lidlezz-$V.dmg
rm -rf dist/dmg "$DMG"
mkdir -p dist/dmg
cp -R dist/Lidlezz.app dist/dmg/
ln -s /Applications dist/dmg/Applications
hdiutil create -volname Lidlezz -srcfolder dist/dmg -ov -format UDZO "$DMG" >/dev/null
rm -rf dist/dmg
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile lidlezz --wait
xcrun stapler staple "$DMG"
# Same file under a fixed name, so releases/latest/download/Lidlezz.dmg always works.
cp "$DMG" dist/Lidlezz.dmg
# Sparkle's feed. One item is enough: the app only needs to learn that a newer build exists.
APPCAST_TOOL=.build/artifacts/sparkle/Sparkle/bin/generate_appcast
rm -rf dist/appcast && mkdir -p dist/appcast
cp "$DMG" dist/appcast/
"$APPCAST_TOOL" --download-url-prefix "$DOWNLOAD_BASE/v$V/" --link "$HOMEPAGE" dist/appcast >/dev/null
cp dist/appcast/appcast.xml dist/appcast.xml

SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
URL="$DOWNLOAD_BASE/v$V/Lidlezz-$V.dmg"
cat > dist/latest.json <<JSON
{ "version": "$V", "url": "$URL" }
JSON
sed -e "s|__VERSION__|$V|" -e "s|__SHA256__|$SHA|" -e "s|__URL__|$URL|" -e "s|__HOMEPAGE__|$HOMEPAGE|" \
  homebrew/lidlezz.rb.template > homebrew/lidlezz.rb
echo "release ready:"
echo "  $DMG dist/Lidlezz.dmg → gh release create v$V ... --repo witcharon/lidlezz"
echo "  dist/appcast.xml     → lidlezz-web/public/appcast.xml   (Sparkle, DMG users)"
echo "  dist/latest.json     → lidlezz-web/public/latest.json   (Homebrew users' notice)"
echo "  homebrew/lidlezz.rb  → witcharon/homebrew-tap Casks/"
