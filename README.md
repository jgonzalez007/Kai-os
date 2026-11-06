# Kai OS

**An on-device personal AI for your Mac.** It understands the context of your life and work overnight, so you can hand off a task, draft the right reply in two taps, or wake up to useful work already prepared for your approval.

On-device understanding. Your choice of AI. Knowledge you own.

**macOS · Apple Silicon · Always Private**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![License: CC-BY-4.0](https://img.shields.io/badge/Docs-CC--BY--4.0-0088ff.svg)](LICENSING.md)
[![Platform: macOS 15+](https://img.shields.io/badge/macOS-15.4%2B-silver.svg)](ARCHITECTURE.md)
[![Chip: Apple Silicon](https://img.shields.io/badge/Chip-M1%2B-30d158.svg)](ARCHITECTURE.md)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](BUILD.md)
[![Package: Homebrew](https://img.shields.io/badge/install-brew%20install%20--cask-kai--os-brightgreen.svg)](BUILD.md)
[![Status: v1.0.0](https://img.shields.io/badge/version-1.0.0-6366f1.svg)](ARCHITECTURE.md)

---

## Features

- **Kai Sidekick** — Computer-use agent with its own cursor. Click the notch, give it a task. It works in your real apps, your real browser, your logged-in accounts.
- **Kai Double Tap** — Put your cursor in a reply box, double-tap the key. Kai drafts a reply in your voice from your knowledge. Unsent until you send.
- **Kai Proactive** — Overnight, Kai reads what's new, prepares suggestions. Morning: review cards, tap to fire. You decide; Kai prepares.
- **Kai Engine** — On-device inference via Gemma 4 / Qwen / your own model. Metal GPU. Speculative decoding. Zero cloud required.
- **Kai Knowledge Base** — A folder of Markdown files on your Mac. RAG + knowledge graph + vector embeddings. You own the files.
- **Connectors** — Apple Mail, Apple Calendar, WhatsApp, iMessage, Notes, Gmail, Outlook, Slack, Notion, SiYuan. All optional.
- **Night Shift** — Wakes a sleeping, lid-shut Mac at 3 AM, runs local inference, returns to sleep.

---

## Quick Install

```bash
brew install --cask kai-os/tap/kai-os
```

## Build from Source

```bash
cd kai-os
xcodebuild -project "Kai OS.xcodeproj" -scheme "Kai OS" build
```

Requires: macOS 15.4+ · Apple Silicon M1+ · 8 GB RAM · Xcode 15+

## Architecture

| Module | Purpose |
|--------|---------|
| `KaiEngine` | On-device inference (LiteRT-LM, Gemma 4, Metal GPU) |
| `KaiIngestion` | Data connectors, batch processing, SQLite pools |
| `KaiVault` | Knowledge base: RAG, vector store, knowledge graph |
| `KaiProactive` | Overnight analysis, morning suggestion cards |
| `KaiDriver` | Computer-use automation, multi-step planner |
| `KaiDoubleTap` | Smart reply in your voice, two taps |
| `KaiMagic` | Dynamic Island UI, Sidekick interface |
| `KaiCloud` | Hosted AI (ChatGPT, Claude, OpenRouter), MCP relay |
| `Views` | SwiftUI app shell, settings, onboarding, processing |
| `KaiScheduling` | Night Shift scheduler, wake helper, login item |
| `KaiConnectors` | Direct MCP server, identity, auth |

For full details, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Privacy

- All on-device processing stays on your Mac
- Knowledge base = plain Markdown folder at `~/Kai OS - Knowledge Base/`
- Hosted AI uses YOUR account keys, not ours
- No telemetry. No tracking. No accounts required.
- AES-256-GCM encryption for cloud sync (opt-in)

## Getting Help

- [ARCHITECTURE.md](ARCHITECTURE.md) — Module map, data flow, privacy model
- [BUILD.md](BUILD.md) — Build instructions, requirements, troubleshooting
- [MIGRATION.md](MIGRATION.md) — Upgrading from sentient-os
- [CONTRIBUTING.md](CONTRIBUTING.md) — How to contribute
- [LICENSING.md](LICENSING.md) — License terms

## License

- **Code:** [MIT](LICENSE)
- **Documentation:** [CC-BY-4.0](LICENSING.md)
- **Trademark:** "Kai OS" and the Kai logo are trademarks of Kai OS Labs

---

© 2026 Kai OS Labs. All rights reserved.
