#!/bin/zsh
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <app-path> <dmg-path>" >&2
  exit 1
fi

APP_PATH="$1"
DMG_PATH="$2"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DMG_STAGING_DIR="$ROOT_DIR/dist/dmg"
APP_BUNDLE_NAME="$(basename "$APP_PATH")"
MACOS_SIGNING_IDENTITY="${MACOS_SIGNING_IDENTITY:-Developer ID Application}"

required_vars=(
  MACOS_CERT_P12_BASE64
  MACOS_CERT_PASSWORD
  APPLE_TEAM_ID
  APPLE_API_KEY_ID
  APPLE_API_ISSUER_ID
  APPLE_API_PRIVATE_KEY
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${(P)var_name:-}" ]]; then
    echo "Skipping signing and notarization because $var_name is not set"
    exit 0
  fi
done

TMP_DIR="$(mktemp -d)"
KEYCHAIN_PATH="$TMP_DIR/release-signing.keychain-db"
CERT_PATH="$TMP_DIR/certificate.p12"
API_KEY_PATH="$TMP_DIR/AuthKey_${APPLE_API_KEY_ID}.p8"

cleanup() {
  security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "$MACOS_CERT_P12_BASE64" | base64 --decode > "$CERT_PATH"
printf '%s' "$APPLE_API_PRIVATE_KEY" > "$API_KEY_PATH"

security create-keychain -p "$MACOS_CERT_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$MACOS_CERT_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERT_PATH" -k "$KEYCHAIN_PATH" -P "$MACOS_CERT_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security list-keychains -d user -s "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$MACOS_CERT_PASSWORD" "$KEYCHAIN_PATH"

codesign --force --deep --options runtime --timestamp --sign "$MACOS_SIGNING_IDENTITY" "$APP_PATH"
rm -rf "$DMG_STAGING_DIR/$APP_BUNDLE_NAME"
cp -R "$APP_PATH" "$DMG_STAGING_DIR/$APP_BUNDLE_NAME"

TMP_DMG="${DMG_PATH}.signed"
hdiutil create \
  -volname "VoiceRaft Signed" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$TMP_DMG"
mv "$TMP_DMG" "$DMG_PATH"

codesign --force --timestamp --sign "$MACOS_SIGNING_IDENTITY" "$DMG_PATH"

xcrun notarytool submit "$DMG_PATH" \
  --key "$API_KEY_PATH" \
  --key-id "$APPLE_API_KEY_ID" \
  --issuer "$APPLE_API_ISSUER_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --wait

xcrun stapler staple "$DMG_PATH"

echo "Signed and notarized $DMG_PATH"
