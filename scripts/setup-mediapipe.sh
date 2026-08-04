#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
destination="$project_root/models/mediapipe"
wheel_name="mediapipe-0.10.35-py3-none-manylinux_2_28_x86_64.whl"
wheel_sha256="db9a579df48cffe9570cd3e93f6a5d2dd089a1103b846c60c5b5de8a21c38db0"
model_sha256="fbc2a30080c3c557093b5ddfc334698132eb341044ccee322ccf8bcf3607cde1"
model_url="https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task"

mkdir -p "$destination"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

python3 -m pip download --no-deps --only-binary=:all: --platform manylinux_2_28_x86_64 \
  --python-version 3 --implementation py --abi none mediapipe==0.10.35 -d "$temporary"
curl -fL --retry 3 -o "$temporary/hand_landmarker.task" "$model_url"
printf '%s  %s\n' "$wheel_sha256" "$temporary/$wheel_name" | sha256sum --check
printf '%s  %s\n' "$model_sha256" "$temporary/hand_landmarker.task" | sha256sum --check

python3 -m zipfile -e "$temporary/$wheel_name" "$temporary/wheel"
cp "$temporary/wheel/mediapipe/tasks/c/libmediapipe.so" "$destination/libmediapipe.so"
cp "$temporary/hand_landmarker.task" "$destination/hand_landmarker.task"

echo "MediaPipe runtime and Hand Landmarker model installed in $destination"
