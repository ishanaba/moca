#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
runtime="$project_root/models/mediapipe/libmediapipe.so"
hand_model="$project_root/models/mediapipe/hand_landmarker.task"

if [[ ! -f "$runtime" || ! -f "$hand_model" ]]; then
  echo "MediaPipe assets are missing; run 'make mediapipe-setup' first" >&2
  exit 1
fi

tracker="$project_root/build/dev/services/tracker/moca-tracker"
"$tracker" --source camera --device "${MOCA_CAMERA:-/dev/video0}" --hand-only \
  --hand-tracker mediapipe --hand-model "$hand_model" --mediapipe-library "$runtime" \
  --mediapipe-delegate "${MOCA_MEDIAPIPE_DELEGATE:-GPU}" --serve &
tracker_pid=$!
trap 'kill "$tracker_pid" 2>/dev/null || true' EXIT INT TERM

for _attempt in $(seq 1 100); do
  ss -ltn | grep -q ':8765 ' && break
  kill -0 "$tracker_pid" 2>/dev/null || { wait "$tracker_pid"; exit 1; }
  sleep 0.1
done
ss -ltn | grep -q ':8765 ' || { echo "Tracker did not open ws://127.0.0.1:8765" >&2; exit 1; }

if command -v godot >/dev/null 2>&1; then
  MOCA_LIVE=1 godot --path "$project_root/games/godot" -- --live
else
  MOCA_LIVE=1 flatpak run org.godotengine.Godot --path "$project_root/games/godot" -- --live
fi
