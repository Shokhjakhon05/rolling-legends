#!/usr/bin/env bash
# Renders a few frames for a visual check: tool/dev/shots.sh <outdir> <level:at> ...
set -e
out="$1"; shift
for spec in "$@"; do
  level="${spec%%:*}"; at="${spec##*:}"
  godot --path . --resolution 432x768 -- --shot=game:"$level" --at="$at" --out="$out/l${level}_${at}.png" 2>&1 | grep -E "saved|ERROR|SCRIPT" || true
done
