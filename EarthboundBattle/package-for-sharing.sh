#!/bin/bash
# Build a UNIVERSAL (Apple Silicon + Intel), ad-hoc-signed .saver and package it
# into a zip a friend can install, with a double-click installer + README.
#
# Usage:  ./package-for-sharing.sh
set -eo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAVER_NAME="EarthboundBattle.saver"
STAGE="$PROJECT_DIR/dist/EarthboundBattle Screensaver"
ZIP_OUT="$PROJECT_DIR/dist/EarthboundBattle-Screensaver.zip"

echo "Building universal (arm64 + x86_64, Release)..."
xcodebuild -project "$PROJECT_DIR/EarthboundBattle.xcodeproj" \
  -scheme EarthboundBattle -configuration Release \
  -derivedDataPath "$PROJECT_DIR/build" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build >/dev/null

BUILT="$PROJECT_DIR/build/Build/Products/Release/$SAVER_NAME"
[ -d "$BUILT" ] || { echo "Build product not found at $BUILT" >&2; exit 1; }

echo "Staging package..."
rm -rf "$PROJECT_DIR/dist"
mkdir -p "$STAGE"
cp -R "$BUILT" "$STAGE/$SAVER_NAME"

echo "Ad-hoc signing..."
codesign --force --deep --sign - "$STAGE/$SAVER_NAME"

echo "Architectures: $(lipo -archs "$STAGE/$SAVER_NAME/Contents/MacOS/EarthboundBattle")"

# Double-click installer for the recipient.
cat > "$STAGE/Install.command" <<'INSTALL'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/Library/Screen Savers"
mkdir -p "$DEST"
rm -rf "$DEST/EarthboundBattle.saver"
cp -R "$DIR/EarthboundBattle.saver" "$DEST/"
# Clear the download quarantine so macOS won't block it.
xattr -dr com.apple.quarantine "$DEST/EarthboundBattle.saver" 2>/dev/null || true
echo ""
echo "Installed! Now open System Settings > Screen Saver and pick \"EarthboundBattle\"."
echo "You can close this window."
INSTALL
chmod +x "$STAGE/Install.command"

cat > "$STAGE/README.txt" <<'README'
Earthbound Battle Backgrounds — macOS Screensaver
=================================================

EASY INSTALL (recommended)
1. Right-click (or Control-click) "Install.command" and choose Open.
   - macOS will warn it's from an unidentified developer; click Open.
   - It copies the screensaver into place. Close the window when it says "Installed!".
2. Open System Settings > Screen Saver and choose "EarthboundBattle".

MANUAL INSTALL (if you prefer)
1. Double-click "EarthboundBattle.saver" — System Settings will offer to install it.
2. If macOS blocks it: System Settings > Privacy & Security, scroll down, and click
   "Open Anyway" next to the EarthboundBattle message. Then pick it in Screen Saver.

OPTIONS
In System Settings > Screen Saver, with EarthboundBattle selected, click "Options…"
to set how often the background changes and the animation speed.

Note: this is a personal, free, fan-made project — not notarized by Apple, which is
why the one-time "unidentified developer" prompt appears. It is safe to open.
README

echo "Zipping..."
( cd "$PROJECT_DIR/dist" && zip -r -q "$ZIP_OUT" "EarthboundBattle Screensaver" )

echo ""
echo "Done. Share this file with friends:"
echo "  $ZIP_OUT"
