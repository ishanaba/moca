#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tracker="$project_root/build/dev/services/tracker/moca-tracker"
model="$project_root/models/yolo26n-pose_openvino_model/yolo26n-pose.xml"

if [[ ! -f "$model" ]]; then
  echo "Pose model not found at $model" >&2
  exit 1
fi

"$tracker" --source camera --device /dev/video0 --model "$model" \
  --inference-device "${MOCA_DEVICE:-GPU}" --serve &
tracker_pid=$!
trap 'kill "$tracker_pid" 2>/dev/null || true' EXIT INT TERM

for _attempt in $(seq 1 100); do
  if ss -ltn | grep -q ':8765 '; then
    break
  fi
  if ! kill -0 "$tracker_pid" 2>/dev/null; then
    wait "$tracker_pid"
    exit 1
  fi
  sleep 0.1
done

if ! ss -ltn | grep -q ':8765 '; then
  echo "Tracker did not open ws://127.0.0.1:8765" >&2
  exit 1
fi

if command -v godot >/dev/null 2>&1; then
  MOCA_LIVE=1 godot --path "$project_root/games/godot" -- --live
else
  flatpak run --env=MOCA_LIVE=1 org.godotengine.Godot --path "$project_root/games/godot" -- --live
fi
