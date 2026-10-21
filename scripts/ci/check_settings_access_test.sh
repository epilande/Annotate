#!/bin/bash

# Checks check_settings_access.sh against fixtures: raw UserDefaults access, and any @AppStorage or
# @SceneStorage whose key doesn't start with a dot (string literals, raw strings, constants), must
# fail outside the allowlist, and the typed @AppStorage(.key) forms must pass.
# Usage: ./scripts/ci/check_settings_access_test.sh (from anywhere)

set -euo pipefail

GUARD="$(cd "$(dirname "$0")" && pwd)/check_settings_access.sh"

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/Annotate" "$root/AnnotateTests"

failures=0

# Runs the guard in a tree holding only the given file and asserts on its exit status.
# Arguments: expected result (pass or fail), file path relative to the tree, file contents.
check() {
	local expected="$1" file="$2" contents="$3" output status
	rm -f "$root"/Annotate/*.swift "$root"/AnnotateTests/*.swift
	printf '%s\n' "$contents" >"$root/$file"

	if output=$(cd "$root" && "$GUARD" 2>&1); then
		status=pass
	else
		status=fail
	fi

	if [ "$status" != "$expected" ]; then
		echo "❌ expected $expected, got $status for $file:" >&2
		printf '    %s\n' "$contents" >&2
		echo "$output" | sed 's/^/    /' >&2
		failures=$((failures + 1))
	elif [ "$expected" = fail ] && ! grep -qF "$file:" <<<"$output"; then
		echo "❌ guard failed without naming $file:" >&2
		echo "$output" | sed 's/^/    /' >&2
		failures=$((failures + 1))
	fi
}

check fail Annotate/View.swift '@AppStorage("ToolbarVisible") var toolbarVisible = true'
check fail Annotate/View.swift '@AppStorage("ToolbarVisible", store: .standard) var toolbarVisible = true'
check fail Annotate/View.swift '@SceneStorage("SelectedTab") var selectedTab = ""'
check fail Annotate/View.swift 'let storage = AppStorage(wrappedValue: true, "ToolbarVisible")'
check fail Annotate/View.swift '@AppStorage(wrappedValue: "chalk", "SoundTheme") var soundTheme: String'
check fail Annotate/View.swift '@AppStorage(wrappedValue: 40.0, "TextFontSize") var textFontSize: Double'
check fail Annotate/View.swift '@AppStorage( "ToolbarVisible") var toolbarVisible = true'
check fail Annotate/View.swift '@AppStorage( wrappedValue: true, "ToolbarVisible") var toolbarVisible'
check fail Annotate/View.swift '@AppStorage(#"ToolbarVisible"#) var toolbarVisible = true'
check fail Annotate/View.swift '@SceneStorage(#"SelectedTab"#) var selectedTab = ""'
check fail Annotate/View.swift '@AppStorage(wrappedValue: "chalk", #"SoundTheme"#) var soundTheme: String'
check fail Annotate/View.swift '@AppStorage(Keys.toolbar) var toolbarVisible = true'
check fail Annotate/View.swift '@AppStorage(Keys.toolbar, store: .standard) var toolbarVisible = true'
check fail Annotate/View.swift '@SceneStorage(Keys.selectedTab) var selectedTab = ""'
check fail Annotate/View.swift 'let storage = AppStorage(Keys.toolbar)'
check fail Annotate/View.swift '@AppStorage(wrappedValue: true, Keys.toolbar) var toolbarVisible'
check fail Annotate/View.swift '@AppStorage(wrappedValue : true, "ToolbarVisible") var toolbarVisible'
check fail Annotate/View.swift '@AppStorage(wrappedValue:true,"ToolbarVisible") var toolbarVisible'
check fail Annotate/View.swift '@AppStorage(wrappedValue: Color(1, .red), "AccentColor") var accent'
check fail Annotate/View.swift 'let storage = AppStorage<Bool>("ToolbarVisible")'
check fail Annotate/View.swift 'let storage = AppStorage<Bool>(wrappedValue: true, "ToolbarVisible")'
check fail Annotate/View.swift 'let storage = AppStorage<Optional<String>>(Keys.name)'
check fail Annotate/View.swift '@AppStorage(.toolbarVisible) var a: Bool; @AppStorage("ToolbarVisible") var b = true'
check fail Annotate/Manager.swift 'let visible = UserDefaults.standard.bool(forKey: "ToolbarVisible")'
check fail AnnotateTests/ViewTests.swift '@AppStorage("ToolbarVisible") var toolbarVisible = true'

check pass Annotate/View.swift '@AppStorage(.toolbarVisible) var toolbarVisible: Bool'
check pass Annotate/View.swift 'let storage = AppStorage(.toolbarVisible, store: defaults)'
check pass Annotate/View.swift 'let visible = settings[.toolbarVisible]'
check pass Annotate/View.swift '@AppStorage(wrappedValue: "chalk", .soundTheme) var soundTheme: String'
check pass Annotate/View.swift '@AppStorage( .toolbarVisible) var toolbarVisible: Bool'
check pass Annotate/View.swift 'let storage = AppStorage<Bool>(.toolbarVisible)'
check pass Annotate/View.swift '@AppStorage(wrappedValue : "chalk", .soundTheme) var soundTheme: String'
check pass Annotate/View.swift '@AppStorage(wrappedValue: "a, b", .soundTheme) var soundTheme: String'
check pass Annotate/View.swift '@AppStorage(wrappedValue: [1, 2], .counts) var counts: [Int]'
check pass Annotate/View.swift '@AppStorage(.soundTheme) var soundTheme: SoundTheme; let label = "Sound"'
check pass Annotate/View.swift '@CloudAppStorage("ToolbarVisible") var toolbarVisible = true'
check pass Annotate/View.swift '// Not @AppStorage("ToolbarVisible"): comment lines are skipped.'
check pass Annotate/SettingsStore.swift 'self.init(wrappedValue: key.defaultValue, key.name, store: store)'
check pass Annotate/SettingsStore.swift 'let visible = UserDefaults.standard.bool(forKey: "ToolbarVisible")'
check pass Annotate/View.swift '@CloudAppStorage(Keys.toolbar) var toolbarVisible = true'
check pass Annotate/SettingsStore.swift '@AppStorage(Keys.toolbar) var toolbarVisible = true'
check pass AnnotateTests/TestHelpers.swift 'let defaults = UserDefaults(suiteName: name)'

if [ "$failures" -ne 0 ]; then
	echo "❌ $failures settings access guard fixture(s) failed" >&2
	exit 1
fi

echo "✅ Settings access guard catches raw UserDefaults and untyped @AppStorage/@SceneStorage keys"
