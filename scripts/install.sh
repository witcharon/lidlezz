#!/bin/sh
# Builds Lidlezz.app, installs it to /Applications, points the Claude Code hooks at it and launches it.
set -e
cd "$(dirname "$0")/.."
./scripts/bundle.sh
pkill -f "Lidlezz.app/Contents/MacOS/LidlezzApp" || true
rm -rf /Applications/Lidlezz.app
ditto dist/Lidlezz.app /Applications/Lidlezz.app
/Applications/Lidlezz.app/Contents/MacOS/lidlezz hooks install
/Applications/Lidlezz.app/Contents/MacOS/lidlezz helper install
open /Applications/Lidlezz.app
echo "installed /Applications/Lidlezz.app"
