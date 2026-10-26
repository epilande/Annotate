#!/usr/bin/env bash
# Ratchet on hand-written redraw requests in the app sources.
#
# Overlay state redraws itself through OverlayDocument changes, so a new
# `needsDisplay = true` or `setNeedsDisplay(` is usually a missed model change.
# The budget may only go down: lower MAX_SITES when you remove one.
set -euo pipefail

cd "$(dirname "$0")/../.."

MAX_SITES=13
MAX_OVERLAY_WINDOW_SITES=0

sites() {
	grep -rnE 'needsDisplay = true|setNeedsDisplay\(' "$@" --include='*.swift' |
		grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' || true
}

all_sites=$(sites Annotate)
total=$(printf '%s' "$all_sites" | grep -c . || true)
window_total=$(sites Annotate/OverlayWindow.swift | grep -c . || true)

echo "Redraw sites in Annotate/: $total (budget $MAX_SITES)"
echo "Redraw sites in OverlayWindow.swift: $window_total (budget $MAX_OVERLAY_WINDOW_SITES)"

status=0
if [ "$window_total" -gt "$MAX_OVERLAY_WINDOW_SITES" ]; then
	echo "error: OverlayWindow asks the overlay to redraw by hand. Change OverlayView.document" \
		"(or a live preview property) instead, and the view redraws itself." >&2
	status=1
fi
if [ "$total" -gt "$MAX_SITES" ]; then
	echo "error: redraw sites rose above $MAX_SITES:" >&2
	printf '%s\n' "$all_sites" >&2
	status=1
elif [ "$total" -lt "$MAX_SITES" ]; then
	echo "note: below budget; lower MAX_SITES to $total in $0 to lock it in."
fi
exit $status
