# Kai OS: Build Guide

Kai OS builds with Swift Package Manager. There is no `.xcodeproj`: open the folder (or `Package.swift`) in Xcode and use the `KaiOS` scheme, or build from the command line. `scripts/install-app.sh` builds and installs `~/Applications/Kai OS.app`.

## Quick start

```bash
git clone https://github.com/jgonzalez007/Kai-os
cd Kai-os
swift build          # build everything
swift test           # run the 122 checks (XCTest)
swift run "Kai OS"   # run the app
xcodebuild -scheme KaiOS -destination 'platform=macOS' test   # same tests through Xcode
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

## Slack setup

Kai reads Slack with a token you create for your own Slack app. It uses read-only scopes and has no way to post, edit or delete.

1. Go to https://api.slack.com/apps and choose **Create New App → From scratch**. Pick your workspace.
2. Under **OAuth & Permissions → User Token Scopes**, add: `channels:read`, `groups:read`, `im:read`, `mpim:read`, `channels:history`, `groups:history`, `im:history`, `mpim:history`, `users:read` and `search:read`.
3. Click **Install to Workspace**. In a company workspace this may send a request to an admin, and nothing works until they approve it.
4. Copy the **User OAuth Token** (it starts with `xoxp-`) and paste it into Kai OS → Settings → Slack → Connect. Don't share it: it acts as you. It is stored in your Keychain.
5. Click **Index now** under Knowledge base to pull recent messages in, and ask Kai things like "what did Ana say about the launch in Slack?".

You can leave out the `im` and `mpim` scopes if you never want direct messages read.

To read the Slack window that is open on your Mac without any token, give Kai OS Accessibility permission and ask about "this Slack channel". It reads only what is on screen, never your message box.

## Signing and release

Not set up yet. `NOTARIZATION.md` and `scripts/` describe the intended flow, which needs a Developer ID certificate. There is no published DMG and no Homebrew tap.

## Troubleshooting

- **Chat says the server is unreachable:** start Ollama (`ollama serve`).
- **Calendar, Mail or Notes return nothing:** grant access in System Settings → Privacy & Security.
- **Screen capture or the Right Command hotkey does not work:** grant Screen Recording and Accessibility, then relaunch.
