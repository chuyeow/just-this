#!/usr/bin/env bash
# Package build/Just This.app into build/JustThis-<VERSION>.dmg with an Applications shortcut.
# Usage: VERSION=1.0.3 scripts/make-dmg.sh   (run scripts/build-app.sh first)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-1.0}"
APP="build/Just This.app"
DMG="build/JustThis-$VERSION.dmg"
[[ -d "$APP" ]] || { echo "Missing $APP; run scripts/build-app.sh" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Just This" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "$DMG"
