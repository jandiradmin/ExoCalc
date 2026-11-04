#!/bin/bash
# Сборка ExoCalc.app.  Использование:
#   ./build.sh            — собрать в build/
#   ./build.sh --install  — собрать, установить в /Applications и запустить
#   ./build.sh --test     — только самопроверка движка
set -euo pipefail
cd "$(dirname "$0")"

if [[ "${1:-}" == "--test" ]]; then
    swift run -c release exocalc-cli --selftest
    exit $?
fi

echo "▸ Сборка…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"

APP="build/ExoCalc.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/ExoCalc" "$APP/Contents/MacOS/ExoCalc"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN/exocalc-cli" build/exocalc
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "▸ Самопроверка движка…"
build/exocalc --selftest || echo "⚠︎ Есть ошибки в самопроверке — пришлите вывод выше"

echo "✓ Готово: $APP"
echo "  CLI: build/exocalc \"600 usd in uah\""

if [[ "${1:-}" == "--install" ]]; then
    pkill -x ExoCalc 2>/dev/null || true
    sleep 0.5
    rm -rf /Applications/ExoCalc.app
    cp -R "$APP" /Applications/
    open /Applications/ExoCalc.app
    echo "✓ Установлено в /Applications и запущено"
fi
