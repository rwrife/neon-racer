#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$(pwd)"
godot="${GODOT:-godot}"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

run() {
  "$godot" "$@" 2>&1 | tee "$log"
  if grep -Eq 'SCRIPT ERROR:|ERROR:' "$log"; then
    echo "Godot reported an error even though its process may have returned success." >&2
    exit 1
  fi
}

run --headless --path Godot --editor --import
run --headless --path Godot --script res://tests/run_tests.gd
run --headless --path Godot --script res://tests/smoke_ui.gd
mkdir -p Godot/exports/ios
run --headless --path Godot --export-pack iOS exports/ios/NeonRacerGodot.pck
run --headless --main-pack "$root/Godot/exports/ios/NeonRacerGodot.pck" \
  --script "$root/Godot/tests/smoke_ui.gd"
