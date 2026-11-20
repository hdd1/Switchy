#!/bin/bash
# Собирает Switchy.app в build/ и подписывает его сертификатом Apple Development
# (стабильная подпись — права Accessibility / Input Monitoring не слетают при пересборке).
#
# Использование:
#   scripts/build-app.sh          — только собрать
#   scripts/build-app.sh --run    — собрать, остановить запущенный Switchy и запустить новый
#
# Другой сертификат: SWITCHY_SIGN_ID="..." scripts/build-app.sh  (SWITCHY_SIGN_ID=- — ad-hoc)
# Универсальная сборка (Apple Silicon + Intel): SWITCHY_UNIVERSAL=1 scripts/build-app.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Switchy.app"
SIGN_ID="${SWITCHY_SIGN_ID:-Apple Development}"

cd "$ROOT"

ARCH_FLAGS=(--arch arm64)
if [[ "${SWITCHY_UNIVERSAL:-0}" == "1" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "=== swift build (release, ${ARCH_FLAGS[*]}) ==="
swift build -c release "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

echo "=== Сборка Switchy.app ==="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Switchy" "$APP/Contents/MacOS/Switchy"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Support/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp -R "$ROOT/Support/Localization/"*.lproj "$APP/Contents/Resources/"

echo "=== Подпись ($SIGN_ID) ==="
codesign --force --sign "$SIGN_ID" --timestamp=none "$APP"
codesign --verify --strict "$APP"

echo "Готово: $APP"

if [[ "${1:-}" == "--run" ]]; then
    pkill -x Switchy 2>/dev/null && sleep 0.5 || true
    open "$APP"
    echo "Запущен."
fi
