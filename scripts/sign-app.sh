#!/bin/bash
# Signs a local build of Kai OS so macOS keeps its permission grants (Screen Recording, Accessibility,
# Mail, Calendar, microphone) across rebuilds. macOS ties a grant to the app's signature. An ad-hoc
# signature is different on every build, so every rebuild loses its grants.
#
# Usage: scripts/sign-app.sh "/path/to/Kai OS.app"
#
# It picks the first identity that works:
#   1. $KAI_SIGN_IDENTITY (a name or SHA-1 from `security find-identity -v -p codesigning`)
#   2. an "Apple Development" certificate (free: Xcode > Settings > Accounts > your Apple ID)
#   3. the local "Kai OS Local Dev" certificate, if you have trusted it for code signing
#   4. ad-hoc, with a warning
# Release builds (scripts/package-release.sh) stay ad-hoc on purpose: they are public.
set -euo pipefail

APP="${1:?usage: sign-app.sh <path to Kai OS.app>}"
HELPER="$APP/Contents/MacOS/kai-hook"

sign() { # identity [keychain]
    local identity="$1" keychain="${2:-}"
    local args=(--force --sign "$identity")
    [ -n "$keychain" ] && args+=(--keychain "$keychain")
    if [ -f "$HELPER" ]; then
        codesign "${args[@]}" --identifier ai.kai.hook "$HELPER" 2>/dev/null || return 1
    fi
    codesign "${args[@]}" --identifier ai.kai "$APP" 2>/dev/null
}

report() { # label
    echo "Signed with: $1"
    codesign -dr - "$APP" 2>&1 | sed -n 's/^designated => /Designated requirement: /p'
}

if [ -n "${KAI_SIGN_IDENTITY:-}" ] && sign "$KAI_SIGN_IDENTITY"; then
    report "$KAI_SIGN_IDENTITY"; exit 0
fi

DEV_SHA="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $2; exit}')"
if [ -n "$DEV_SHA" ] && sign "$DEV_SHA"; then
    report "Apple Development ($DEV_SHA)"; exit 0
fi

if LOCAL="$("$(dirname "$0")/setup-signing.sh" 2>/dev/null)"; then
    read -r SHA KEYCHAIN <<< "$LOCAL"
    if [ -n "$SHA" ] && sign "$SHA" "$KEYCHAIN"; then
        report "Kai OS Local Dev ($SHA)"; exit 0
    fi
fi

codesign --force --sign - --identifier ai.kai.hook "$HELPER" 2>/dev/null || true
codesign --force --sign - --identifier ai.kai "$APP"
cat >&2 <<'MSG'
warning: no trusted signing identity, so this build is ad-hoc signed and macOS will forget its
permissions after the next rebuild. To fix it, once, do one of:
  1. Xcode > Settings > Accounts > add your Apple ID > Manage Certificates > + > Apple Development
  2. Trust the local certificate:  scripts/trust-local-signing.sh   (asks for your password)
Then run scripts/install-app.sh again.
MSG
