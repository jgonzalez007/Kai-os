#!/bin/bash
# Installs the latest Kai OS release:
#   curl -fsSL https://raw.githubusercontent.com/jgonzalez007/Kai-os/main/scripts/install.sh | bash
# Remove it again with:  ... | bash -s -- --uninstall
#
# It downloads Kai-OS.zip from the latest GitHub release, checks the SHA-256 checksum, puts
# Kai OS.app in /Applications (or ~/Applications when that is not writable), and clears the
# download quarantine flag on that one app so macOS opens it. Kai OS is not notarized by Apple.
set -euo pipefail

REPO="jgonzalez007/Kai-os"
BASE="${KAI_INSTALL_BASE:-https://github.com/$REPO/releases/latest/download}"
# For testing only: KAI_INSTALL_BASE reads from another location, KAI_INSTALL_DIR installs
# somewhere else and neither quits nor opens the real app.
TEST_DIR="${KAI_INSTALL_DIR:-}"

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "Kai OS runs on macOS only."
[ "$(uname -m)" = "arm64" ] || die "Kai OS needs a Mac with Apple Silicon."
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MAJOR" -ge 14 ] || die "Kai OS needs macOS 14 or later."

if [ -n "$TEST_DIR" ]; then DEST_DIR="$TEST_DIR"
elif [ -w /Applications ]; then DEST_DIR="/Applications"; else DEST_DIR="$HOME/Applications"; fi
DEST="$DEST_DIR/Kai OS.app"

quit_running() {
    [ -z "$TEST_DIR" ] || return 0
    if pgrep -x "Kai OS" >/dev/null; then
        say "Quitting Kai OS..."
        osascript -e 'tell application "Kai OS" to quit' >/dev/null 2>&1 || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x "Kai OS" >/dev/null || break; sleep 0.5; done
        pgrep -x "Kai OS" >/dev/null && die "Kai OS is still running. Quit it and run this again."
    fi
}

if [ "${1:-}" = "--uninstall" ]; then
    quit_running
    if [ -n "$TEST_DIR" ]; then DIRS=("$TEST_DIR"); else DIRS=(/Applications "$HOME/Applications"); fi
    for dir in "${DIRS[@]}"; do
        if [ -d "$dir/Kai OS.app" ]; then rm -rf "$dir/Kai OS.app"; say "Removed $dir/Kai OS.app"; fi
    done
    say "Your settings and knowledge base were kept. They are in ~/Library/Application Support/Kai OS"
    say "and ~/Kai OS - Knowledge Base. Delete them yourself if you want them gone."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say "Downloading Kai OS..."
curl -fsSL -o "$TMP/Kai-OS.zip" "$BASE/Kai-OS.zip" || die "Could not download the release. Is there a published release yet?"
curl -fsSL -o "$TMP/Kai-OS.zip.sha256" "$BASE/Kai-OS.zip.sha256" || die "Could not download the checksum."

say "Checking the download..."
EXPECTED="$(awk '{print $1}' "$TMP/Kai-OS.zip.sha256")"
ACTUAL="$(shasum -a 256 "$TMP/Kai-OS.zip" | awk '{print $1}')"
[ -n "$EXPECTED" ] && [ "$EXPECTED" = "$ACTUAL" ] || die "The checksum does not match. Nothing was installed."

ditto -x -k "$TMP/Kai-OS.zip" "$TMP/out"
[ -d "$TMP/out/Kai OS.app" ] || die "The download did not contain Kai OS.app."

quit_running
mkdir -p "$DEST_DIR"
rm -rf "$DEST"
ditto "$TMP/out/Kai OS.app" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

say "Installed $DEST"
[ -n "$TEST_DIR" ] || open "$DEST"
