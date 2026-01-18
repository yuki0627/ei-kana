# ei-kana

A macOS app for switching input sources. Press left/right Command key alone to switch input sources.

- **Left Command** → switches to the configured input source
- **Right Command** → switches to another configured input source

You can select any installed input source for each key from the menu bar.

Example: If you have ABC and Japanese installed, you can set Left ⌘ to ABC and Right ⌘ to Japanese.

## Supported OS

- macOS 14.0 (Sonoma) or later
- Tested on macOS 26 (Tahoe)

## Installation

### Pre-built App

Download from [Releases](https://github.com/yuki0627/ei-kana/releases/)

### Build from Source

```bash
cd ei-kana
swiftc -parse-as-library -emit-executable -o ei-kana \
  ei_kanaApp.swift KeyboardMonitor.swift MenuBarView.swift \
  -framework Cocoa -framework Carbon -target arm64-apple-macosx14.0
```

## Usage

1. Launch the app
2. Grant accessibility permission (System Settings > Privacy & Security > Accessibility)
3. A "⌘" icon will appear in the menu bar
4. Press left/right Command key to switch input sources

## Technical Background

On macOS 26 (Tahoe), the traditional keycode method (keyCode 102/104) for switching input sources no longer works. This app uses the `TISSelectInputSource` API to switch input sources directly.

## Credits

This project was inspired by [cmd-eikana](https://github.com/iMasanari/cmd-eikana).

## License

MIT License
