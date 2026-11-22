# OpenKey Lite

A minimal Vietnamese input app for macOS: **Telex** typing, **Unicode** output, menu bar only.

OpenKey Lite is built on **[OpenKey](https://github.com/tuyenvm/OpenKey) by Tuyen Mai (Mai Vũ Tuyên)**. The whole typing mechanism (the Telex engine, spell checking, tone placement and the backspace sending technique) is OpenKey's. This project only trims the features and the interface.

## Download

Get the latest version from [Releases](https://github.com/vuluonganh/OpenKey-Lite/releases). Requires macOS 13 or later; runs on Apple Silicon and Intel.

The app is ad-hoc signed, not notarized by Apple, so macOS blocks the first launch. Go to **System Settings → Privacy & Security** and click **Open Anyway**.

## Usage

There is no settings window. Everything is in the menu bar menu (its labels are in Vietnamese):

| Menu item | What it does |
| --- | --- |
| **Gõ tiếng Việt** | Turns Vietnamese typing on or off. The switch shortcut is shown next to it (default ⌥Z). The icon shows the mode: solid **V** = Vietnamese, outlined **E** = English. |
| **Đặt dấu kiểu mới: hoà, uý** | New-style tone placement (hoà, uý). Turn off for the old style (hòa, úy). |
| **Giữ nguyên từ không phải tiếng Việt** | Keeps words that aren't Vietnamese as typed: "windows" stays "windows" instead of becoming "ưindows". |
| **Kêu bíp khi chuyển chế độ** | Beeps when the shortcut switches between Vietnamese and English. |
| **Mở cùng macOS** | Opens OpenKey Lite when you log in. |
| **Thoát OpenKey Lite** | Quits the app. |

On first launch, macOS asks for permission to control the computer (macOS 27: *Device Control and Data Access*; earlier versions: *Accessibility*). Typing starts as soon as you allow it; no relaunch needed.

Turn off other Vietnamese input apps while using OpenKey Lite to avoid conflicts.

## Differences from OpenKey

| | OpenKey 2.0.4 | OpenKey Lite |
| --- | --- | --- |
| Input methods | Telex, VNI, Simple Telex | Telex |
| Code tables | Unicode, TCVN3, VNI Windows, Unicode Compound, CP 1258 | Unicode |
| Interface | 4-tab control panel, macro editor, convert tool, About window | Menu bar menu only |
| Macros, convert tool, smart switching, Quick Telex, auto-capitalization, auto-update | Yes | No |
| Platforms | macOS, Windows, Linux (in development) | macOS 13 or later |
| App size | 1.7 MB | about 480 KB |

## Building

Requires macOS 13 or later and Xcode.

1. Open `Sources/OpenKey/macOS/OpenKey.xcodeproj`.
2. Choose the **OpenKey** scheme and select **Product → Build** (or **Archive** for a release build).

Or from the command line:

```
xcodebuild -project Sources/OpenKey/macOS/OpenKey.xcodeproj -scheme OpenKey -configuration Release build
```

The project signs the app with *Sign to Run Locally* (ad-hoc), so no Apple Developer account is needed. Each rebuild counts as a new app to macOS, so you need to grant permission again.

## Tests

```
Tests/run.sh
```

Runs the Telex test cases and compares the engine's output with `Tests/golden.txt`. If you change typing behavior on purpose, run `Tests/run.sh --update` to record the new output.

## Credits and license

- Typing engine and original source: **OpenKey** © 2019 Tuyen Mai (Mai Vũ Tuyên), https://github.com/tuyenvm/OpenKey. Please support the original author on the [OpenKey page](https://github.com/tuyenvm/OpenKey).
- OpenKey Lite is a modified version of OpenKey 2.0.4 (commit `89c2fd3`), modified by vuluonganh starting November 2026. The changes are listed in [CHANGELOG.md](CHANGELOG.md).
- Licensed under the **GNU GPL v3**, like the original. See [LICENSE](LICENSE). The original copyright notices in the source files are kept.
