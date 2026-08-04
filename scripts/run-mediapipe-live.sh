#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
runtime="$project_root/models/mediapipe/libmediapipe.so"
hand_model="$project_root/models/mediapipe/hand_landmarker.task"

if [[ ! -f "$runtime" || ! -f "$hand_model" ]]; then
  echo "MediaPipe assets are missing; run 'make mediapipe-setup' first" >&2
  exit 1
fi

MOCA_HAND_TRACKER=mediapipe \
MOCA_HAND_MODEL="$hand_model" \
MOCA_MEDIAPIPE_LIBRARY="$runtime" \
  "$project_root/scripts/run-live.sh"
