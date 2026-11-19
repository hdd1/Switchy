# Switchy

> 🚧 **Work in progress.** No release yet — build from source if you want to try it.

A small macOS menu-bar utility that fixes text typed in the wrong keyboard layout — **on demand**,
not automatically. No dictionaries to maintain, no network, nothing leaves your Mac.

[Русский](README.ru.md)

## Features

- **Fix typed text.** Typed `ghbdtn` instead of `привет`? Tap **Left Option** — the text is retyped
  in the right layout and the layout is switched.
- **Smart mode.** The first tap picks the most likely layout using macOS built-in spell checking and
  language recognition (on-device). Further taps cycle through the remaining layouts.
- **Fix selected text.** Select text and tap the same key.
- **Direct layout hotkeys.** One key per layout (e.g. F13 → English, F14 → Russian, F15 → Ukrainian).
  Optionally converts what you just typed into that layout.
- **Per-window layout memory.** Each window keeps its own layout — including switches made by Switchy.
- **Clipboard history** *(planned)* — text-only, with a quick picker panel.
- **Settings window** *(planned)* — all hotkeys, layout order, behavior.

## Requirements

- macOS 15 or later
- Permissions: **Accessibility** and **Input Monitoring** (needed to see keystrokes and retype text)

## Build from source

Requires Xcode (or Command Line Tools with Swift 6).

```bash
git clone https://github.com/hdd1/Switchy.git
cd Switchy
swift test                     # unit tests
scripts/build-app.sh --run     # builds build/Switchy.app and launches it
```

The build script signs the app with an `Apple Development` certificate so that macOS keeps
granted permissions across rebuilds. Use another identity with
`SWITCHY_SIGN_ID="..." scripts/build-app.sh`, or `SWITCHY_SIGN_ID=-` for ad-hoc signing.

## License

[MIT](LICENSE)
