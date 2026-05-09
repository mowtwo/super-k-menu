#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUILT_APP="$ROOT_DIR/build/Release/SuperKMenu.app"
DIST_APP="$ROOT_DIR/dist/SuperKMenu.app"

xcodebuild \
  -project SuperKMenu.xcodeproj \
  -target SuperKMenu \
  -configuration Release \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual

rm -rf "$DIST_APP"
mkdir -p dist
cp -R "$BUILT_APP" "$DIST_APP"

echo "Packaged: $DIST_APP"
