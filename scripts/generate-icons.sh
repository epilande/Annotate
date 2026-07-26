#!/usr/bin/env bash
set -euo pipefail

# Regenerates the full AppIcon.appiconset from Design/annotate-icon.svg.
#
# IMPORTANT: never rasterize the SVG directly with ImageMagick. Without the
# rsvg delegate installed, `magick annotate-icon.svg ...` silently produces a
# solid BLACK icon instead of erroring out. ImageMagick is only used here for
# PNG -> PNG downscaling; the SVG -> PNG master is rendered with headless
# Chrome, which renders the SVG correctly everywhere.

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
cd "$REPO_ROOT"

SVG_SRC="Design/annotate-icon.svg"
ICONSET_DIR="Annotate/Assets.xcassets/AppIcon.appiconset"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

if [ ! -x "$CHROME" ]; then
	echo "error: Google Chrome not found at '$CHROME' (required to rasterize the SVG master)" 1>&2
	exit 1
fi

command -v magick >/dev/null 2>&1 || {
	echo "error: 'magick' (ImageMagick) not found on PATH" 1>&2
	exit 1
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Rendering 1024x1024 master from $SVG_SRC via headless Chrome..." 1>&2
"$CHROME" \
	--headless --disable-gpu --hide-scrollbars \
	--default-background-color=00000000 \
	--force-device-scale-factor=1 \
	--window-size=1024,1024 \
	--screenshot="$TMP_DIR/mac1024-raw.png" \
	"$SVG_SRC" 1>&2

# Re-encode through ImageMagick once so every file in the set shares the same
# encoder fingerprint (pixels are unchanged, only the PNG stream is rewritten).
magick "$TMP_DIR/mac1024-raw.png" -strip "PNG32:$ICONSET_DIR/mac1024.png"

# Downscale everything else from the normalized 1024 master. The 16 and 32 px
# slots get a light unsharp pass after resizing: a plain downscale of this
# artwork loses too much ink at that size to read as the app icon.
for size in 512 256 128 64; do
	magick "$ICONSET_DIR/mac1024.png" -resize "${size}x${size}" -strip "PNG32:$ICONSET_DIR/mac${size}.png"
done
# 16 px needs a stronger pass than 32 px: measured against the pre-vector
# icon (darkest pixel 60, 4.3% dark ink on white), 0x0.6+1.2 restores the
# 32 px slot to parity while 16 px still reads washed out until 0x0.75+1.8.
magick "$ICONSET_DIR/mac1024.png" -resize 32x32 -unsharp 0x0.6+1.2+0 -strip "PNG32:$ICONSET_DIR/mac32.png"
magick "$ICONSET_DIR/mac1024.png" -resize 16x16 -unsharp 0x0.75+1.8+0 -strip "PNG32:$ICONSET_DIR/mac16.png"

# The @2x slots whose pixel size collides with the next @1x size up
# (16x16@2x, 128x128@2x, 256x256@2x) reference the same PNG in
# Contents.json, so no extra files are needed for them.

echo "" 1>&2
echo "Verifying generated icons..." 1>&2

status=0
for f in mac16.png mac32.png mac64.png mac128.png mac256.png mac512.png mac1024.png; do
	dims="$(magick identify -format "%wx%h" "$ICONSET_DIR/$f")"
	echo "  $f: $dims" 1>&2
done

corners="$(magick "$ICONSET_DIR/mac1024.png" -alpha extract -format "%[fx:p{0,0}] %[fx:p{w-1,0}] %[fx:p{0,h-1}] %[fx:p{w-1,h-1}]" info:)"
echo "  mac1024.png corner alpha: $corners" 1>&2
for a in $corners; do
	if [ "$a" != "0" ]; then
		echo "error: expected transparent corners on mac1024.png, got alpha=$a" 1>&2
		status=1
	fi
done

if [ "$status" -ne 0 ]; then
	exit "$status"
fi

echo "Done." 1>&2
