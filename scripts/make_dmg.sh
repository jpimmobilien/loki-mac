#!/bin/bash
# Erstellt dist/LOKI-<Version>.dmg aus build/LOKI.app (mit Verknüpfung „Programme“ und Installationshinweis).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="${VERSION:-0.1.0}"
APP="build/LOKI.app"
test -d "$APP" || { echo "✗ $APP fehlt – zuerst scripts/build.sh"; exit 1; }

STAGE="build/dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE" dist
ditto "$APP" "$STAGE/LOKI.app"
ln -s /Applications "$STAGE/Programme"
cp "Packaging/Installation – bitte lesen.txt" "$STAGE/"

DMG="dist/LOKI-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "LOKI $VERSION" -srcfolder "$STAGE" -ov -format UDZO -imagekey zlib-level=9 "$DMG"
hdiutil verify "$DMG"

# Prüfen: einhängen, Inhalt und Signatur kontrollieren
MNT="$(mktemp -d)"
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MNT" >/dev/null
ls -la "$MNT"
codesign --verify --deep --strict "$MNT/LOKI.app"
lipo -archs "$MNT/LOKI.app/Contents/MacOS/LOKI"
hdiutil detach "$MNT" >/dev/null

(cd dist && shasum -a 256 "LOKI-$VERSION.dmg" > "LOKI-$VERSION.dmg.sha256")
echo "✓ $DMG ($(du -h "$DMG" | cut -f1))"
cat "dist/LOKI-$VERSION.dmg.sha256"
