#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
temporary="$(mktemp -d)"
trap 'rm -f "$temporary/export-reference"; rmdir "$temporary"' EXIT
xcrun swiftc -O -o "$temporary/export-reference" \
  Tools/GodotReference/main.swift \
  NeonRacer/Content/*.swift \
  NeonRacer/Game/Simulation/*.swift \
  NeonRacer/Services/Persistence/*.swift \
  NeonRacer/Shared/Accessibility/AccessibilitySettings.swift \
  NeonRacer/Shared/Design/AccessiblePalette.swift
"$temporary/export-reference" Godot/assets/swift-reference.json
