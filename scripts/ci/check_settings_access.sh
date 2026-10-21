#!/bin/bash

# Fail when code reads or writes UserDefaults outside the typed settings store.
# Usage: ./scripts/ci/check_settings_access.sh (from the repository root)
#
# Every persisted setting is declared once, as a SettingKey in Annotate/SettingsStore.swift,
# with its key string, default, and encoding. Raw UserDefaults access anywhere else lets a key
# string or default drift from that declaration. Outside the allowlist below, the guard fails on:
#
#   - UserDefaults.standard, UserDefaults(suiteName:, any forKey: "literal", and the UserDefaults
#     getters and setters listed in USER_DEFAULTS_PATTERNS called with forKey:.
#   - Any @AppStorage or @SceneStorage, including the AppStorage(...) and AppStorage<T>(...)
#     initializer forms, whose key argument does not start with a dot. The key is the first
#     argument, or the second after a leading wrappedValue: argument. That fails string literals,
#     raw strings, and constants such as Keys.toolbar, and passes only the typed
#     @AppStorage(.key) form from SettingsStore.swift. The leading boundary keeps
#     CloudAppStorage( and similar names out.
#
# The checks are line-based regexes, not a Swift parser. Known limits:
#
#   - Multi-line calls pass: @AppStorage( on one line and "Key") on the next is not seen.
#   - Comments: lines that start with // are skipped, even inside a multiline string, while lines
#     inside a /* */ block comment, or a trailing // comment after code, are checked.
#   - Non-literal keys: UserDefaults or KVC calls outside the listed methods, such as
#     value(forKey: name) or setValue(x, forKey: name), pass when the key is not a string literal.
#   - A wrappedValue: default with brackets nested two deep, such as f(g(1), 2), is not parsed, so
#     the line fails even when the key is typed.
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

USER_DEFAULTS_PATTERNS=(
	'UserDefaults\.standard'
	'UserDefaults\(suiteName'
	'forKey: "'
	'\.(object|bool|string|double|float|integer|data|array|stringArray|dictionary|url|set|removeObject)\(.*forKey:'
)

# @AppStorage(, @SceneStorage(, AppStorage(, and AppStorage<T>(.
WRAPPER='((^|[^[:alnum:]_])(AppStorage|SceneStorage)(<[^()]*>)?)\('

# A leading wrappedValue: argument up to its comma. The default may hold string literals and
# brackets one level deep, so a comma inside "a, b", f(a, b), or [a, b] doesn't end it.
WRAPPED_VALUE='[[:space:]]*wrappedValue[[:space:]]*:([^]["(),]|"([^"\\]|\\.)*"|\([^()]*\)|\[[^][]*\])*,'

# After the wrappedValue: argument is removed, a key argument that doesn't start with a dot.
UNTYPED_KEY="$WRAPPER[[:space:]]*[^.[:space:]]"

pattern=$(
	IFS='|'
	echo "${USER_DEFAULTS_PATTERNS[*]}"
)

violations=$(
	{
		grep -rnE --include='*.swift' "$pattern" Annotate AnnotateTests || true
		# Drop each wrappedValue: argument, then print the original line if any key is untyped.
		grep -rnE --include='*.swift' "$WRAPPER" Annotate AnnotateTests |
			sed -nE -e 'h' -e "s/$WRAPPER$WRAPPED_VALUE/\\1(/g" -e "/$UNTYPED_KEY/{" -e 'g' -e 'p' -e '}' ||
			true
	} |
		awk '!seen[$0]++' |
		grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' |
		grep -vF -f <(printf '%s:\n' "${ALLOWLIST[@]}") ||
		true
)

if [ -n "$violations" ]; then
	echo "❌ UserDefaults or an untyped @AppStorage/@SceneStorage key used outside $STORE:" >&2
	echo "$violations" >&2
	echo "" >&2
	echo "Declare the setting as a SettingKey in $STORE and read or write it through" >&2
	echo "SettingsStore (settings[.key]). In SwiftUI views, use the typed initializer," >&2
	echo "@AppStorage(.key), never a string or constant key such as @AppStorage(\"Key\")." >&2
	echo "@SceneStorage has no typed initializer, so declare the value as a SettingKey and" >&2
	echo "bind it with the typed AppStorage initializer, @AppStorage(.key), instead." >&2
	exit 1
fi

echo "✅ All UserDefaults access and @AppStorage/@SceneStorage property wrappers go through $STORE"
