#!/bin/bash

# Fail when code reads or writes UserDefaults outside the typed settings store.
# Usage: ./scripts/ci/check_settings_access.sh (from the repository root)
#
# Every persisted setting is declared once, as a SettingKey in Annotate/SettingsStore.swift,
# with its key string, default, and encoding. Raw UserDefaults access anywhere else lets a key
# string or default drift from that declaration. That includes SwiftUI's @AppStorage and
# @SceneStorage with a string key: only the typed @AppStorage(.key) form is allowed.
#
# The patterns are line-based regexes, not a Swift parser. They miss a call split across lines,
# such as @AppStorage( on one line and "Key") on the next, and they skip any line that starts
# with //, even inside a multiline string. A string literal later on the same line, such as
# foo(AppStorage(wrappedValue: x, .key), "label"), is a false positive.
#
# scripts/ci/check_settings_access_test.sh checks this script against fixtures.

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
	# @AppStorage("Key"), @SceneStorage( #"Key"#), and AppStorage(wrappedValue: "chalk", "Key").
	# The typed form, @AppStorage(.key), has no string literal after the paren. The default may
	# hold string literals; the leading boundary keeps CloudAppStorage( and similar names out.
	'(^|[^[:alnum:]_])(AppStorage|SceneStorage)\([[:space:]]*(wrappedValue:([^"]|"([^"\\]|\\.)*")*,[[:space:]]*)?#*"'
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
	echo "❌ UserDefaults or a string-keyed property wrapper used outside $STORE:" >&2
	echo "$violations" >&2
	echo "" >&2
	echo "Declare the setting as a SettingKey in $STORE and read or write it through" >&2
	echo "SettingsStore (settings[.key]). Use @AppStorage(.key) in SwiftUI views, never" >&2
	echo "@AppStorage(\"Key\"). @SceneStorage has no typed form, so declare the value as a" >&2
	echo "SettingKey and bind it with @AppStorage(.key) instead." >&2
	exit 1
fi

echo "✅ All UserDefaults access goes through $STORE"
