#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
python3 "$ROOT/tools/configure_android_template.py"
mkdir -p "$ROOT/godot/build"
"$GODOT_BIN" --headless --path "$ROOT/godot" --export-debug Android "$ROOT/godot/build/rooftop-rivals-campaign-preview.apk"
