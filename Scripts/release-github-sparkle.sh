#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 1.0.1"
  exit 64
fi

VERSION="$1"
REPO_SLUG="${ORBIT_GITHUB_REPOSITORY:-kohichiwa/Orbit-MacOS}"
TARGET_COMMIT="$(git rev-parse HEAD)"
APP_NAME="Orbit"
SCHEME="Orbit"
DERIVED_DATA="${DERIVED_DATA:-/tmp/OrbitReleaseDerived}"
RELEASE_DIR="${RELEASE_DIR:-.release}"
UPDATES_DIR="$RELEASE_DIR/updates"
ARCHIVE_NAME="$APP_NAME-$VERSION.zip"
ARCHIVE_PATH="$UPDATES_DIR/$ARCHIVE_NAME"
APPCAST_URL="https://github.com/$REPO_SLUG/releases/latest/download/appcast.xml"
DOWNLOAD_URL_PREFIX="https://github.com/$REPO_SLUG/releases/download/v$VERSION/"

if [[ -z "${ORBIT_SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  echo "ORBIT_SPARKLE_PUBLIC_ED_KEY is required."
  echo "Run Sparkle/bin/generate_keys once and pass the printed public key:"
  echo "ORBIT_SPARKLE_PUBLIC_ED_KEY='<public key>' $0 $VERSION"
  exit 64
fi

mkdir -p "$UPDATES_DIR"

xcodebuild \
  -project Orbit.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -sdk macosx \
  -derivedDataPath "$DERIVED_DATA" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$VERSION" \
  ORBIT_SPARKLE_PUBLIC_ED_KEY="$ORBIT_SPARKLE_PUBLIC_ED_KEY" \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app was not found at $APP_PATH"
  exit 66
fi

ditto -c -k --keepParent "$APP_PATH" "$ARCHIVE_PATH"

SPARKLE_BIN="${SPARKLE_BIN:-}"
if [[ -z "$SPARKLE_BIN" ]]; then
  SPARKLE_BIN="$(find "$DERIVED_DATA/SourcePackages/artifacts" -path "*/Sparkle/bin" -type d -print -quit 2>/dev/null || true)"
fi

if [[ -z "$SPARKLE_BIN" || ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
  echo "Sparkle tools were not found."
  echo "Pass SPARKLE_BIN=/path/to/Sparkle/bin."
  exit 66
fi

GENERATE_APPCAST_ARGS=()
GENERATE_APPCAST_ARGS+=(--download-url-prefix "$DOWNLOAD_URL_PREFIX")
if [[ -n "${ORBIT_SPARKLE_PRIVATE_ED_KEY_FILE:-}" ]]; then
  GENERATE_APPCAST_ARGS+=(--ed-key-file "$ORBIT_SPARKLE_PRIVATE_ED_KEY_FILE")
fi

"$SPARKLE_BIN/generate_appcast" "${GENERATE_APPCAST_ARGS[@]}" "$UPDATES_DIR"

gh release create "v$VERSION" \
  "$ARCHIVE_PATH" \
  "$UPDATES_DIR/appcast.xml" \
  --repo "$REPO_SLUG" \
  --target "$TARGET_COMMIT" \
  --title "Orbit $VERSION" \
  --notes "Orbit $VERSION"

echo "Published Orbit $VERSION"
echo "Appcast: $APPCAST_URL"
