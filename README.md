# Kai OS

**A personal AI for your Mac, in the notch.** Chat with a local model, ask about your calendar, mail and notes, and approve small actions Kai proposes. Nothing is sent or created until you approve it.

**macOS 14+ · Apple Silicon · Early development**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![License: CC-BY-4.0](https://img.shields.io/badge/Docs-CC--BY--4.0-0088ff.svg)](LICENSING.md)
[![Platform: macOS 14+](https://img.shields.io/badge/macOS-14%2B-silver.svg)](BUILD.md)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](BUILD.md)

> **Status:** early development. The features below work. Everything under
> [Planned](#planned) does not exist yet. There is no Xcode project: build with SwiftPM or open `Package.swift` in Xcode (see [BUILD.md](BUILD.md)).

---

## What works today

- **Chat in the notch.** Local chat through [Ollama](https://ollama.com) (`localhost:11434`), or ChatGPT and Claude with your own API key. Keys are stored in the macOS Keychain.
- **Ask about your Mac.** The assistant can read your Apple Calendar, Apple Mail and Apple Notes (read-only) and search files with Spotlight.
- **Approved actions only.** Kai can propose a calendar event, a mail draft or a notification. You see a card and decide. Kai never sends mail and never runs shell commands.
- **Double Tap.** In Apple Mail, Kai drafts a reply with the local model, from the selected message or a screenshot. It writes the draft into the email and never sends it. Your writing style can be learned from your sent mail, on request.
- **Morning "For You" cards.** While the app is open, from 7 am, Kai prepares suggested actions as cards.
- **Voice and screen.** Hold-to-talk with on-device speech recognition, and user-triggered screen capture sent to a vision model.
- **App awareness.** The UI adapts to the frontmost app.
- **Knowledge base.** Kai indexes the Markdown and text files in `~/Kai OS - Knowledge Base/`, plus your Notes, Calendar events and Mail subjects for the sources you connect, and the assistant can search it. Everything stays in a private SQLite file on this Mac. Mail bodies are never indexed. Index it from Settings → Knowledge base.
- **Night Shift.** Turn it on in Settings and Kai OS starts in the background at a time you pick, updates the knowledge base, prepares the morning cards, and quits. You choose what it includes in Settings → Night Shift: the knowledge folder, Calendar, Notes, Mail, Slack, and the morning cards. Mail is off until you turn it on, because reading it is slow on a big mailbox. The same list decides what "Index now" and the 7 am morning cards read. It only prepares cards: nothing is sent or changed without your approval. It skips the run in Low Power Mode, when the Mac is hot, or on a low battery. It does not wake a sleeping Mac; if the Mac is asleep at that time the job runs when it wakes. Needs the installed app (`scripts/install-app.sh`).
- **Sidekick (computer use).** Describe a task and Kai does it in your other apps by looking at the screen and using the mouse and keyboard, with a ring where it clicks. By default every action waits for your Approve; "Run on its own" still asks before Return, Delete, quitting and similar. Esc, the Stop button, or touching your own mouse or keyboard stops it. It never works in Terminal, System Settings or password managers, and it uses a local model only, so screenshots never leave this Mac. Needs Accessibility and Screen Recording permission. **New and not yet tried on a real screen: start with simple tasks and stay at the keyboard.**
- **Slack (read-only).** Two ways. With a token you create for your own Slack app, Kai can summarize recent Slack by date ("what happened in Slack yesterday?"), search it for specific words, and index recent channel messages into the knowledge base (direct messages are off unless you turn them on). Without any token, Kai can read the Slack window that is open on this Mac when you ask, for example "summarize this channel". Neither can post, edit or delete anything. The screen reader needs Accessibility permission and is new and unproven against Slack's real window. Setup is in [BUILD.md](BUILD.md#slack-setup).
- **Mailbox access (optional, off by default).** In Settings you can let Kai search any mailbox and read a message, or also propose moving messages or marking them read. Every change is a card showing how many messages and examples, and nothing happens until you press Approve. Kai never sends mail, never deletes permanently, and never touches more than 500 messages per approval. **It only works on mailboxes under 5,000 messages:** Apple Mail's scripting is too slow on bigger ones, and Kai refuses rather than freeze Mail. Not yet verified against a real mailbox.
- **Health page.** One screen that shows whether the local model, cloud keys, permissions, sources and the morning briefing are working, and what to do if not.

## Planned

Not built yet: embeddings and a knowledge graph on top of the knowledge base (search is keyword-based, with stemming), waking a sleeping Mac for Night Shift, Gmail, Notion, WhatsApp and iMessage connectors, Outlook and Google Calendar in the app, on-device engine (LiteRT, Gemma), plugin system, Homebrew cask. See [KAI-DEVELOPMENT-PLAN.md](KAI-DEVELOPMENT-PLAN.md).

## Build from source

```bash
git clone https://github.com/jgonzalez007/Kai-os
cd Kai-os
swift build
swift test
```

Requires macOS 14+, Apple Silicon and Xcode (the Command Line Tools alone cannot run the tests). For local chat, install and start Ollama and pull a model.

## Privacy

- Local chat stays on your Mac.
- If you turn on ChatGPT or Claude, your messages go to that provider with your key. Kai has no servers and no telemetry.
- API keys live in the Keychain, readable only while the Mac is unlocked.
- Calendar, Mail and Notes access uses macOS permissions that you grant and can revoke.

## Docs

- [ARCHITECTURE.md](ARCHITECTURE.md): what the code contains
- [BUILD.md](BUILD.md): build, test, requirements
- [KAI-DEVELOPMENT-PLAN.md](KAI-DEVELOPMENT-PLAN.md): roadmap and status
- [MIGRATION.md](MIGRATION.md): coming from sentient-os
- [CONTRIBUTING.md](CONTRIBUTING.md) · [LICENSING.md](LICENSING.md)

## License

- **Code:** [MIT](LICENSE)
- **Documentation:** [CC-BY-4.0](LICENSING.md)
- **Trademark:** "Kai OS" and the Kai logo are trademarks of Kai OS Labs

© 2026 Kai OS Labs.
