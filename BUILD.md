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
| `KaiDesk` | library | Clipboard history, Shelf, Claude Code hook events and the local socket |
| `kai-hook` | executable | The command Claude Code hooks run (`KaiHook/`); `install-app.sh` copies it into the app |
| `KaiOS` | executable | The app (`Kai OS macOS/`) |
| `KaiChecksTests` | test | All checks, in `Tests/KaiChecksTests` |

## Tests

`swift test` runs one XCTest method per section. Each check is reported as its own activity, so a failure names the check. A few checks use real macOS tools (`osacompile`, `mdfind`) and need to run on a Mac.

## Slack setup

Kai reads Slack with a token you create for your own Slack app. It uses read-only scopes and has no way to post, edit or delete.

1. Go to https://api.slack.com/apps, choose **Create New App → From a manifest**, pick your workspace, and paste the contents of [`slack-app-manifest.yaml`](slack-app-manifest.yaml). It sets the name and these read-only user scopes: `channels:read`, `groups:read`, `im:read`, `mpim:read`, `channels:history`, `groups:history`, `im:history`, `mpim:history`, `users:read` and `search:read`.
2. Click **Install to Workspace**. In a company workspace this may send a request to an admin, and nothing works until they approve it. Check your company's policy on custom Slack apps first.
3. Under **OAuth & Permissions**, copy the **User OAuth Token** (it starts with `xoxp-`) and paste it into Kai OS → Settings → Slack → Connect. Don't share it: it acts as you. It is stored in your Keychain.
4. Click **Index now** under Knowledge base to pull recent messages in, and ask Kai things like "what did Ana say about the launch in Slack?".

You can leave out the `im` and `mpim` scopes if you never want direct messages read.

To read the Slack window that is open on your Mac without any token, give Kai OS Accessibility permission and ask about "this Slack channel". It reads only what is on screen, never your message box.

## Claude Code hooks

Turn on Settings → Desk → Listen for Claude Code, copy the hook setup, and paste it into `~/.claude/settings.json` by hand. Steps and safety notes are in [INSTALL-HOOKS.md](INSTALL-HOOKS.md). `swift run` works too: the helper is built beside the app and Settings shows its path.

## Signing and release

Kai OS is signed ad hoc (free). It is not notarized, which needs a paid Apple Developer account, so a hand-downloaded copy needs right-click → Open once. The install script and the cask clear the download flag for you.

To make a release:

1. Raise `CFBundleShortVersionString` (and `CFBundleVersion`) in `Kai OS macOS/Info.plist`.
2. `scripts/package-release.sh` builds a release copy and writes `dist/Kai-OS.zip` and `dist/Kai-OS.zip.sha256`. It publishes nothing.
3. Create a GitHub release tagged `v<version>` and attach both files. `scripts/install.sh` and the in-app update check both read the latest release.
4. Optional: put the new checksum in `Casks/kai-os.rb` and publish it in a tap repository named `homebrew-kai-os`.

`scripts/install-app.sh` is the developer version: it builds a debug copy, installs it in `~/Applications` and relaunches it. It signs with `scripts/sign-app.sh`, which uses `$KAI_SIGN_IDENTITY`, then an "Apple Development" certificate, then the local "Kai OS Local Dev" certificate, and only then ad-hoc. macOS ties permission grants to the signature, so an ad-hoc build loses Screen Recording, Accessibility and other grants on every rebuild. To keep them, do one of these once:

- **Apple ID (free):** Xcode, Settings, Accounts, add your Apple ID, Manage Certificates, +, Apple Development.
- **Trust the local certificate:** `scripts/trust-local-signing.sh` (macOS asks for your password; the trust is for your user only, and the script prints the command to undo it).

Then rebuild. The script prints the designated requirement it signed with: it should name a certificate (`certificate leaf = H"..."`), not a `cdhash`. `NOTARIZATION.md` describes the notarized flow for if you get a Developer ID.

## Sandbox and entitlements

Kai OS is not sandboxed, on purpose. It drives Apple Mail and Notes with AppleScript, reads Calendar, uses Accessibility and Screen Recording, keeps a socket and a database in Application Support, and installs a launch agent for Night Shift. The App Sandbox blocks most of that, so adding `com.apple.security.app-sandbox` would break the app. It is only required for the Mac App Store, which Kai does not target. Permissions are asked for at runtime (see the setup guide). The bundle identifier `ai.kai` is kept: changing it would reset the Keychain items, saved settings and permissions.

## Troubleshooting

- **Chat says the server is unreachable:** start Ollama (`ollama serve`).
- **Calendar, Mail or Notes return nothing:** grant access in System Settings → Privacy & Security.
- **Screen capture or the Right Command hotkey does not work:** grant Screen Recording and Accessibility, then relaunch.
