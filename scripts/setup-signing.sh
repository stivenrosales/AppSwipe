#!/bin/zsh
# setup-signing.sh — create a STABLE local code-signing identity for app-swipe.
#
# Why: ad-hoc signing (codesign --sign -) changes the binary's cdhash on every
# build, so macOS treats each rebuild as a different app and DROPS the granted
# Accessibility / Input Monitoring permissions. A stable self-signed certificate
# gives TCC a stable code-signing requirement, so the permission sticks across
# rebuilds (you authorize once, never again).
#
# Design: the identity lives in a DEDICATED, password-less keychain so codesign
# can use the private key without GUI prompts. Idempotent: re-running is a no-op
# once the identity exists.

set -euo pipefail

CERT_NAME="AppSwipe Local Signing"
KC_NAME="appswipe-signing.keychain-db"
KC_PATH="$HOME/Library/Keychains/$KC_NAME"
KC_PASS=""   # empty on purpose: avoids codesign keychain-access prompts

# --- Idempotency: bail out if the identity already exists ---
# IMPORTANT: omit -v. A self-signed cert is reported as "not trusted", so `-v`
# (valid identities only) would HIDE it, making this check always miss and create
# DUPLICATE identities — which then break codesign with "ambiguous (matches ...)".
ids="$(security find-identity -p codesigning 2>/dev/null || true)"
if [[ "$ids" == *"$CERT_NAME"* ]]; then
  echo "OK: code-signing identity '$CERT_NAME' already available."
  exit 0
fi

# --- 1. Dedicated keychain (no password) ---
if [[ ! -f "$KC_PATH" ]]; then
  security create-keychain -p "$KC_PASS" "$KC_NAME"
fi
security set-keychain-settings "$KC_PATH"          # no inactivity auto-lock
security unlock-keychain -p "$KC_PASS" "$KC_PATH"

# --- 2. Self-signed Code Signing certificate (openssl) ---
TMP="$(mktemp -d)"
{
  print -r -- "[req]"
  print -r -- "distinguished_name = dn"
  print -r -- "x509_extensions = v3"
  print -r -- "prompt = no"
  print -r -- "[dn]"
  print -r -- "CN = $CERT_NAME"
  print -r -- "[v3]"
  print -r -- "basicConstraints = critical,CA:FALSE"
  print -r -- "keyUsage = critical,digitalSignature"
  print -r -- "extendedKeyUsage = critical,codeSigning"
} > "$TMP/cs.cnf"

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cs.cnf"
# macOS `security import` uses a SHA1 MAC + legacy PBE for PKCS#12. Force them, or
# the import fails with "MAC verification failed" (OpenSSL/LibreSSL default to SHA256/AES).
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/id.p12" -passout pass:appswipe -name "$CERT_NAME" \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1

# --- 3. Import into the dedicated keychain, authorize codesign ---
security import "$TMP/id.p12" -k "$KC_PATH" -P appswipe -A -T /usr/bin/codesign

# --- 4. Allow the key to be used without prompts (partition list) ---
security set-key-partition-list -S apple-tool:,apple: -s -k "$KC_PASS" "$KC_PATH" >/dev/null 2>&1 || true

# --- 5. Add the dedicated keychain to the user search list (keep existing) ---
typeset -a kc_list
for line in "${(@f)$(security list-keychains -d user)}"; do
  clean="${line//\"/}"
  clean="${clean// /}"
  clean="${clean//$'\t'/}"
  [[ -n "$clean" ]] && kc_list+=("$clean")
done
if [[ " ${kc_list[*]} " != *" $KC_PATH "* ]]; then
  security list-keychains -d user -s "$KC_PATH" "${kc_list[@]}"
fi

rm -rf "$TMP"
echo "OK: code-signing identity '$CERT_NAME' created in $KC_NAME."
