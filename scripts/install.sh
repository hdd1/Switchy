#!/bin/bash
# Собирает Switchy и устанавливает в /Applications (заменяя прежнюю версию), затем запускает.
#
# Использование:  scripts/install.sh
#
# После первой установки в /Applications включите заново «Запускать при входе в систему»
# в настройках Switchy, если раньше включали его для сборки из build/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="/Applications/Switchy.app"

"$ROOT/scripts/build-app.sh"

echo "=== Установка в $DEST ==="
pkill -x Switchy 2>/dev/null && sleep 0.5 || true
rm -rf "$DEST"
cp -R "$ROOT/build/Switchy.app" "$DEST"
open "$DEST"
echo "Установлен и запущен: $DEST"
