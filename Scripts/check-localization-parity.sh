#!/bin/sh
# Fails if Resources/en.lproj/Localizable.strings and
# Resources/pt-BR.lproj/Localizable.strings don't define the exact same set
# of keys. A key added to one and forgotten in the other fails silently at
# runtime (falls back to the raw key, or to English, for a real pt-BR user)
# instead of crashing anything a developer would notice locally — this is
# the one place that catches that before it ships.
set -eu

cd "$(dirname "$0")/.."

EN="Sources/ZeroServerControl/Resources/en.lproj/Localizable.strings"
PT="Sources/ZeroServerControl/Resources/pt-BR.lproj/Localizable.strings"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

# Matches lines of the form `"key" = "value";`, ignoring /* ... */ comment
# lines and blank lines — the only two other line shapes in these files.
extract_keys() {
  grep -oE '^"([^"]|\\.)*"[[:space:]]*=' "$1" | sed -E 's/^"//; s/"[[:space:]]*=$//'
}

extract_keys "$EN" | sort -u > "$SCRATCH/en.keys"
extract_keys "$PT" | sort -u > "$SCRATCH/pt.keys"

MISSING_IN_PT="$(comm -23 "$SCRATCH/en.keys" "$SCRATCH/pt.keys")"
MISSING_IN_EN="$(comm -13 "$SCRATCH/en.keys" "$SCRATCH/pt.keys")"

if [ -n "$MISSING_IN_PT" ] || [ -n "$MISSING_IN_EN" ]; then
  echo "Localizable.strings key mismatch between en.lproj and pt-BR.lproj:"
  if [ -n "$MISSING_IN_PT" ]; then
    echo "  Missing in pt-BR.lproj:"
    echo "$MISSING_IN_PT" | sed 's/^/    /'
  fi
  if [ -n "$MISSING_IN_EN" ]; then
    echo "  Missing in en.lproj:"
    echo "$MISSING_IN_EN" | sed 's/^/    /'
  fi
  exit 1
fi

KEY_COUNT="$(wc -l < "$SCRATCH/en.keys" | tr -d ' ')"
echo "Localizable.strings key parity OK ($KEY_COUNT keys)."
