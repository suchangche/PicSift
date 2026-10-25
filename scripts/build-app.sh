#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/Products/PicSift.app"

swift build --package-path "$ROOT" --configuration release --arch arm64
BIN_DIR="$(swift build --package-path "$ROOT" --configuration release --arch arm64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PicSift" "$APP/Contents/MacOS/PicSift"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/MacOS/PicSift"
codesign --force --sign - --identifier app.picsift.mac "$APP" >/dev/null

printf '%s\n' "$APP"
