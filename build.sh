#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="HeadsUp"
DISPLAY_NAME="Heads Up"
MINIMUM_MACOS_VERSION="${MINIMUM_MACOS_VERSION:-14.0}"
ARCHS="${ARCHS:-$(uname -m)}"
BUNDLE_ID="${BUNDLE_ID:-com.boriskachscovsky.headsup}"
VERSION="${VERSION:-0.3.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
DEST="${1:-$PROJECT_DIR/build}"
APP="$DEST/$DISPLAY_NAME.app"
CONTENTS="$APP/Contents"

command -v swiftc >/dev/null || {
  echo "error: swiftc not found; install the Xcode Command Line Tools" >&2
  exit 1
}

echo "==> Running logic tests"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
TEST_TARGET="$(uname -m)-apple-macos$MINIMUM_MACOS_VERSION"
swiftc -warnings-as-errors -target "$TEST_TARGET" \
  -framework AppKit -framework EventKit \
  "$PROJECT_DIR/Sources/Models.swift" \
  "$PROJECT_DIR/Sources/MeetingLinkExtractor.swift" \
  "$PROJECT_DIR/Sources/EventStoreService.swift" \
  "$PROJECT_DIR/Tests/LogicTests.swift" \
  -o "$TEST_DIR/LogicTests"
"$TEST_DIR/LogicTests"

echo "==> Building $DISPLAY_NAME for $ARCHS"
BINARIES=()
for ARCH in $ARCHS; do
  BINARY="$TEST_DIR/$APP_NAME-$ARCH"
  swiftc -warnings-as-errors -O -parse-as-library \
    -target "$ARCH-apple-macos$MINIMUM_MACOS_VERSION" \
    -framework AppKit -framework EventKit -framework ServiceManagement \
    "$PROJECT_DIR"/Sources/*.swift \
    -o "$BINARY"
  BINARIES+=("$BINARY")
done

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
if [[ ${#BINARIES[@]} -eq 1 ]]; then
  cp "${BINARIES[0]}" "$CONTENTS/MacOS/$APP_NAME"
else
  lipo -create "${BINARIES[@]}" -output "$CONTENTS/MacOS/$APP_NAME"
fi
cp "$PROJECT_DIR/Info.plist" "$CONTENTS/Info.plist"
cp "$PROJECT_DIR/Assets/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $MINIMUM_MACOS_VERSION" "$CONTENTS/Info.plist"
chmod +x "$CONTENTS/MacOS/$APP_NAME"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
fi
codesign --verify --verbose=1 "$APP"

echo "✅ Built $APP"
echo "   Run: open \"$APP\""
