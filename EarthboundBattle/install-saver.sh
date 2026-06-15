#!/bin/bash
# Build the screensaver, then (re)install it into ~/Library/Screen Savers,
# busting the macOS screensaver cache so the new build actually shows up.
#
# Usage:  ./install-saver.sh
set -eo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAVER_NAME="EarthboundBattle.saver"
DEST_DIR="$HOME/Library/Screen Savers"

echo "Building (Release, unsigned)..."
xcodebuild -project "$PROJECT_DIR/EarthboundBattle.xcodeproj" \
  -scheme EarthboundBattle -configuration Release \
  -derivedDataPath "$PROJECT_DIR/build" \
  CODE_SIGNING_ALLOWED=NO build >/dev/null

BUILT="$PROJECT_DIR/build/Build/Products/Release/$SAVER_NAME"
if [ ! -d "$BUILT" ]; then
  echo "Build product not found at $BUILT" >&2
  exit 1
fi

echo "Closing System Settings and screensaver helpers..."
osascript -e 'tell application "System Settings" to quit' 2>/dev/null || true
killall legacyScreenSaver 2>/dev/null || true
killall ScreenSaverEngine 2>/dev/null || true

echo "Installing to $DEST_DIR ..."
mkdir -p "$DEST_DIR"
rm -rf "$DEST_DIR/$SAVER_NAME"
cp -R "$BUILT" "$DEST_DIR/$SAVER_NAME"

# Apple Silicon kills unsigned bundles on launch and won't list them. A proper
# ad-hoc signature (no Apple account needed) makes it run and appear.
echo "Ad-hoc signing..."
codesign --force --deep --sign - "$DEST_DIR/$SAVER_NAME"

echo "Installed. Test it with EITHER:"
echo "  - System Settings > Screen Saver > pick EarthboundBattle, or"
echo "  - Run the engine directly (faster):"
echo "      /System/Library/CoreServices/ScreenSaverEngine.app/Contents/MacOS/ScreenSaverEngine"
