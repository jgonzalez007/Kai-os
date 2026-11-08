# Kai OS: Architecture

> This describes the code as it is on 2026-11-07. The planned design (knowledge base, computer-use, Night Shift) is in [KAI-DEVELOPMENT-PLAN.md](KAI-DEVELOPMENT-PLAN.md), not here.

Bundle ID: `ai.kai` · Build: Swift Package Manager · Minimum: macOS 14

## Layout

```
Package.swift
KaiShared/        Chat models, ChatGPT and Claude clients, Keychain
KaiLocalAI/       Ollama client (localhost:11434)
KaiLocalData/     Calendar, Mail, Notes and Spotlight sources
KaiCapture/       Permissions, screen grab, speech, text insertion
KaiNotchCore/     Notch geometry and the hold gesture (pure, tested)
KaiActions/       Approved actions, morning cards, reply drafting, writing style
Kai OS macOS/     The app target
  App/              Entry point, AppState, assistant tools, app awareness
  Views/            SwiftUI views and settings
  KaiMagic/         Notch window, notch view, Right Command hotkey
  KaiDoubleTap/     Double Tap reply drafting
  KaiProactive/     Placeholder
KaiKnowledge/     Local search index (SQLite FTS5) and the indexers that fill it
KaiAgent/         Computer-use agent: actions, rules, loop, log (no AppKit, fully tested with fakes)
KaiSlack/         Read-only Slack client, message formatting and the Slack indexer
KaiDesk/          Clipboard history, Shelf, Claude Code hook events, tracker and local socket
KaiHook/          The kai-hook command that Claude Code hooks run
Tests/KaiChecksTests/    122 checks, run with `swift test`
```

## Libraries

| Module | What it does |
|--------|--------------|
| `KaiShared` | `KaiChatService` picks the active client. `OpenAIChatClient` and `AnthropicChatClient` stream chat. `KaiKeychain` stores API keys in the Keychain and migrates any legacy plaintext key out of UserDefaults. |
| `KaiLocalAI` | `KaiOllamaClient` streams chat and lists models over HTTP. |
| `KaiLocalData` | Read-only access to Apple Calendar (EventKit), Mail and Notes (AppleScript), and Spotlight search (`mdfind`). |
| `KaiCapture` | Permission status and requests, screen capture, speech transcription, and writing text into other apps. |
| `KaiKnowledge` | `KaiKnowledgeStore` keeps documents and their chunks in one SQLite file (`~/Library/Application Support/Kai OS/knowledge.sqlite`, readable only by you) with an FTS5 index using Porter stemming. `KaiKnowledgeIndexer` fills it from a Markdown folder, Notes, Calendar and Mail subjects, skipping unchanged items. The assistant reaches it through the `search_knowledge` tool. |
| Night Shift | `KaiNightShiftSettings` (with the list of sources to include, `KaiNightShiftSource`), `KaiNightShiftPolicy`, `KaiNightShiftStore` and `KaiNightShiftAgent` (in `KaiShared`) hold the schedule, the power rules, the saved settings and last run, and the per-user launchd job (`~/Library/LaunchAgents/ai.kai.nightshift.plist`). `KaiNightShiftRunner` (in the app) does the run: index the knowledge base, generate today's briefing if there isn't one, record the outcome and quit. launchd starts the app with `--night-shift`, which hides it from the Dock and windows. |
| `KaiAgent` | The computer-use agent's brain, with no AppKit. `KaiAgentTools` defines and validates the six actions the model may ask for (click, type, key, scroll, wait, finish). `KaiAgentPolicy` decides allow, ask or refuse, from the action, the app in front and the mode, and nothing the model or the screen says can change it. `KaiAgentRunner` is the loop: screenshot, ask the model, check the policy, ask the person if needed, act, repeat, with step and time limits, an emergency stop, and a stop when the person uses their own mouse or keyboard. `KaiAgentAuditLog` records every event. |
| Sidekick (app) | `KaiSystemScreen` (screenshot without Kai's windows), `KaiSystemInput` (real mouse and keyboard events, tagged so the person's own input can be told apart), `KaiOllamaAgentBrain` (local model only), `KaiAgentController` and `KaiAgentOverlay` (the floating panel with Approve, Decline and Stop, left out of screenshots, and a ring where it clicks). The agent cannot act while Kai is in front and cannot click Kai's panel. |
| `KaiSlack` | `KaiSlackClient` calls only Slack's read methods (`auth.test`, `users.conversations`, `conversations.history`, `users.info`, `search.messages`) with a token from the Keychain, retries once after a rate limit, and turns Slack's error codes into plain messages. `KaiSlackText` turns Slack markup into text and groups a channel's day into one knowledge document. `KaiSlackIndexer` keeps the knowledge base up to date, and leaves out direct messages unless they are turned on. In the app, `search_slack` and `read_slack_screen` are assistant tools, and `KaiSlackScreenReader` reads the running Slack window through Accessibility (never the message box). |
| `KaiDesk` | `KaiClipboardHistory` keeps the last 50 text copies and decides what is never recorded (password managers, terminals, dictation, secret-marked copies). `KaiShelf` holds files (by path), links and text, with a 5 second undo after a drag-out. `KaiHookEvent` reads only a few fields of a Claude Code hook, `KaiHookTracker` follows turns and helper agents, and `KaiHookServer` / `KaiHookClient` talk over a private Unix socket (0600 in a 0700 folder, same-user peer check). `KaiHookSetup` builds the text you paste into your Claude settings. In the app, `KaiDeskController` watches the pasteboard (only when turned on), runs the socket (only when turned on), and drives the notch tabs and the approval card. |
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

## Removed scaffolding

`KaiEngine` (on-device inference, fallback chain, PII scan) and `KaiIngestion` (a connector protocol with unused REST connectors) were deleted on 2026-11-07. Nothing used them: local chat goes through Ollama in `KaiLocalAI` and cloud chat through `KaiShared`. They are in git history (`1a91b08` and earlier) and the plan describes what is still wanted.

## Privacy model

- Local chat sends nothing off the Mac.
- Cloud chat is opt-in. Your messages go to OpenAI or Anthropic with your own key. API keys are stored in the Keychain.
- Mail, Calendar and Notes are read through macOS permissions that you grant.
- Nothing is sent or created without an approval card, and Kai never sends mail.
- No telemetry.

## Testing

`swift test` runs `Tests/KaiChecksTests`. See [BUILD.md](BUILD.md).
