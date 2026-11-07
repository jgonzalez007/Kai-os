# Kai OS: Build Guide

Kai OS builds with Swift Package Manager. `Kai OS.xcodeproj` is an out-of-date skeleton: it still lists files that were deleted, so do not use it until it is regenerated.

## Quick start

```bash
git clone https://github.com/jgonzalez007/Kai-os
cd Kai-os
swift build          # build everything
swift test           # run the 122 checks (XCTest)
swift run "Kai OS"   # run the app
```

## Requirements

| Requirement | Needed |
|-------------|--------|
| macOS | 14.0 or later |
| Chip | Apple Silicon |
| Xcode | Required for `swift test` (XCTest). Select it with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| Swift | 5.9 or later |
| Ollama | Only for local chat: install it, start it, and pull a model |

If `swift build` fails with a dyld or SDK-mismatch error, your Command Line Tools and SDK versions disagree. Select a full Xcode as above.

## Targets (`Package.swift`)

| Target | Kind | Purpose |
|--------|------|---------|
| `KaiShared` | library | Chat models, cloud clients, Keychain |
| `KaiLocalAI` | library | Ollama client |
| `KaiLocalData` | library | Calendar, Mail, Notes, Spotlight |
| `KaiCapture` | library | Permissions, screen, speech, text insertion |
| `KaiNotchCore` | library | Notch geometry, hold gesture |
| `KaiActions` | library | Approved actions, morning cards, reply drafting |
| `KaiOS` | executable | The app (`Kai OS macOS/`) |
| `KaiChecksTests` | test | All checks, in `Tests/KaiChecksTests` |

## Tests

`swift test` runs one XCTest method per section. Each check is reported as its own activity, so a failure names the check. A few checks use real macOS tools (`osacompile`, `mdfind`) and need to run on a Mac.

## Signing and release

Not set up yet. `NOTARIZATION.md` and `scripts/` describe the intended flow, which needs a Developer ID certificate. There is no published DMG and no Homebrew tap.

## Troubleshooting

- **Chat says the server is unreachable:** start Ollama (`ollama serve`).
- **Calendar, Mail or Notes return nothing:** grant access in System Settings → Privacy & Security.
- **Screen capture or the Right Command hotkey does not work:** grant Screen Recording and Accessibility, then relaunch.
