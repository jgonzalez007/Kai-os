# Kai OS — Notarization Guide

## Prerequisites

1. **Apple Developer Account** ($99/year)
2. **Developer ID Application** certificate
3. **notarytool** credentials (App-Specific Password + Team ID)

## Steps

### 1. Sign the App

```bash
codesign \
  --timestamp \
  --deep \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  --entitlements "ai.kai.entitlements" \
  "Kai OS.app"
```

### 2. Create DMG (with app symlink)

```bash
hdiutil create \
  -volname "Kai OS" \
  -fs APFS \
  -format UDZO \
  -o "Kai-OS-1.0.0.dmg" \
  -srcfolder .
```

### 3. Notarize

```bash
xcrun notarytool submit \
  "Kai-OS-1.0.0.dmg" \
  --team-id "TEAMID" \
  --apple-id "apple-id@email.com" \
  --password "@keychain:NotaryPassword" \
  --wait
```

### 4. Staple

```bash
xcrun stapler staple "Kai-OS-1.0.0.dmg"
```

### 5. Verify

```bash
xcrun notarytool info "Kai-OS-1.0.0.dmg" \
  --team-id "TEAMID" \
  --apple-id "apple-id@email.com" \
  --password "@keychain:NotaryPassword"
```

## Homebrew Cask

After notarization, update the cask:

```ruby
sha256 "REAL_SHA256_FROM_HDIUTIL_CHECKSUM"
```

Then push to `kai-os/tap` homebrew tap.

## Automation Script

```bash
#!/bin/bash
# kai-notarize.sh — Full notarization pipeline

TEAM_ID="TEAMID"
APP_NAME="Kai OS"
VERSION="1.0.0"

# Sign
codesign --timestamp --deep \
  --sign "Developer ID Application: $APP_NAME ($TEAM_ID)" \
  --entitlements "ai.kai.entitlements" \
  "${APP_NAME}.app"

# Create notarized DMG
hdiutil create -fs APFS -volname "${APP_NAME}" \
  -format UDZO -o "Kai-OS-${VERSION}.dmg" \
  -srcfolder .

# Notarize
xcrun notarytool submit "Kai-OS-${VERSION}.dmg" \
  --team-id "$TEAM_ID" \
  --password "@keychain:NotaryPassword" \
  --wait

# Staple
xcrun stapler staple "Kai-OS-${VERSION}.dmg"

echo "✅ Notarized: Kai-OS-${VERSION}.dmg"
```

