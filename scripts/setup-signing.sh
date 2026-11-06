#!/bin/bash
# Creates a local code-signing identity in its own keychain, once. macOS ties permission
# grants to an app's signature, and an ad-hoc signature changes on every build, so a stable
# identity keeps grants across rebuilds. Prints the identity's SHA-1 and keychain path.
set -euo pipefail

SUPPORT="$HOME/Library/Application Support/Kai OS Dev"
KEYCHAIN="$HOME/Library/Keychains/kai-os-dev.keychain-db"
PASSWORD_FILE="$SUPPORT/signing-keychain-password"
NAME="Kai OS Local Dev"

mkdir -p "$SUPPORT"
chmod 700 "$SUPPORT"

if [ ! -f "$KEYCHAIN" ]; then
    (umask 077; openssl rand -hex 24 > "$PASSWORD_FILE")
    PASSWORD="$(cat "$PASSWORD_FILE")"
    WORK="$(mktemp -d)"
    trap 'rm -rf "$WORK"' EXIT
    openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
        -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -subj "/CN=$NAME" \
        -addext "extendedKeyUsage=critical,codeSigning" \
        -addext "keyUsage=critical,digitalSignature" 2>/dev/null
    openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
        -out "$WORK/identity.p12" -passout "pass:$PASSWORD" -name "$NAME" 2>/dev/null
    security create-keychain -p "$PASSWORD" "$KEYCHAIN" >/dev/null
    security set-keychain-settings "$KEYCHAIN"
    security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
    security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null
fi

security unlock-keychain -p "$(cat "$PASSWORD_FILE")" "$KEYCHAIN"
SHA="$(security find-certificate -c "$NAME" -Z "$KEYCHAIN" | awk '/SHA-1 hash:/ {print $3}')"
echo "$SHA $KEYCHAIN"
