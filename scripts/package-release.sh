#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$PROJECT_DIR/dist}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

mkdir -p "$DIST_DIR"
ARCHS="${ARCHS:-arm64 x86_64}" \
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}" \
"$PROJECT_DIR/build.sh" "$DIST_DIR"

APP="$DIST_DIR/Heads Up.app"
DMG="$DIST_DIR/Heads-Up.dmg"
DMG_ROOT="$(mktemp -d)"
trap 'rm -rf "$DMG_ROOT"' EXIT

cp -R "$APP" "$DMG_ROOT/Heads Up.app"
ln -s /Applications "$DMG_ROOT/Applications"
rm -f "$DMG"
hdiutil create -volname "Heads Up" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG"

if [[ -n "$NOTARY_PROFILE" ]]; then
  if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "error: notarization requires SIGNING_IDENTITY" >&2
    exit 1
  fi
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo "✅ Packaged $DMG"
