#!/bin/sh
# Makes a notarized dist/Lidlezz-<version>.dmg and dist/latest.json for the site.
# One-time setup: a "Developer ID Application" certificate in the keychain and
#   xcrun notarytool store-credentials lidlezz --apple-id <id> --team-id <team> --password <app-specific password>
set -e
cd "$(dirname "$0")/.."
# Where the DMG will be downloadable from, and the site. Override with env vars until these are final.
DOWNLOAD_BASE=${DOWNLOAD_BASE:-https://github.com/witcharon/lidlezz-releases/releases/download}
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
SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
URL="$DOWNLOAD_BASE/v$V/Lidlezz-$V.dmg"
cat > dist/latest.json <<JSON
{ "version": "$V", "url": "$URL" }
JSON
sed -e "s|__VERSION__|$V|" -e "s|__SHA256__|$SHA|" -e "s|__URL__|$URL|" -e "s|__HOMEPAGE__|$HOMEPAGE|" \
  homebrew/lidlezz.rb.template > homebrew/lidlezz.rb
echo "release ready: $DMG, dist/latest.json (site root), homebrew/lidlezz.rb (your tap)"
