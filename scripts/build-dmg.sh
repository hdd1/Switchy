#!/bin/bash
# Собирает релизный DMG: универсальный Switchy.app (Apple Silicon + Intel) + ярлык «Программы».
#
# Использование:  scripts/build-dmg.sh
# Результат:      build/Switchy-<версия>.dmg (+ SHA-256 в выводе)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIGN_ID="${SWITCHY_SIGN_ID:-Apple Development}"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/Support/Info.plist")"
STAGE="$ROOT/build/dmg"
DMG="$ROOT/build/Switchy-$VERSION.dmg"

SWITCHY_UNIVERSAL=1 "$ROOT/scripts/build-app.sh"

echo "=== DMG $VERSION ==="
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$ROOT/build/Switchy.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Switchy $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" -quiet
codesign --force --sign "$SIGN_ID" --timestamp=none "$DMG"
rm -rf "$STAGE"

echo "Готово: $DMG"
shasum -a 256 "$DMG"
