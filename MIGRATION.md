# Migration Guide: sentient-os → Kai OS

> For users and developers upgrading from the original sentient-os.

## What Changed

### Rebranding
- **Name:** "Sentient OS" → "Kai OS"
- **Bundle ID:** `jesai.Sentient-OS-macOS` → `ai.kai`
- **All modules:** `Engine/`, `Vault/`, `Proactive/`, etc. → `KaiEngine/`, `KaiVault/`, `KaiProactive/`
- **All classes:** `SentientOSApp` → `KaiOSApp`, `LocalFallbackManager` → `KaiFallbackManager`

### New Features
- **App Awareness:** Kai detects the frontmost app and adapts suggestions (Mail → drafts, Safari → web actions)
- **ProactiveFire:** Real NSUserNotification, calendar invites, email replies, computer actions
- **DoubleTap Fallback:** Local model support via Ollama, LM Studio, llama.cpp
- **Spotlight Indexing:** Real mdfind and system_profiler for on-device research
- **Enhanced Connectors:** Google Calendar, Outlook Calendar with OAuth2

### What Stayed the Same
- Knowledge base at `~/Kai OS - Knowledge Base/`
- All connector integrations (Mail, Calendar, Gmail, WhatsApp, iMessage, Notes, etc.)
- On-device inference architecture (Gemma 4, Qwen)
- Night Shift scheduler
- Double Tap reply system
- Computer-use agent (Sidekick)
- Privacy-first approach (no cloud telemetry)

## How to Upgrade

1. **Install Kai OS** alongside or instead of sentient-os
2. **Copy your knowledge base:**
   ```bash
   cp -r "~/Sentient OS - Knowledge Base/" "~/Kai OS - Knowledge Base/"
   ```
3. **Reconnect your data sources** in Settings
4. **Your Claude/OpenAI keys** work the same — they're stored locally

## Breaking Changes

| Old | New |
|-----|-----|
| `SentientOSApp` | `KaiOSApp` |
| `jesai.Sentient-OS-macOS` bundle | `ai.kai` |
| `Engine/` module | `KaiEngine/` |
| `Vault/` module | `KaiVault/` |
| `Proactive/` module | `KaiProactive/` |
| `Driver/` module | `KaiDriver/` |
| `DoubleTap/` module | `KaiDoubleTap/` |
| `NotchMagic/` module | `KaiMagic/` |
| `Cloud/` module | `KaiCloud/` |
| `Scheduling/` module | `KaiScheduling/` |

## For Developers

### Building
```bash
cd kai-os
swift build
```

### Package Naming
All public classes use `Kai*` prefix:
```swift
// Old
class SentientOSApp { }
class LocalFallbackManager { }

// New  
class KaiOSApp { }
class KaiFallbackManager { }
```

### Configuration
- UserDefaults key: `ai.kai.*`
- Bundle identifier: `ai.kai`
- LaunchAgent: `ai.kai.wakehelper`

## License

Same as before: MIT for code, CC-BY-4.0 for documentation.

---

Questions? See [CONTRIBUTING.md](CONTRIBUTING.md) or open an issue.
