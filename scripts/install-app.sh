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
# The command Claude Code hooks run. It talks to the app over a local socket.
cp "$BIN_DIR/kai-hook" "$CONTENTS/MacOS/kai-hook"
cp "Kai OS macOS/Info.plist" "$CONTENTS/Info.plist"
read -r SIGNING_SHA SIGNING_KEYCHAIN <<< "$(scripts/setup-signing.sh)"
if ! codesign --force --sign "$SIGNING_SHA" --keychain "$SIGNING_KEYCHAIN" --identifier ai.kai "$APP" 2>/dev/null; then
    # macOS refuses an untrusted self-signed identity. An ad-hoc signature still runs, but
    # macOS forgets permission grants (Calendar, Mail, microphone) after every rebuild.
    echo "warning: the local signing identity is not trusted, so this build is ad-hoc signed." >&2
    codesign --force --sign - --identifier ai.kai "$APP"
fi

open "$APP"
sleep 2
pgrep -x "Kai OS" >/dev/null
echo "Installed and running: $APP"
