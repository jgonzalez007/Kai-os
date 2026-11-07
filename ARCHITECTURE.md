# Kai OS: Architecture

> This describes the code as it is on 2026-11-07. The planned design (knowledge base, computer-use, Night Shift) is in [KAI-DEVELOPMENT-PLAN.md](KAI-DEVELOPMENT-PLAN.md), not here.

Bundle ID: `ai.kai` · Build: Swift Package Manager · Minimum: macOS 14

## Layout

```
Package.swift
KaiShared/        Chat models, ChatGPT and Claude clients, Keychain
KaiLocalAI/       Ollama client (localhost:11434)
KaiLocalData/     Calendar, Outlook Calendar, Mail, Notes, Spotlight
KaiCapture/       Permissions, screen grab, speech, text insertion
KaiNotchCore/     Notch geometry and the hold gesture (pure, tested)
KaiActions/       Approved actions, morning cards, reply drafting, writing style
Kai OS macOS/     The app target
  App/              Entry point, AppState, assistant tools, app awareness
  Views/            SwiftUI views and settings
  KaiMagic/         Notch window, notch view, Right Command hotkey
  KaiDoubleTap/     Double Tap reply drafting
  KaiEngine/        Engine, fallback chain, PII scan (not used by the app yet)
  KaiIngestion/     Connector protocol and REST connectors (not used by the app yet)
  KaiProactive/     Placeholder
  StubFrameworks.swift   Fake EventKit and UserNotifications types
Tests/KaiChecksTests/    the checks, run with `swift test`
```

## Libraries

| Module | What it does |
|--------|--------------|
| `KaiShared` | `KaiChatService` picks the active client. `OpenAIChatClient` and `AnthropicChatClient` stream chat. `KaiKeychain` stores API keys in the Keychain and migrates any legacy plaintext key out of UserDefaults. |
| `KaiLocalAI` | `KaiOllamaClient` streams chat and lists models over HTTP. |
| `KaiLocalData` | Read-only access to Apple Calendar (EventKit), Outlook Calendar (Microsoft Graph, signed in with `KaiMicrosoftAuth`, OAuth code flow with PKCE), Mail and Notes (AppleScript), and Spotlight search (`mdfind`). |
| `KaiCapture` | Permission status and requests, screen capture, speech transcription, and writing text into other apps. |
| `KaiNotchCore` | Notch layout for each Mac and the hold-to-talk gesture state machine. |
| `KaiActions` | Parses model proposals into actions. Only a user-approved card runs. Calendar event, mail draft and notification only. No shell, no send. Also morning cards and reply drafting. |

## Data flow

```
User (notch, hotkey, voice)
  → KaiAppState (App/)
  → active chat client: Ollama, OpenAI or Anthropic
  → tool calls (App/KaiAssistantTools):
        list_calendar_events, mail, notes, search_files   → KaiLocalData (read-only)
        propose_calendar_event / mail draft / notification → KaiActions → approval card → user decides
```

## Not used by the app yet

- `KaiEngine/`: written for on-device inference with a fallback chain. Nothing in the app calls it. I did not verify that its inference is real.
- `KaiIngestion/`: a `Connector` protocol with Apple, Gmail, Google Calendar, Notes and Files connectors. The OAuth ones have no way to sign in (`authenticate()` throws), and the app does not use any of them.
- `StubFrameworks.swift`: fake EventKit and UserNotifications types in the app target. They can shadow the real frameworks, so do not rely on them.

## Privacy model

- Local chat sends nothing off the Mac.
- Cloud chat is opt-in. Your messages go to OpenAI or Anthropic with your own key. API keys are stored in the Keychain.
- Mail, Calendar and Notes are read through macOS permissions that you grant.
- Outlook Calendar uses your own Microsoft app registration and a read-only scope. Tokens are in the Keychain.
- Nothing is sent or created without an approval card, and Kai never sends mail.
- No telemetry.

## Testing

`swift test` runs `Tests/KaiChecksTests`. See [BUILD.md](BUILD.md).
