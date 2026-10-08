#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Prefer full Xcode when installed; do not change the global xcode-select setting.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$PWD/build/Flick.app"
mkdir -p "$APP/Contents/MacOS"
# Replace the inode instead of overwriting code mapped by a running Flick.
# The running process keeps the old version until the user quits/reopens it.
cp "$BIN_DIR/Flick" "$APP/Contents/MacOS/.Flick.new"
mv -f "$APP/Contents/MacOS/.Flick.new" "$APP/Contents/MacOS/Flick"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Ad-hoc signing works for local use. A stable signing identity is preferable
# for preserving Accessibility approval across rebuilds.
codesign --force --sign "${FLICK_SIGN_IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"
echo "Built: $APP"
echo "Quit any running Flick instance, then launch: open \"$APP\""
