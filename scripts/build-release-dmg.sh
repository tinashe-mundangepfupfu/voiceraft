#!/bin/zsh
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <version-tag>" >&2
  exit 1
fi

VERSION_TAG="$1"
VERSION="${VERSION_TAG#v}"
if [[ ! "$VERSION_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "expected semver tag like v1.2.3, got: $VERSION_TAG" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
DERIVED_DATA_DIR="$ROOT_DIR/.build/release-derived-data"
APP_NAME="VoiceRaft"
APP_BUNDLE_NAME="$APP_NAME.app"
APP_PATH="$DIST_DIR/$APP_BUNDLE_NAME"
DMG_STAGING_DIR="$DIST_DIR/dmg"
DMG_PATH="$DIST_DIR/VoiceRaft-v$VERSION.dmg"
VOLUME_NAME="VoiceRaft $VERSION"

rm -rf "$DERIVED_DATA_DIR" "$DMG_STAGING_DIR" "$APP_PATH" "$DMG_PATH"
mkdir -p "$DIST_DIR" "$DMG_STAGING_DIR"

xcodebuild \
  -project "$ROOT_DIR/voiceraft.xcodeproj" \
  -scheme "voiceraft" \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" \
  build

cp -R "$DERIVED_DATA_DIR/Build/Products/Release/$APP_BUNDLE_NAME" "$APP_PATH"
cp -R "$APP_PATH" "$DMG_STAGING_DIR/$APP_BUNDLE_NAME"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Built $APP_PATH"
echo "Built $DMG_PATH"
