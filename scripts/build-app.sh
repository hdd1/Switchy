#!/bin/bash
# Собирает Switchy.app в build/ и подписывает его сертификатом Apple Development
# (стабильная подпись — права Accessibility / Input Monitoring не слетают при пересборке).
#
# Использование:
#   scripts/build-app.sh          — только собрать
#   scripts/build-app.sh --run    — собрать, остановить запущенный Switchy и запустить новый
#
# Другой сертификат: SWITCHY_SIGN_ID="..." scripts/build-app.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Switchy.app"
SIGN_ID="${SWITCHY_SIGN_ID:-Apple Development}"

cd "$ROOT"

echo "=== swift build (release) ==="
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

echo "=== Сборка Switchy.app ==="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Switchy" "$APP/Contents/MacOS/Switchy"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"

echo "=== Подпись ($SIGN_ID) ==="
codesign --force --sign "$SIGN_ID" --timestamp=none "$APP"
codesign --verify --strict "$APP"

echo "Готово: $APP"

if [[ "${1:-}" == "--run" ]]; then
    pkill -x Switchy 2>/dev/null && sleep 0.5 || true
    open "$APP"
    echo "Запущен."
fi
