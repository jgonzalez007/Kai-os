# Kai OS — Build Guide

## Quick Start

```bash
# Clone
git clone https://github.com/kai-os/kai-os.git
cd kai-os

# Build
xcodebuild -project "Kai OS.xcodeproj" \
  -scheme "Kai OS" \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  build

# Install
cp -r build/Release/Kai\ OS.app /Applications/
```

## Build from Command Line

```bash
# Debug build (for development)
xcodebuild \
  -project "Kai OS.xcodeproj" \
  -scheme "Kai OS" \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build

# Release build (for distribution)
xcodebuild \
  -project "Kai OS.xcodeproj" \
  -scheme "Kai OS" \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  build

# Run tests
xcodebuild \
  -project "Kai OS.xcodeproj" \
  -scheme "Kai OS Tests" \
  -destination 'platform=macOS,arch=arm64' \
  test
```

## Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| macOS | 15.4 (Sequoia) | 15.4+ |
| Chip | Apple Silicon M1 | M1+ (any) |
| RAM | 8 GB | 16 GB |
| Xcode | 15.0+ | 15.4+ |
| Swift | 5.9+ | 5.9+ |

## Project Structure

```
Kai OS/
├── Kai OS.xcodeproj/          # Xcode project
├── Kai OS macOS/              # Source code
│   ├── App/                   # App entry point
│   ├── KaiEngine/             # On-device inference
│   ├── KaiIngestion/          # Data connectors
│   ├── KaiVault/              # Knowledge base
│   ├── KaiProactive/          # Proactive intelligence
│   ├── KaiDriver/             # Computer-use automation
│   ├── KaiDoubleTap/          # Smart reply
│   ├── KaiMagic/              # Dynamic Island UI
│   ├── KaiCloud/              # Hosted AI
│   ├── Views/                 # SwiftUI interfaces
│   ├── KaiScheduling/         # Night Shift scheduler
│   ├── KaiConnectors/         # Direct MCP
│   ├── KaiSources/            # Data sources
│   ├── KaiUpdates/            # App updates
│   ├── KaiDiagonstics/        # Diagnostics
│   ├── Tests/                 # Test suite
│   └── Assets.xcassets/       # Icons & assets
├── Info.plist                 # App configuration
├── ai.kai.entitlements        # App entitlements
├── README.md                  # This file
├── ARCHITECTURE.md            # Architecture docs
├── MIGRATION.md               # Sentient → Kai migration
├── LICENSING.md               # Licensing terms
├── CLAUDE.md                  # (if exists)
├── CONTRIBUTING.md            # How to contribute
└── LICENSE                    # MIT License
```

## Configuration

| Setting | Value |
|---------|-------|
| Bundle ID | `ai.kai` |
| Display Name | `Kai OS` |
| Knowledge Base | `~/Kai OS - Knowledge Base/` |
| Settings | `~/Library/Preferences/ai.kai.plist` |
| LaunchAgent | `ai.kai.wakehelper` |

## Build Output

| Build Type | Output Path |
|------------|-------------|
| Debug | `build/Debug/Kai OS.app` |
| Release | `build/Release/Kai OS.app` |
| Test | `build/Test/` (test reports) |

## Troubleshooting

### "No such file or module"
- Ensure you're building from the project root
- Run `xcodebuild -list` to verify schemes

### "Code signing failed"
```bash
codesign --force --deep --sign - "Kai OS.app"
```

### "Missing entitlements"
```bash
codesign --entitlements ai.kai.entitlements \
  --force --deep --sign - "Kai OS.app"
```

---

For full architecture details, see [ARCHITECTURE.md](ARCHITECTURE.md).
For migration from sentient-os, see [MIGRATION.md](MIGRATION.md).
