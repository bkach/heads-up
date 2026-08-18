#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$PROJECT_DIR/dist}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "error: set SIGNING_IDENTITY to a Developer ID Application certificate" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
ARCHS="${ARCHS:-arm64 x86_64}" \
SIGNING_IDENTITY="$SIGNING_IDENTITY" \
"$PROJECT_DIR/build.sh" "$DIST_DIR"

APP="$DIST_DIR/Heads Up.app"
ARCHIVE="$DIST_DIR/Heads-Up.zip"
rm -f "$ARCHIVE"
ditto -c -k --keepParent "$APP" "$ARCHIVE"

if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ARCHIVE"
  ditto -c -k --keepParent "$APP" "$ARCHIVE"
fi

echo "✅ Packaged $ARCHIVE"
