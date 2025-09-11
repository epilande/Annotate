#!/usr/bin/env bash
set -euo pipefail
APP_NAME="Annotate"
PRODUCT_DIR="build/export"
APP_PATH="$PRODUCT_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME.dmg"
DMG_OUT="build/$DMG_NAME"

rm -f "$DMG_OUT"
command -v create-dmg >/dev/null 2>&1 || npm i -g create-dmg 1>&2

create-dmg \
  --overwrite \
  --dmg-title "$APP_NAME" \
  --icon-size 128 \
  "$APP_PATH" \
  "$(dirname "$DMG_OUT")" 1>&2

mv "$(dirname "$DMG_OUT")"/"$APP_NAME"*.dmg "$DMG_OUT" 1>&2

echo "$DMG_OUT"