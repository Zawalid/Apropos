#!/usr/bin/env bash
# Makes a stable self-signed code signing certificate for releases, once.
#
#   scripts/make-signing-cert.sh
#
# Why: an ad hoc signature (what a build gets with no certificate) is only a hash of that one build, so macOS sees every
# update as a new app and drops its Accessibility grant. A signature made with the same certificate every time keeps the
# app's identity, so the grant survives updates. This does NOT remove the first-launch Gatekeeper step (that needs an Apple
# Developer ID and notarization), and it cannot be notarized.
#
# It writes the certificate and its private key to ~/.apropos-secrets/ (mode 700) and prints the commands that put them in
# GitHub secrets. Nothing secret is printed. Back the folder up: if the key is lost, every install re-grants Accessibility
# once, and a new certificate means a new identity. It never touches your keychain.
set -euo pipefail

NAME="${SIGNING_NAME:-Apropos Release}"
DIR="${SECRETS_DIR:-$HOME/.apropos-secrets}"
OPENSSL=/usr/bin/openssl   # the system one: its p12 files import on macOS and on the CI runner
P12="$DIR/apropos-release.p12"
PASS="$DIR/apropos-release.p12.password"

umask 077
mkdir -p "$DIR"
chmod 700 "$DIR"
if [ -e "$P12" ]; then
  echo "$P12 already exists; not overwriting it. Move it away first if you really want a new identity." >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/openssl.cnf" \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
"$OPENSSL" rand -hex 24 > "$PASS"
"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
  -passout "file:$PASS" -out "$P12"
chmod 600 "$P12" "$PASS"

echo "made $P12 (certificate \"$NAME\", valid 10 years) and its password file."
echo
echo "Put them in GitHub, one command each (each reads a file, nothing is shown):"
echo
echo "  base64 < \"$P12\" | gh secret set SIGNING_P12 --repo Zawalid/Apropos"
echo "  gh secret set SIGNING_P12_PASSWORD --repo Zawalid/Apropos < \"$PASS\""
echo "  printf '%s' \"$NAME\" | gh secret set SIGNING_IDENTITY --repo Zawalid/Apropos"
echo
echo "Then back up the folder $DIR (password manager or an encrypted drive)."
