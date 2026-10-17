#!/bin/bash

# Fail when code reads or writes UserDefaults outside the typed settings store.
# Usage: ./scripts/ci/check_settings_access.sh (from the repository root)
#
# Every persisted setting is declared once, as a SettingKey in Annotate/SettingsStore.swift,
# with its key string, default, and encoding. Raw UserDefaults access anywhere else lets a key
# string or default drift from that declaration.

set -euo pipefail

STORE="Annotate/SettingsStore.swift"

# Files allowed to touch UserDefaults directly, each for a stated reason.
ALLOWLIST=(
	"$STORE"                                 # The store itself.
	"AnnotateTests/TestHelpers.swift"        # Creates and tears down the per-process test suite.
	"AnnotateTests/SettingsStoreTests.swift" # Pins raw key strings and encodings users already have on disk.
)

PATTERNS=(
	'UserDefaults\.standard'
	'UserDefaults\(suiteName'
	'forKey: "'
	'\.(object|bool|string|double|float|integer|data|array|stringArray|dictionary|url|set|removeObject)\(.*forKey:'
)

pattern=$(
	IFS='|'
	echo "${PATTERNS[*]}"
)

violations=$(
	grep -rnE --include='*.swift' "$pattern" Annotate AnnotateTests |
		grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' |
		grep -vF -f <(printf '%s:\n' "${ALLOWLIST[@]}") ||
		true
)

if [ -n "$violations" ]; then
	echo "❌ UserDefaults accessed outside $STORE:" >&2
	echo "$violations" >&2
	echo "" >&2
	echo "Declare the setting as a SettingKey in $STORE and read or write it through" >&2
	echo "SettingsStore (settings[.key]). Use @AppStorage(.key) in SwiftUI views." >&2
	exit 1
fi

echo "✅ All UserDefaults access goes through $STORE"
