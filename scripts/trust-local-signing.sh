#!/bin/bash
# Tells macOS to trust Kai's local signing certificate for code signing, for your user only.
# macOS shows its own password / Touch ID prompt. Nothing is changed for other users.
# Undo with: security remove-trusted-cert "$HOME/Library/Application Support/Kai OS Dev/kai-os-dev.pem"
set -euo pipefail
SUPPORT="$HOME/Library/Application Support/Kai OS Dev"
KEYCHAIN="$HOME/Library/Keychains/kai-os-dev.keychain-db"
PEM="$SUPPORT/kai-os-dev.pem"
"$(dirname "$0")/setup-signing.sh" >/dev/null
security find-certificate -c "Kai OS Local Dev" -p "$KEYCHAIN" > "$PEM"
security add-trusted-cert -r trustRoot -p codeSign -k "$HOME/Library/Keychains/login.keychain-db" "$PEM"
echo "Trusted. Check with: security find-identity -v -p codesigning"
