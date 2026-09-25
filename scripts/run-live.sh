#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tracker="$project_root/build/dev/services/tracker/moca-tracker"
model="$project_root/models/yolo26n-pose_openvino_model/yolo26n-pose.xml"
difficulty="${1:-2}"

if [[ ! "$difficulty" =~ ^[123]$ ]]; then
  echo "Difficulty must be 1, 2, or 3" >&2
  exit 2
fi

if [[ ! -f "$model" ]]; then
  echo "Pose model not found at $model" >&2
  exit 1
fi

camera="${MOCA_CAMERA:-/dev/video0}"
# A loopback camera can return one stale frame even when its producer is stuck.
# Require several frames before opening the game or loading the pose model.
if ! "$tracker" --source camera --device "$camera" --hand-tracker none --frames 3; then
  echo "Camera $camera is not delivering frames; the game was not started." >&2
  echo "Check the camera privacy switch and close other camera apps." >&2
  if [[ -r "/sys/class/video4linux/${camera##*/}/name" ]] &&
      [[ "$(<"/sys/class/video4linux/${camera##*/}/name")" == "Intel MIPI Camera" ]]; then
    echo "Check the Intel camera relay: journalctl -u v4l2-relayd@default.service -n 30" >&2
    echo "To restart it: sudo systemctl restart v4l2-relayd@default.service" >&2
  fi
  exit 1
fi

tracker_args=(--source camera --device "$camera" --model "$model"
  --inference-device "${MOCA_DEVICE:-GPU}" --hand-tracker "${MOCA_HAND_TRACKER:-wrist}" --serve)
if [[ "${MOCA_HAND_TRACKER:-wrist}" == "mediapipe" ]]; then
  tracker_args+=(--hand-model "${MOCA_HAND_MODEL:?MOCA_HAND_MODEL is required}"
    --mediapipe-library "${MOCA_MEDIAPIPE_LIBRARY:?MOCA_MEDIAPIPE_LIBRARY is required}"
    --mediapipe-delegate "${MOCA_MEDIAPIPE_DELEGATE:-GPU}")
fi
"$tracker" "${tracker_args[@]}" &
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
  MOCA_LIVE=1 godot --path "$project_root/games/godot" -- --live "--difficulty=$difficulty"
else
  flatpak run --env=MOCA_LIVE=1 org.godotengine.Godot --path "$project_root/games/godot" -- --live "--difficulty=$difficulty"
fi
