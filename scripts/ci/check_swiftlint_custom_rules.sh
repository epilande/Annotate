#!/bin/bash

# Check the custom rules in .swiftlint.yml against a fixture.
# Lines ending in `// expect: <rule>` must trigger that rule; no other line may.
# Usage: ./scripts/ci/check_swiftlint_custom_rules.sh (from the repo root, after
# `swift package plugin swiftlint` has downloaded the binary)

set -euo pipefail

FIXTURE="scripts/ci/swiftlint-fixtures/AnnotateTests/CustomRulesFixture.swift"
RULES=(observable_over_observable_object positional_layer_lookup real_updater_in_tests)

SWIFTLINT="${SWIFTLINT:-$(find .build/artifacts -path '*/macos/swiftlint' -type f 2>/dev/null | head -n 1)}"
if [ -z "$SWIFTLINT" ]; then
    echo "error: swiftlint binary not found; run 'swift package plugin swiftlint' first" >&2
    exit 1
fi

status=0
for rule in "${RULES[@]}"; do
    expected=$(grep -n "// expect: $rule\$" "$FIXTURE" | cut -d: -f1 | sort -n | tr '\n' ' ')
    # strict: true makes swiftlint exit non-zero on every hit, so ignore its status.
    actual=$("$SWIFTLINT" lint --quiet --config .swiftlint.yml --only-rule "$rule" "$FIXTURE" 2>/dev/null \
        | grep "($rule)\$" | cut -d: -f2 | sort -n | tr '\n' ' ' || true)

    if [ "$expected" = "$actual" ]; then
        echo "ok: $rule hits lines ${actual:-none}"
    else
        echo "error: $rule expected lines [${expected}] but hit [${actual}]" >&2
        status=1
    fi
done

exit $status
