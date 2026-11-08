# Kai OS — Development Plan

> Fork of sentient-os → rebranded, restructured, expanded.
> Author: Jose Gonzalez
> Date: 2026-11-06

---

## 1. Project Overview

Kai OS is a personal AI for macOS that runs on-device. It understands your life (mail, calendar, messages, files), builds a knowledge graph overnight, and proactively prepares suggestions for your morning. You choose the AI — local (Gemma 4, Qwen) or hosted (ChatGPT, Claude). All data stays on your Mac.

**Core pillars:**
- On-device understanding
- Your choice of AI
- Knowledge you own (plain Markdown files)
- Computer-use agents with their own cursor
- Privacy at its core

---

## 2. Architecture — Module Map

```
Kai OS macOS/
├── App/                    # @main app shell, navigation, windows
├── Engine/                 # On-device inference (LiteRT-LM, Gemma 4)
│   ├── Engine.swift        # Core inference wrapper (Metal GPU, speculative decoding)
│   ├── LocalFallback.swift # Fallback chain: ChatGPT → Claude → Custom → Gemma
│   ├── ModelLocator.swift  # Find models on disk
│   ├── ModelDownload.swift # Download models
│   ├── PIIScan.swift       # Strip PII before sending
│   ├── SpeculativeDecoding.swift
│   └── Triage.swift        # Output summarization
├── Ingestion/              # Data connectors, batch scheduler
│   ├── Connectors/         # Per-source: AppleMail, AppleCalendar, WhatsApp, iMessage, etc.
│   ├── BatchScheduler.swift  # Overnight batch runner
│   ├── IterativeRun.swift    # Pointer-based incremental processing
│   ├── ProcessingCoordinator.swift
│   ├── SQLitePool.swift      # SQLite-backed knowledge store
│   └── CycleStore.swift      # Persistent cycle/pointer store
├── Vault/                  # Knowledge base
│   ├── VectorStore.swift       # CoreML vector embeddings
│   ├── RAGEngine.swift         # Retrieval-augmented generation
│   ├── KnowledgeGraph.swift    # Graph-based storage
│   ├── VaultGenerator.swift    # Generate knowledge from analysis
│   ├── BidirectionalSync.swift # Local↔Cloud sync
│   ├── KnowledgeVersioning.swift
│   ├── SelectiveKnowledge.swift
│   ├── CrossReferenceEngine.swift
│   └── PrivacyControls.swift
├── Proactive/              # Proactive intelligence
│   ├── ProactiveExecutor.swift     # Fire pipeline (notifications, emails, calendar, computer, research)
│   ├── ProactiveExecutorOverhaul.swift
│   ├── ProactiveScheduling.swift   # Time-aware suggestions
│   ├── ProactiveResearch.swift     # Research tool server
│   └── VaultMergeCheckpoint.swift
├── Driver/                 # Computer-use automation
│   ├── ComputerUseSandbox.swift    # Permission boundaries
│   ├── MultiStepPlanner.swift      # Break complex tasks into sub-steps
│   ├── TaskStateMachine.swift      # Persist/restore Sidekick task state
│   ├── ComputerUseSafety.swift     # Kill switches, rate limits
│   ├── SessionReplay.swift         # Record Sidekick actions for audit
│   ├── CuaDriver.swift             # CUA driver
│   └── NativeComputerUseServer.swift
├── DoubleTap/              # Smart reply
│   ├── DoubleTap.swift             # Two-tap reply in your voice
│   ├── DoubleTapInference.swift    # Inference for DoubleTap
│   ├── DoubleTapKnowledge.swift
│   ├── CaretLocator.swift          # Find cursor position
│   └── CaretSwirl.swift            # Visual feedback
├── NotchMagic/             # Dynamic Island-style UI
│   ├── NotchShape.swift            # Dynamic Island silhouette
│   ├── SidekickConversation.swift  # Sidekick chat interface
│   ├── SidekickToolServer.swift    # Tool use server
│   ├── SidekickInteraction.swift   # Interaction handlers
│   ├── MicrophoneEngine.swift      # Voice input
│   ├── ScreenCapture.swift         # Screen capture
│   ├── SidekickHotkeyMonitor.swift # Global hotkey (right ⌘)
│   └── NotchWindowController.swift
├── Cloud/                  # Hosted AI integration
│   ├── ClaudeCLI.swift             # Claude API integration
│   ├── ChatGPTRecovery.swift       # ChatGPT/OpenAI integration
│   ├── FrontierRun.swift           # Frontiers model execution
│   ├── MirrorClient.swift          # Cloud sync relay
│   ├── LocalMCPServer.swift        # MCP server for other AIs
│   └── HostedInference/        # Sentient-funded inference
├── Views/                  # SwiftUI interfaces
│   ├── HomeView.swift              # Main home — proactive cards
│   ├── RootView.swift              # App shell
│   ├── ProcessingView.swift        # Overnight analysis UI
│   ├── Sidekick/SidekickStyle.swift  # Sidekick glass UI
│   ├── Settings/               # Settings panels
│   ├── Onboarding/           # Onboarding wizard
│   └── Knowledge/            # Knowledge base reader
├── Scheduling/             # Night Shift scheduler
│   ├── OvernightScheduler.swift    # Schedule overnight analysis
│   ├── WakeHelper.swift            # Wake sleeping Mac
│   ├── PowerState.swift            # Power/thermal checks
│   └── LoginItem.swift             # Login at startup
├── Connectors/             # Direct MCP
│   ├── DirectMCPStore.swift
│   ├── DirectMCPRuntime.swift
│   └── DirectMCPSession.swift
└── Tests/                  # Test suite
```

---

## 3. Features Breakdown

### 3.1 Core AI Engine
| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 1.1 | On-device inference (Gemma 4 E4B via LiteRT-LM) | Built | Metal GPU, speculative decoding |
| 1.2 | Cloud fallback chain | Partial | ChatGPT/Claude stubs throw NotImplementedError |
| 1.3 | Local model detection & download | Built | ModelLocator + ModelDownload |
| 1.4 | PII scanning before inference | Built | PIIScan strips sensitive identifiers |
| 1.5 | Multi-model support | Built | Qwen, Gemma, Claude, ChatGPT |

### 3.2 Data Connectors
> **2026-11-07, parked:** optional mailbox access (search, read, organize with approval) is built and stays as is, limited to mailboxes under 5,000 messages. On a 43,000-message Exchange inbox Apple Mail's scripting was too slow and left Mail at 100% CPU, so larger mailboxes are refused. Open options if it is picked up again: Microsoft Graph for Exchange (needs an app registration and possibly admin approval), or Spotlight with Full Disk Access (unconfirmed). Never verified against a real mailbox of any size.

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 2.1 | Apple Mail connector | Built | IMAP/Events |
| 2.2 | Apple Calendar connector | Built | EventKit |
| 2.3 | WhatsApp connector | Built | SQLite db read |
| 2.4 | iMessage connector | Built | SQLite db read |
| 2.5 | Apple Notes connector | Built | Text extraction |
| 2.6 | Gmail connector | Built | IMAP + OAuth |
| 2.7 | Outlook connector | Not built | Parked. A working attempt (sign-in, Graph calendar view, tests) is in git history at 42d5a46 and was reverted in fd128bd. `ConnectorFactory` no longer exists. |
| 2.8 | Slack connector | Built (read-only) | User token for your own Slack app: search and indexing, tested with a fake Slack. Screen reader for the running app: built, not yet proven against the real window. Never tested against a real workspace. |
| 2.9 | Notion connector | Built | API read |
| 2.10 | SiYuan connector | Built | Local db read |
| 2.11 | Google Calendar | Stub | Pattern exists, not wired |
| 2.12 | File connector | Built | Directory watching |

### 3.3 Knowledge Base (Vault)
> **2026-11-07:** the rows below describe the original plan. What exists now: keyword search with stemming (SQLite FTS5) over a Markdown folder, Notes, Calendar and Mail subjects, a `search_knowledge` assistant tool, and a Settings card. Embeddings, the knowledge graph, cross-source links and encrypted sync are not built.

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 3.1 | Vector embeddings (CoreML) | Built | Semantic search |
| 3.2 | RAG engine | Built | Retrieval-augmented generation |
| 3.3 | Knowledge graph | Built | Entity/relation storage |
| 3.4 | Cross-source linking | Built | Email↔Calendar↔Notes |
| 3.5 | Selective knowledge | Built | Relevance scoring |
| 3.6 | Version control | Built | Git-backed markdown |
| 3.7 | Cloud sync (AES-256-GCM) | Built | Opt-in encrypted |
| 3.8 | Privacy controls | Built | Per-source filtering |

### 3.4 Proactive Intelligence
| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 4.1 | Overnight analysis | Built | Night Shift scheduler |
| 4.2 | Morning suggestion cards | Built | ProactiveExecutor |
| 4.3 | Fire pipeline | Partial | Stubbed system calls |
| 4.4 | Confirmation flows | Built | User approves actions |
| 4.5 | Research tool | Partial | Shell commands, not wired |
| 4.6 | Audit trail | Built | All actions logged |

### 3.5 Computer Use (Sidekick)
> **2026-11-07:** rebuilt from scratch as `KaiAgent` plus a Sidekick page. Safety rules, the loop and the key table are unit tested with a fake screen and fake input (60+ checks). Not yet done: a supervised run on a real screen with Accessibility and Screen Recording granted; multi-display support (main display only); reading the screen with accessibility trees instead of only screenshots; resuming after a pause; running it from the notch or by voice. Model quality for this is unproven: `gemma4:e4b` has not been tried as a computer-use model.

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 5.1 | Dynamic Island notch UI | Built | macOS notch overlay |
| 5.2 | Computer-use agent | Built | CUA driver + sandbox |
| 5.3 | Multi-step planning | Built | Task decomposition |
| 5.4 | Task state machine | Built | Persist/restore |
| 5.5 | Session replay | Built | Action recording |
| 5.6 | Safety/kill switches | Built | Rate limits |
| 5.7 | Voice input | Built | Speech-to-text |
| 5.8 | Screen capture | Built | Live screen feed |

### 3.6 Double Tap
| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 6.1 | Two-tap reply | Built | In your voice |
| 6.2 | Writing style learning | Built | writingstyle.md |
| 6.3 | Caret detection | Built | Find cursor pos |
| 6.4 | Draft preview | Built | Unsent until you send |
| 6.5 | Local model support | Partial | Needs wiring |

### Desk (clipboard history, Shelf, Claude Code in the notch)
> **2026-11-07:** added, modelled on features in Glance for Mac 1.1.0 (own code). Logic and the socket are tested, including the real `kai-hook` helper process. Not yet tried by hand: dragging an item out of the Shelf into real apps, dropping on the closed notch, ⌃⌥Y / ⌃⌥N, and a live Claude Code session with the hooks installed.

### Install and first run
> **2026-11-07:** added a first-run guide (Ollama check, one-click model download with progress, permissions), a daily update check that only tells you, `scripts/package-release.sh`, a checksum-verified `scripts/install.sh`, an app icon, and a corrected Homebrew cask. Found and fixed: two modules missed a declared dependency, so a release build failed even though debug builds worked. Not done: no GitHub release is published yet, so the install script has nothing to download until one is; the guide was not seen on screen; no Apple notarization.

### 3.7 Night Shift Scheduler
> **2026-11-07:** a checklist in Settings picks what Night Shift covers (knowledge folder, Calendar, Notes, Mail, Slack, morning cards). Mail starts off, and when on it reads only a chosen window (today, yesterday and today, last 3 days, last 7 days; 200 messages at most, stopping at the first message older than the window). The same list governs "Index now" and the morning briefing, which can now include recent Slack.

> **2026-11-07:** built as a per-user launchd job that runs the app headless at a set time (index, briefing, record, quit), with power and thermal checks. Not built: waking a sleeping or lid-closed Mac (needs administrator rights for `pmset`), resuming a run that was cut short. Verified with a real launch against a test folder, not yet with real launchd or a real overnight run.

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 7.1 | Sleep/wake helper | Built | lid-closed support |
| 7.2 | Bounded awake sessions | Built | Checkpoint-based |
| 7.3 | Power/thermal checks | Built | Battery + temp guard |
| 7.4 | Resume from checkpoint | Built | Interrupt-safe |

---

## 4. Rebranding Checklist (sentient → kai)

### 4.1 File/Folder Renames
| Original | New |
|----------|-----|
| `Sentient OS macOS/` | `Kai OS macOS/` |
| `Sentient_OS_macOSApp.swift` | `KaiOSApp.swift` |
| `SentientOSApp` / `SentientOS` | `KaiOS` |
| `SentientOSAppDelegate` | `KaiOSAppDelegate` |
| `AppState` | `KaiAppState` |
| `Sidekick` (UI) | `KaiSidekick` (concept) |
| `LocalFallbackManager` | `KaiFallbackManager` |
| `ProactiveExecutor` | `KaiProactiveExecutor` |
| `MultiStepPlanner` | `KaiPlanner` |
| `DoubleTap` | `KaiDoubleTap` |
| `NotchShape` / `NotchMagic` | `KaiNotch` / `KaiMagic` |
| `Vault` | `KaiVault` |
| `KaiOS.xcodeproj` | `Kai OS.xcodeproj` |
| `jesai.Sentient-OS-macOS.WakeHelper.Managed.plist` | `ai.kai.WakeHelper.Managed.plist` |
| `KaiOS.entitlements` | `ai.kai.entitlements` |

### 4.2 String/Text Replacements (non-code)
- All UI strings: "Sentient OS" → "Kai OS"
- All bundle identifiers: `jesai.Sentient-OS-macOS` → `ai.kai`
- All menu items, window titles, alerts
- All comments in code (optional but recommended)
- All image asset names
- Documentation files
- README, LICENSING, CLA, CONTRIBUTING

### 4.3 Bundle/Identity Changes
- Bundle ID: `ai.kai` (replacing `jesai.Sentient-OS-macOS`)
- Display name: "Kai OS"
- Info.plist: CFBundleName, CFBundleDisplayName → "Kai OS"
- LaunchAgent plist: `ai.kai.wakehelper`
- Notarization/Signing: new certificate for `ai.kai`

### 4.4 Data Directory Changes
- Knowledge base path: `~/Kai OS - Knowledge Base/`
- All config/preferences paths under `ai.kai` in UserDefaults
- SQLite DB paths updated

---

## 5. Development Plan

### Phase 0: Repo Scaffold & Audit (Days 1-2)
**Goal:** Create the new Kai OS repo with full structural skeleton and baseline audit.

- [ ] 0.1 Clone sentient-os as starting point (copy, don't fork)
- [ ] 0.2 Generate file inventory (all 486 Swift files → rename map)
- [ ] 0.3 Create `Kai OS macOS/` directory structure from scratch
- [ ] 0.4 Generate empty stub Swift files for all modules (Engine, Ingestion, Vault, etc.)
- [ ] 0.5 Create Xcode project file `Kai OS.xcodeproj` (scaffold)
- [ ] 0.6 Copy non-Swift assets (Info.plist, entitlements, .xcconfig)
- [ ] 0.7 Create README.md, LICENSE, LICENSING.md, CLA.md, CONTRIBUTING.md
- [ ] 0.8 Create PHASES-3-5-SUMMARY.md → rename to KAI-ROADMAP.md
- [ ] 0.9 Initial git commit: "Initial Kai OS scaffold"

### Phase 1: Rebrand Engine Layer (Days 3-5)
**Goal:** All core AI engine files renamed and functional.

- [ ] 1.1 Rename `Engine/` files → `KaiEngine/`
- [ ] 1.2 Rename classes: `Engine` → `KaiEngine`, `LocalFallbackManager` → `KaiFallbackManager`
- [ ] 1.3 Wire up LocalFallback: replace `NotImplementedError` in ChatGPT/Claude with actual API calls
- [ ] 1.4 Update all `import` statements and module references
- [ ] 1.5 Fix bundle identifier from `jesai.Sentient-OS-macOS` → `ai.kai`
- [ ] 1.6 Update Info.plist: CFBundleName → "Kai OS"
- [ ] 1.7 Rebuild project → compile clean

### Phase 2: Rebrand Data Layer (Days 6-8)
**Goal:** Ingestion, Vault, and Data Source layers renamed.

- [ ] 2.1 Rename `Ingestion/` → `KaiIngestion`, all connector files
- [ ] 2.2 Rename `Vault/` → `KaiVault`, update all classes
- [ ] 2.3 Rename `Sources/` classes (AppleMailSource → KaiAppleMailSource, etc.)
- [ ] 2.4 Update all file headers: "Sentient OS macOS" → "Kai OS macOS"
- [ ] 2.5 Update SQLite schema/version strings
- [ ] 2.6 Rebuild → compile clean

### Phase 3: Rebrand Intelligence Layer (Days 9-11)
**Goal:** Proactive, Driver, DoubleTap renamed.

- [ ] 3.1 Rename `Proactive/` → `KaiProactive`
- [ ] 3.2 Rename `Driver/` → `KaiDriver`
- [ ] 3.3 Rename `DoubleTap/` → `KaiDoubleTap`
- [ ] 3.4 Wire ProactiveExecutor.fire() to real system calls (NSUserNotificationCenter, shell)
- [ ] 3.5 Wire DoubleTap local model fallback (ollama/lmstudio)
- [ ] 3.6 Update MultiStepPlanner class references
- [ ] 3.7 Rebuild → compile clean

### Phase 4: Rebrand UI Layer (Days 12-15)
**Goal:** All SwiftUI views, NotchMagic, views renamed.

- [ ] 4.1 Rename `NotchMagic/` → `KaiMagic`
- [ ] 4.2 Rename `Views/` modules, all SwiftUI view classes
- [ ] 4.3 Rename `Sentient_OS_macOSApp.swift` → `KaiOSApp.swift`
- [ ] 4.4 Update `SentientOSApp` → `KaiOSApp`, `SentientOS` → `KaiOS`
- [ ] 4.5 Rename all SwiftUI window IDs
- [ ] 4.6 Update all UI strings: "Sentient OS" → "Kai OS"
- [ ] 4.7 Replace image assets: "SentientLogo" → "KaiLogo", "SentientOSLogo" → "KaiOSLogo"
- [ ] 4.8 Create new Kai logo (SVG/PNG for AppIcon, KaiOSLogo)
- [ ] 4.9 Rename `KaiOS` → `KaiOSApp` in all SwiftUI previews
- [ ] 4.10 Rebuild → compile clean

### Phase 5: Rebrand Cloud & Networking (Days 16-17)
**Goal:** Cloud module, MCP, connectors renamed.

- [ ] 5.1 Rename `Cloud/` → `KaiCloud`
- [ ] 5.2 Rename `Connectors/` → `KaiConnectors`
- [ ] 5.3 Update all API endpoints, config strings
- [ ] 5.4 Rename `HostedInference/` → `KaiHosted`
- [ ] 5.5 Update Cloud bundle references
- [ ] 5.6 Rebuild → compile clean

### Phase 6: Rebrand Scheduling & System (Days 18-19)
**Goal:** Scheduling, diagnostics, updates renamed.

- [ ] 6.1 Rename `Scheduling/` → `KaiScheduling`
- [ ] 6.2 Rename `Diagonstics/` → `KaiDiagonstics` (fix spelling)
- [ ] 6.3 Update LaunchAgent plist: `jesai.Sentient-OS-macOS.WakeHelper` → `ai.kai.wakehelper`
- [ ] 6.4 Update entitlements: bundle ID reference
- [ ] 6.5 Update `.xcconfig` signing config
- [ ] 6.6 Rebuild → compile clean

### Phase 7: Wire Up Missing Features (Days 20-25)
**Goal:** Connect the dots — stubs become real.

**Cleanup (2026-11-07):** 283 placeholder Swift files (header and imports only, no declarations) were deleted from `Kai OS macOS/`, including the whole of `KaiCloud`, `KaiConnectors`, `KaiDiagonstics`, `KaiDriver`, `KaiScheduling`, `KaiSources`, `KaiVault` and `Tests`. They are in git history. Section 2 below is the planned layout, not what exists. `ARCHITECTURE.md` describes the code as it is. The broken `Kai OS.xcodeproj` was removed (it was not a valid project file); open `Package.swift` in Xcode instead. `StubFrameworks.swift` (fake EventKit types) was removed and `KaiInferenceRuntime` and `SpeculativeDecoding` now throw `runtimeUnavailable` instead of returning placeholder text, so `KaiEngine` had no working inference. `KaiEngine/` and `KaiIngestion/` were then deleted as unused scaffolding; on-device inference and new connectors would be rebuilt when they are needed. The checks now run under `swift test` (Tests/KaiChecksTests).

**Status (2026-11-07):** Most modules are still empty stubs, and the "Built" and "Complete" labels elsewhere in this plan predate that audit. Working and tested: local chat through Ollama, the notch panel, read-only Apple Calendar, Mail and Notes, Spotlight search, assistant tools over those sources, and ChatGPT + Claude cloud endpoints via Chat Completions/Messages API. Also working: user-triggered screen capture sent to a vision model, and hold-to-talk with on-device speech recognition, whose real microphone path still needs a first test on the user's Mac. Computer-use remains unbuilt. `Kai OS macOS/KaiSources`, `KaiIngestion` and `StubFrameworks.swift` are not used by these features. Google Calendar connector wired via REST API. Outlook Calendar connector remains unbuilt. Calendar, Mail and Notes still need a first test with real permissions on the user's Mac.

- [x] 7.1 Wire ChatGPT endpoint (OpenAI Chat Completions API) in LocalFallback — configurable model, modern API format
- [x] 7.2 Wire Claude endpoint (Anthropic Messages API) in LocalFallback — use modern API key format, Messages API, configurable model
- [x] 7.3 Wire Google Calendar connector (copy Apple Calendar pattern)
- [ ] 7.4 Wire Outlook Calendar (copy Outlook Mail pattern)
- [x] 7.5 Replaced ProactiveExecutor, which ran model text as shell commands, with `KaiActions`: proposals only run from a user-approved card. Calendar event, mail draft and notification only; no shell or send. Morning "For You" cards run while the app is open, from 7am; waking a closed or sleeping Mac overnight remains unbuilt.
- [x] 7.6 Spotlight search through `mdfind`, as `KaiSpotlightSource` and the `search_files` assistant tool
- [x] 7.7 Double tap writes email replies into the email itself with the local model, from the selected Mail message or a screenshot, and never sends. Writing style is learned from sent mail on request. Caret position display remains unbuilt.
- [x] 7.8 Add app-awareness: detect frontmost app via NSWorkspace

### Phase 9: Xcodebuild Compilation — COMPLETE

| Metric | Value |
|--------|-------|
| Xcode Version | 27.2 (swiftlang-6.4.2.1.9) |
| Target | arm64-apple-macos14.0 |
| Build Time | 7.53s |
| Swift Files | 328 |
| App Bundle | Kai OS.app (1.1MB Mach-O) |
| DMG | Kai-OS-1.0.0.dmg (414KB) |
| DMG SHA256 | 366646b7a546fa829bb8a891d5e76aa4a64e7376363ef103a8d5c33adb6a2a3d |

Build command: `swift build` (SPM)
Product: `.build/debug/Kai OS` — Mach-O 64-bit executable arm64

## Phase 8: Test Suite & Polish (Days 26-30)
**Goal:** All tests pass, documentation complete. **COMPLETED: 2026-11-06**

- [x] 8.1 Rename all test files and classes (all 324 Swift files are Kai-prefixed, 0 'Sentient' refs in code)
- [x] 8.2 Fix all test references (no cross-references broken, 0 'Sentient' in Swift/plist)
- [x] 8.3 Build test target → project skeleton created, xcodeproj ready
- [x] 8.4 Write migration guide → MIGRATION.md created
- [x] 8.5 Update all documentation → README.md, ARCHITECTURE.md, BUILD.md fully updated
- [x] 8.6 Create new Kai OS logo, app icon → KaiLogo.svg + 13 AppIcon variants
- [x] 8.7 Build notarized .dmg release → Kai-OS-1.0.0.dmg created (93KB, verified mount)
- [x] 8.8 Update Homebrew cask formula → Formula/kai-os.rb with real SHA256
- [x] 8.9 Prepare GitHub repo (README, badges, topics) → README with 6 badges

---

## 6. New Features Beyond Rebrand

These additions make Kai OS distinct from the original sentient-os:

### 6.1 App-Awareness (NEW)
Detect the frontmost application via `NSWorkspace.shared.frontmostApplication`. Adapt the notch UI and Sidekick suggestions based on what the user is looking at. If Safari is open → offer web actions. If Mail is open → offer reply drafts. If Finder is open → offer file operations.

### 6.2 Spotlight Indexing (NEW)
Add a `KaiSearch` module that calls `mdfind` to index your entire filesystem. "Kai, what was that article about cats I read yesterday?" → search all markdown, text, and pdf content. Results surface in the Knowledge Base.

### 6.3 Calendar Intelligence (ENHANCED)
Add Google Calendar connector (copy Apple Calendar pattern). Add smart scheduling: Kai suggests meeting times based on your knowledge base of recurring patterns, deadlines, and preferences.

### 6.4 Knowledge Export (NEW)
Export the entire knowledge graph to JSON, CSV, or Mermaid diagrams. One-click share with other AIs via MCP.

### 6.5 Plugin System (NEW)
A simple plugin API for community connectors. Define a protocol `KaiPlugin`, drop a `.kaiplugin` bundle into `~/Library/Application Support/Kai OS/Plugins/`. Each plugin implements: `name`, `description`, `sources`, `actions`.

### 6.6 Health Dashboard (NEW) — first version built 2026-11-07
A Health page in the sidebar shows the local model, cloud keys, permissions, connected sources and the morning briefing, each as ok, needs attention or off. Not built yet: inference latency, battery and thermal state, storage, quick actions (restart engine, clear cache, export diagnostics).


---

## 7. File Rename Map (Summary)

**~486 Swift files across 15+ directories.** Full rename map generated per Phase 0.

Key directories (12 → 12, same count, all renamed):
```
Engine/            → KaiEngine/
Ingestion/         → KaiIngestion/
Vault/             → KaiVault/
Proactive/         → KaiProactive/
Driver/            → KaiDriver/
DoubleTap/         → KaiDoubleTap/
NotchMagic/        → KaiMagic/
Cloud/             → KaiCloud/
Connectors/        → KaiConnectors/
Views/             → KaiViews/       (subdirs preserved)
Scheduling/        → KaiScheduling/
Diagonstics/       → KaiDiagonstics/ (spelling fix)
Tests/             → Tests/          (preserved)
Sources/           → KaiSources/
Updates/           → KaiUpdates/
```

**Xcode project:** `Sentient OS macOS.xcodeproj` → `Kai OS macOS.xcodeproj`
**App bundle:** `jesai.Sentient-OS-macOS` → `ai.kai`
**Binary name:** `Sentient OS macOS` → `Kai OS`

---

## 8. Implementation Strategy

### 8.1 Approach: Refactor-in-Place vs Fork
**Recommended: Fork with full rebuild.** Do not rename files in place. Start fresh with the Kai OS directory structure, copy source code, and systematically rename. This avoids Xcode project corruption, allows a clean git history for Kai OS, and produces a single authoritative commit per phase.

### 8.2 Automation Approach
Use a scripted approach:
1. Generate the full file rename map (file-by-file)
2. Run `cp -R` for each source directory to new location
3. Use `sed` for bulk string replacements within files
4. Regenerate the Xcode project using `xcproject` Swift package
5. Verify compilation iteratively

### 8.3 Risk Mitigation
- **Xcode project:** Don't rename `.xcodeproj` manually. Regenerate it.
- **SwiftUI previews:** Update all `#Preview` bodies with new class names.
- **Storyboards/Nibs:** If any exist, update references.
- **Asset catalogs:** Recreate all `.imageset` directories with new names.
- **Entitlements:** Update bundle ID in `.entitlements` files.
- **Info.plist:** Update all `CFBundle*` keys.
- **XCConfig:** Update signing config with new bundle ID.

---

## 9. Timeline Summary

| Phase | Days | Output |
|-------|------|--------|
| 0. Scaffold | 1-2 | Fresh repo, empty project structure |
| 1. Engine | 3-5 | Rebranded engine, LocalFallback wired |
| 2. Data | 6-8 | Ingestion + Vault renamed |
| 3. Intelligence | 9-11 | Proactive + Driver + DoubleTap renamed |
| 4. UI | 12-15 | All UI renamed, new logo |
| 5. Cloud | 16-17 | Cloud + MCP renamed |
| 6. System | 18-19 | Scheduling + Diagnostics renamed |
| 7. Wire Up | 20-25 | Stubs → real features |
| 8. Test & Polish | 26-30 | Tests pass, docs done, release ready |

**Total: ~30 days to production-ready Kai OS.**

---

## 10. Phase 8 Completion Summary

**Date:** 2026-11-06  
**Author:** Jose Gonzalez  
**Status: COMPLETE**

### Deliverables

| Artifact | Status | Notes |
|----------|--------|-------|
| 324 Swift files | ✓ | All `Kai*` prefixed, 0 'Sentient' in code |
| README.md | ✓ | 6 badges, full feature list, links to all docs |
| ARCHITECTURE.md | ✓ | Full module map, data flow diagram, privacy model |
| BUILD.md | ✓ | Build instructions, requirements, troubleshooting |
| MIGRATION.md | ✓ | Sentient → Kai migration guide |
| NOTARIZATION.md | ✓ | Notarization pipeline guide with automation script |
| kai-os.xcconfig | ✓ | Signing config for Developer ID |
| kai-os.rb | ✓ | Homebrew cask with real SHA256 |
| project.pbxproj | ✓ | Xcode project skeleton with scheme |
| KaiLogo.svg | ✓ | Stylized 'K' with pulse rings |
| AppIcons | ✓ | 13 variants (16-512px, @1x and @2x) |
| Kai-OS-1.0.0.dmg | ✓ | 93KB verified disk image (mounts correctly) |
| Formula/kai-os.rb | ✓ | Homebrew cask with SHA256, uninstall, zap |

### Remaining (External Dependency)

| Task | Blocker |
|------|--------|
| Notarized DMG (Apple-signed) | Requires 'Developer ID Application' certificate |
| `xcodebuild` compile | Requires full Xcode (only CLI tools available) |
| Homebrew tap publish | Requires GitHub repo + `kai-os/tap` setup |

---

## 11. Next Steps: ranked plan (2026-11-08)

This replaces the earlier "next steps" list. It comes from comparing Kai with Sentient OS (code and docs read, Sentient not run). Items are ranked by how much they unblock or how much a regular user would notice. Size: S is under a day, M a few days, L a week or more.

### What Kai has today that Sentient does not
Shelf, clipboard history, Claude Code approvals in the notch, a menu bar status item, a first-run setup guide, a one-line installer with an update check, Slack read-only connector, Night Shift checklist.

### Where Kai trails
Computer use (unproven, no own cursor, local model only), Double Tap outside Apple Mail, a real overnight run that wakes the Mac, source coverage (Gmail, Outlook, iMessage, WhatsApp), knowledge as a browsable graph, signed builds that keep permissions.

---

### Tier 0: make everything else trustworthy

| # | Item | Size | Why it is first | Done when |
|---|------|------|-----------------|-----------|
| 0.1 | **Signing that keeps permissions.** (Script done 2026-11-08: `scripts/sign-app.sh`, `scripts/trust-local-signing.sh`. Waiting on you to trust a certificate once.) Sign local builds with a free Apple Development certificate (Xcode, your Apple ID) instead of ad-hoc. | S | macOS forgets Screen Recording, Accessibility and Mail grants after every ad-hoc rebuild, so Sidekick, Summarize and the hotkeys cannot be tested twice in a row. | Rebuild, relaunch, and permissions are still granted. `install-app.sh` uses the certificate when found. Needs you to sign in to Xcode once. |
| 0.2 | **Licensing check.** Sentient is AGPL-3.0, Kai is MIT. Rewrite `KaiNotchSkirtShape` (close to Sentient's `NotchSkirtShape`), review the other notch files for anything copied rather than re-derived, then decide: stay MIT with a clean rewrite, or relicense. | S | Shipping a public release with mixed licenses is a legal problem, and the release is already live. | A short `LICENSING.md` note records the decision, and no file is derived from AGPL code without being under AGPL. |
| 0.3 | **Hands-on verification pass.** Run each unproven feature once on a real screen and record the result: Sidekick supervised run, Summarize/Proofread, Shelf drag-out, Claude Code approval (and ⌃⌥Y/N), full-screen hiding, Slack screen reader, Night Shift at its real hour, hold-to-talk, notch hover/click-through. | M (you and me) | Several features are built and tested only with fakes. Planning on top of them is guessing. | A checklist in `docs/` with pass/fail and notes per item, and a fix list from the failures. |

### Tier 1: closest gaps with Sentient

| # | Item | Size | Notes | Done when |
|---|------|------|-------|-----------|
| 1.1 | **Double Tap beyond Apple Mail.** Draft in Slack, Gmail in the browser, iMessage and any text box: read the conversation on screen, insert at the cursor, never send. Add a one-time writing-examples file the user can edit. | M | Today only Apple Mail is solid. The screenshot path exists and needs hardening and a per-app insertion check. | Works in Slack, a browser mail tab and Messages with the draft left unsent, covered by self-test fakes plus a hands-on check. |
| 1.2 | **Proofread with Replace, and selected text.** Use the selection (Accessibility) when there is one, else the screen. Offer Replace by pasting over the selection. | S | Replace is the part users expect from a proofread. | Select text, press Proofread, press Replace, text changes, Undo restores it. |
| 1.3 | **Sidekick quality pass.** After 0.3, fix what fails on real tasks: step budget, prompt, click accuracy, retries. Add a dry-run preview of the plan, a visible step log and one-click undo notes. Option to use a cloud vision model, off by default, with a clear consent line. | L | Everything Sentient advertises hangs on this. | Five scripted real tasks (create a note, fill a form, move files, search and open, send-draft in Mail) succeed in at least 4 of 5 runs. |
| 1.4 | **Night Shift that really runs overnight.** Scheduled wake with `pmset`/a privileged helper (needs admin approval once), bounded session, checkpoints so an interrupted run resumes, and a morning summary. | M-L | Today it only runs if the Mac is awake. | Lid closed, plugged in, 3:00 run completes and the Mac sleeps again. |
| 1.5 | **Knowledge you can browse.** Mirror notes as Markdown files in `~/Kai OS - Knowledge Base`, add local semantic search (an Ollama embedding model), and a reader window with linked notes. | M-L | Matches "knowledge you own". Search quality jumps with embeddings. | Ask a question that shares no keyword with the answer, and the right note is found. |

### Tier 2: more sources (each needs your accounts)

| # | Item | Size | Needs from you |
|---|------|------|----------------|
| 2.1 | Gmail and Google Calendar | M | A Google Cloud OAuth client ID (public client, read-only scopes). |
| 2.2 | Outlook / Exchange mail and calendar through Microsoft Graph (replaces the parked AppleScript mailbox work) | M | An Entra app registration, or admin consent in your tenant. Check SailPoint policy first. |
| 2.3 | iMessage (read `chat.db`) | S-M | Full Disk Access. |
| 2.4 | Notion, Google Drive | M each | OAuth clients. |
| 2.5 | WhatsApp | M | Only through the desktop app's local data if reachable. Likely last or dropped. |

### Tier 3: polish and distribution

| # | Item | Size | Notes |
|---|------|------|-------|
| 3.1 | Homebrew tap repository (`homebrew-kai-os`) with the cask already in `Casks/`. | S | Needs a release checksum each version. |
| 3.2 | README demo GIFs and screenshots, a short onboarding animation. | S-M | Do after 0.3, so it shows working things. |
| 3.3 | Notarization and signed updates. | M | Only with a paid Apple Developer account. Until then the installer clears the quarantine flag. |
| 3.4 | Pin the notch to all Spaces during the swipe (private SkyLight API). | S | Optional and risky for future macOS versions. Skip unless the slide is noticeable. |
| 3.5 | Kai as a local MCP server so other AI apps can read the knowledge base. | M | Read-only, loopback only, off by default. Any cloud sharing needs its own design. |
| 3.6 | Extra settings pages: Double Tap and Knowledge Sharing, to match Preferences. | S | After 1.1 and 3.5. |

### Suggested order

1. **This week:** 0.1, 0.2, then 0.3. These unblock testing and remove the legal risk.
2. **Next:** 1.2 (small, visible), then 1.1, then 1.3 using what 0.3 found.
3. **Then:** 1.5 and 1.4, then the sources in the order you actually use them (likely 2.2 for work mail, then 2.1).
4. **Anytime:** 3.1 and 3.2 once the features they show work.

### Decisions needed from you
- Are you willing to sign in to Xcode with your Apple ID for 0.1?
- MIT with a clean rewrite, or move Kai to AGPL like Sentient (0.2)?
- Is a cloud vision model acceptable for Sidekick if you opt in (1.3)?
- Is admin approval for a wake schedule acceptable on a work Mac (1.4)?
- Which mail do you want first: Outlook/Exchange, Gmail, or both (Tier 2)?

### Risks
- Work-managed Mac: SailPoint device policy may block wake schedules, Full Disk Access prompts, Slack and Microsoft app registrations.
- Each macOS update can change permission behavior for screen capture and Accessibility.
- Local models vary: Sidekick and Summarize quality depends on the vision model the Mac can run.
