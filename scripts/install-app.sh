#!/bin/bash
# Builds Kai OS and installs it into ~/Applications/Kai OS.app, then relaunches it.
# A failed build stops the script, so a stale binary is never launched.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="$HOME/Applications/Kai OS.app"
CONTENTS="$APP/Contents"

swift build
BIN_DIR="$(swift build --show-bin-path)"

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
plutil -lint "Kai OS macOS/Info.plist"

pkill -x "Kai OS" || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x "Kai OS" >/dev/null || break
    sleep 0.3
done

cp "$BIN_DIR/Kai OS" "$CONTENTS/MacOS/Kai OS"
cp "Kai OS macOS/Info.plist" "$CONTENTS/Info.plist"
read -r SIGNING_SHA SIGNING_KEYCHAIN <<< "$(scripts/setup-signing.sh)"
codesign --force --sign "$SIGNING_SHA" --keychain "$SIGNING_KEYCHAIN" --identifier ai.kai "$APP"

open "$APP"
sleep 2
pgrep -x "Kai OS" >/dev/null
echo "Installed and running: $APP"
