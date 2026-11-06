# Kai OS — Architecture

> On-device personal AI for macOS.  
> Author: Jose Gonzalez  
> Bundle: `ai.kai` | Version: 1.0.0

---

## Module Map

```
Kai OS macOS/
├── App/                          # @main app shell, navigation, windows
│   ├── KaiOSApp.swift            # Application entry point
│   ├── KaiAppState.swift         # App lifecycle state
│   ├── KaiHomeWindowOpening.swift
│   ├── KaiMainWindowCloseGuard.swift
│   ├── KaiPersonalSetupProgress.swift
│   ├── KaiMainNavigation.swift
│   ├── KaiDockPolicy.swift
│   ├── KaiLaunchPresentation.swift
│   └── KaiAppAwareness.swift     # NEW: frontmost app detection
├── KaiEngine/                    # On-device inference
│   ├── KaiEngine.swift           # Core inference (Metal GPU, speculative decoding)
│   ├── KaiFallback.swift         # Fallback chain: ChatGPT → Claude → Custom → Gemma
│   ├── ModelLocator.swift        # Find models on disk
│   ├── ModelDownload.swift       # Download models on demand
│   ├── PIIScan.swift             # Strip PII before inference
│   ├── SpeculativeDecoding.swift # Multi-token prediction
│   └── Triage.swift              # Output summarization
├── KaiIngestion/                 # Data connectors
│   ├── Connector.swift           # Connector protocol + factory
│   ├── BatchScheduler.swift      # Overnight batch runner
│   ├── IterativeRun.swift        # Pointer-based incremental processing
│   ├── ProcessingCoordinator.swift
│   ├── SQLitePool.swift          # SQLite-backed knowledge store
│   ├── CycleStore.swift          # Persistent cycle/pointer store
│   └── Connectors/               # Per-source connectors
│       ├── AppleMailConnector.swift
│       ├── AppleCalendarConnector.swift
│       ├── GmailConnector.swift
│       ├── GoogleCalendarConnector.swift
│       ├── OutlookCalendarConnector.swift
│       ├── NotesConnector.swift
│       ├── FilesConnector.swift
│       ├── ChatConnectors.swift  # WhatsApp, iMessage, Slack
│       └── SiYuanConnector.swift
├── KaiVault/                     # Knowledge base
│   ├── VectorStore.swift         # CoreML vector embeddings
│   ├── RAGEngine.swift           # Retrieval-augmented generation
│   ├── KnowledgeGraph.swift      # Entity/relation storage
│   ├── VaultGenerator.swift      # Knowledge from analysis
│   ├── BidirectionalSync.swift   # Local↔Cloud AES-256-GCM
│   ├── KnowledgeVersioning.swift
│   ├── SelectiveKnowledge.swift
│   ├── CrossReferenceEngine.swift
│   └── PrivacyControls.swift
├── KaiProactive/                 # Proactive intelligence
│   ├── KaiProactiveExecutorOverhaul.swift
│   ├── KaiProactiveScheduling.swift
│   └── VaultMergeCheckpoint.swift
├── KaiDriver/                    # Computer-use automation
│   ├── ComputerUseSandbox.swift
│   ├── MultiStepPlanner.swift
│   ├── TaskStateMachine.swift
│   ├── ComputerUseSafety.swift
│   ├── SessionReplay.swift
│   ├── CuaDriver.swift
│   └── NativeComputerUseServer.swift
├── KaiDoubleTap/                 # Smart reply
│   ├── DoubleTap.swift
│   ├── DoubleTapInference.swift
│   ├── DoubleTapKnowledge.swift
│   ├── CaretLocator.swift
│   └── CaretSwirl.swift
├── KaiMagic/                     # Dynamic Island UI
│   ├── NotchShape.swift
│   ├── SidekickConversation.swift
│   ├── SidekickToolServer.swift
│   ├── SidekickInteraction.swift
│   ├── MicrophoneEngine.swift
│   ├── ScreenCapture.swift
│   ├── SidekickHotkeyMonitor.swift
│   └── NotchWindowController.swift
├── KaiCloud/                     # Hosted AI
│   ├── ClaudeCLI.swift
│   ├── ChatGPTRecovery.swift
│   ├── FrontierRun.swift
│   ├── MirrorClient.swift
│   ├── LocalMCPServer.swift
│   └── Hosted/
│       ├── KaiHostedConnectorClient.swift
│       ├── KaiHostedConnectorModels.swift
│       ├── KaiHostedConnectorToolServer.swift
│       └── KaiHostedConnectorAuth.swift
├── Views/                        # SwiftUI interfaces
│   ├── HomeView.swift            # Main home, proactive cards
│   ├── RootView.swift            # App shell
│   ├── ProcessingView.swift      # Overnight analysis
│   ├── Sidekick/
│   ├── Settings/
│   ├── Onboarding/
│   ├── Knowledge/
│   └── Dev/
├── KaiScheduling/                # Night Shift scheduler
│   ├── OvernightScheduler.swift
│   ├── WakeHelper.swift
│   ├── PowerState.swift
│   ├── LoginItem.swift
│   └── Shortcuts/
├── KaiConnectors/                # Direct MCP
│   ├── DirectMCPStore.swift
│   ├── DirectMCPRuntime.swift
│   └── DirectMCPSession.swift
├── KaiSources/                   # Data sources
├── KaiUpdates/                   # App updates
├── KaiDiagonstics/               # Diagnostics (spelling intentional)
├── Tests/                        # Test suite (40+ tests)
└── Assets.xcassets/              # App icons, marks
```

---

## Module Details

### KaiEngine
On-device inference core. Wraps LiteRT-LM for Gemma 4 E4B and ONNX Runtime for Qwen.
- **Metal GPU** acceleration via Metal Performance Shaders
- **Speculative decoding** for 2-3x throughput on Apple Silicon
- **PIIScan** strips PII before any inference call
- **KaiFallback** chain: ChatGPT (hosted) → Claude (hosted) → Custom model → Gemma 4 (local)

### KaiIngestion
Data connectors for understanding your life.
- **Connector protocol** with factory pattern for extensible sources
- **BatchScheduler** runs overnight ingestion while Mac sleeps
- **SQLitePool** for persistent knowledge storage
- 10 connectors: Mail, Calendar, Gmail, Outlook, Notes, Files, WhatsApp, iMessage, Slack, Notion, SiYuan

### KaiVault
Knowledge base as plain Markdown files.
- **Vector Store** with CoreML embeddings for semantic search
- **RAG Engine** for retrieval-augmented generation
- **Knowledge Graph** for entity/relation storage
- **Bidirectional Sync** with AES-256-GCM encryption (opt-in)
- All data stored as `.md` files — you own them

### KaiProactive
Overnight intelligence that prepares morning cards.
- **KaiActions** (top-level target) runs user-approved calendar events, mail drafts and notifications
- **KaiProactiveResearch** performs Spotlight searches via `mdfind`
- Time-aware suggestions based on calendar and context
- **Audit Trail** logs all actions for transparency

### KaiDriver
Computer-use automation with safety boundaries.
- **CuaDriver** implements macOS Computer Use Automation API
- **Sandbox** with permission boundaries and kill switches
- **MultiStepPlanner** decomposes complex tasks into sub-steps
- **SessionReplay** records Sidekick actions for audit

### KaiDoubleTap
Two-tap smart reply in your voice.
- Detects your cursor position (CaretLocator)
- Uses your writing style from `writingstyle.md`
- Local model fallback: Ollama, LM Studio, llama.cpp
- Draft preview — unsent until you send

### KaiMagic
Dynamic Island-style notch UI.
- **NotchShape** — Dynamic Island silhouette overlay
- **SidekickConversation** — Chat interface in the notch
- **MicrophoneEngine** — Voice input (Speech-to-text)
- **ScreenCapture** — Live screen feed for context
- **HotkeyMonitor** — Global hotkey (right ⌘)

### KaiCloud
Hosted AI integration (your account, your keys).
- **ChatGPT** via OpenAI API
- **Claude** via Anthropic API
- **Frontier** models for cutting-edge inference
- **MirrorClient** for cloud sync relay
- **LocalMCPServer** for third-party AI connections

---

## Data Flow

```
┌─────────────────────────────────────────────────┐
│  Ingestion (Mail, Calendar, Notes, Files, etc.) │
│       ↓ SQLitePool (persistent store)           │
│  Vault (Vector Store + Knowledge Graph)          │
│       ↓ Overnight analysis                      │
│  Proactive (Morning cards, research)             │
│       ↓                                           │
│  App (Home, Sidekick, Settings)                  │
│       ↓                                           │
│  Driver (Computer-use, DoubleTap)                │
└─────────────────────────────────────────────────┘
         ↕
    YOUR KEYS (ChatGPT, Claude)
         ↕
    Cloud (optional)
```

---

## Privacy Model

| Layer | What It Does |
|-------|-------------|
| **On-device inference** | Gemma 4 / Qwen run locally, no network |
| **Knowledge base** | Plain `.md` files, you control them |
| **Hosted AI** | YOUR API keys, YOUR accounts |
| **Cloud sync** | Opt-in, AES-256-GCM encrypted |
| **Telemetry** | Zero. No tracking. No accounts required. |

---

## Requirements

- macOS 15.4+ (Sequoia)
- Apple Silicon M1+
- 8 GB RAM minimum (16 GB recommended)
- Xcode 15+
- Swift 5.9+

---

## Build

```bash
cd kai-os
xcodebuild -project "Kai OS.xcodeproj" \
  -scheme "Kai OS" \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  build
```

## License

- **Code:** MIT
- **Documentation:** CC-BY-4.0
- **Trademark:** Kai OS Labs
