# Kai OS

**A personal AI for your Mac, in the notch.** Chat with a local model, ask about your calendar, mail and notes, and approve small actions Kai proposes. Nothing is sent or created until you approve it.

**macOS 14+ · Apple Silicon · Early development**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![License: CC-BY-4.0](https://img.shields.io/badge/Docs-CC--BY--4.0-0088ff.svg)](LICENSING.md)
[![Platform: macOS 14+](https://img.shields.io/badge/macOS-14%2B-silver.svg)](BUILD.md)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](BUILD.md)

> **Status:** early development. The features below work. Everything under
> [Planned](#planned) does not exist yet. The Xcode project is out of date: build with SwiftPM (see [BUILD.md](BUILD.md)).

---

## What works today

- **Chat in the notch.** Local chat through [Ollama](https://ollama.com) (`localhost:11434`), or ChatGPT and Claude with your own API key. Keys are stored in the macOS Keychain.
- **Ask about your Mac.** The assistant can read your Apple Calendar, Apple Mail and Apple Notes (read-only) and search files with Spotlight.
- **Approved actions only.** Kai can propose a calendar event, a mail draft or a notification. You see a card and decide. Kai never sends mail and never runs shell commands.
- **Double Tap.** In Apple Mail, Kai drafts a reply with the local model, from the selected message or a screenshot. It writes the draft into the email and never sends it. Your writing style can be learned from your sent mail, on request.
- **Morning "For You" cards.** While the app is open, from 7 am, Kai prepares suggested actions as cards.
- **Voice and screen.** Hold-to-talk with on-device speech recognition, and user-triggered screen capture sent to a vision model.
- **App awareness.** The UI adapts to the frontmost app.

## Planned

Not built yet: knowledge base (RAG, vector store, knowledge graph), computer-use agent, overnight Night Shift and wake-from-sleep, Gmail, Slack, Notion, WhatsApp and iMessage connectors, Outlook and Google Calendar in the app, on-device engine (LiteRT, Gemma), plugin system, Homebrew cask. See [KAI-DEVELOPMENT-PLAN.md](KAI-DEVELOPMENT-PLAN.md).

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
