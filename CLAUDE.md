# ei-kana Development Notes

## Language Policy

- All documentation (README, release notes, etc.) should be written in English
- UI text should be in English
- Git commit messages should be in English
- Code comments can be in either English or Japanese

## References

- Original cmd-eikana: https://github.com/iMasanari/cmd-eikana

## Technical Notes

- On macOS Tahoe (26), input source switching via keyCode 102/104 no longer works
- Changed implementation to use `TISSelectInputSource` API for direct input source switching
- Launch at login uses `SMAppService.mainApp.register()` / `.unregister()` (macOS 13+)
- Google Japanese Input support: Only target selectable input sources (`kTISPropertyInputSourceIsSelectCapable`)

## Release

- GitHub Actions runner should match the local development macOS version (currently `macos-26`)
- SDK version differences affect MenuBarExtra appearance

## Differences from Original cmd-eikana

- Original: Sends keyCode 102/104 → macOS selects input source (switches within Google IME if installed)
- ei-kana: Directly specifies input source via `TISSelectInputSource` API
