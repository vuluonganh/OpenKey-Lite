# OpenKey Lite Change Log

## 1.0.0 (2026-11-22)

First release. Derived from [OpenKey](https://github.com/tuyenvm/OpenKey) 2.0.4 by Tuyen Mai (commit `89c2fd3`). The typing engine is OpenKey's; this release trims it down.

### Kept from OpenKey
- Telex typing engine, spell checking, tone placement (old and new style), restoring invalid words.
- The backspace sending technique, including the browser autocomplete fix and Spotlight handling.
- Switching Vietnamese/English with a shortcut, with an optional beep.

### Removed
- VNI and Simple Telex input methods.
- Code tables other than Unicode (TCVN3, VNI Windows, Unicode Compound, CP 1258).
- Macros, the convert tool, smart switching per app, Quick Telex, quick start/end consonants, auto-capitalization, temporary off by modifier keys, "turn off for other keyboard languages", Dvorak/Colemak compatibility, send-key-by-key mode, the Chromium beta fix.
- The settings window, About window, update checker, Dock icon option, login helper app and updater.
- Windows and Linux sources.

### Changed
- Menu bar only: one menu with Vietnamese on/off, new-style tones, keep non-Vietnamese words, beep, open at login and quit.
- Menu bar icon drawn in code (solid V = Vietnamese, outlined E = English), adapts to light and dark menu bars.
- Waits for permission instead of quitting, and starts typing as soon as permission is granted.
- Open at login uses `SMAppService` (no helper app).
- Requires macOS 13 or later.
- The Spotlight check is cached instead of listing all windows on every keystroke.
- The keyboard event tap no longer listens to key-up and mouse-drag events, and turns itself back on if macOS disables it.
- Builds with local ad-hoc signing; no Apple Developer account needed.

### Added
- Engine regression tests (`Tests/run.sh`).
