# Switchy — план реализации

Спецификация: `SPEC.md`. Каждый этап заканчивается рабочей сборкой, которую можно проверить руками.

## Структура

```
Switchy/
  Package.swift
  Sources/Switchy/
    App/          — точка входа, AppDelegate, строка меню, онбординг прав
    Input/        — EventTap, HotkeyEngine, TypingBuffer, EventPoster (синтетика)
    Layouts/      — InputSources (TIS: список/текущая/переключение), LayoutMapper (UCKeyTranslate)
    Conversion/   — TypedConverter, SelectionConverter, LayoutDetector, SmartDetector
    Windows/      — FocusTracker (NSWorkspace + AXObserver), WindowLayoutMemory
    Clipboard/    — ClipboardMonitor, ClipboardStore, ClipboardPanel
    Settings/     — модель настроек, SwiftUI-окно, HotkeyRecorder
  Tests/SwitchyTests/ — LayoutMapper, LayoutDetector, TypingBuffer, HotkeyEngine (чистая логика)
  Resources/Info.plist  — LSUIElement, bundle id `ua.wolf.switchy` (или иной)
  scripts/build-app.sh  — swift build → Switchy.app → codesign
  scripts/install.sh    — копирование в /Applications и перезапуск
```

## Этапы

0. **Каркас.** Package.swift, Info.plist, скрипт сборки и подписи, иконка в строке меню, проверка
   прав (AXIsProcessTrusted / Input Monitoring) и кнопки открытия Системных настроек.
1. **Раскладки.** Список включённых источников ввода, текущая, переключение, индикатор EN/RU/UA
   в строке меню. `LayoutMapper`: keycode+модификаторы → символ для любой раскладки и обратно.
   Тесты маппинга EN/RU/UA.
2. **Перехват и хоткеи.** CGEventTap, движок хоткеев (тапы, двойные тапы, одиночные клавиши,
   сочетания), прямые хоткеи раскладок F13/F14/F15 с захардкоженными дефолтами.
3. **Перевод набранного.** TypingBuffer с правилами сброса, перевод по кругу, повторный хоткей,
   перевод прямыми хоткеями. Проверка в PhpStorm, Chrome/Safari, Telegram, Заметках, Терминале,
   Slack/другом Electron.
3a. **Умный перевод.** `SmartDetector` (NLLanguageRecognizer + NSSpellChecker), порог уверенности,
   серия нажатий «исходная раскладка последней». Набор тестовых фраз (EN/RU/UA, короткие слова,
   код, смешанное) — и тест, и инструмент подбора порога.
4. **Перевод выделения.** AX-чтение / Cmd+C, определение исходной раскладки, вставка с
   восстановлением буфера обмена.
5. **Память по окнам.** FocusTracker, WindowLayoutMemory, проверка системной опции «автоматически
   переключаться на источник ввода документа».
6. **Окно настроек.** Модель настроек, HotkeyRecorder, все разделы из SPEC §6, автозапуск.
7. **История буфера обмена.** Монитор, хранилище, панель выбора, фильтр, вставка.
8. **Шлифовка.** Исключения по приложениям, пауза, install-скрипт, иконка, README.

После этапов 3, 5 и 7 — ручное тестирование тобой в реальных программах.

## Что нужно с твоей стороны

- Принять лицензию Xcode и сделать его активным:
  `sudo xcodebuild -license accept && sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
- Для подписи: Xcode → Settings → Accounts → добавить свой Apple ID (бесплатно) → Manage
  Certificates → «+» → Apple Development. Тогда права доступа не будут слетать при пересборке.
- Выдать Switchy права Accessibility и Input Monitoring при первом запуске.
- Выключить в Системных настройках → Клавиатура → Источники ввода опцию «Автоматически
  переключаться на источник ввода документа» (этап 5).
- Если используешь Caramba / Input Source Pro — выключить их на время тестов, чтобы не конфликтовали.
