# Motion Playground

C++20/OpenVINO multi-person tracking service with a Protobuf v2 contract and a lightweight Godot 4 desktop client. Python is restricted to offline model preparation.

## Camera smoke test

```sh
gst-launch-1.0 v4l2src device=/dev/video0 ! videoconvert ! autovideosink
```

## Native core

```sh
cmake --preset dev
cmake --build --preset dev
ctest --preset dev
./build/dev/services/tracker/moca-tracker --source replay
```

## Live motion game

With the exported `models/yolo26n-pose_openvino_model/yolo26n-pose.xml` asset present:

```sh
make live
```

This starts `/dev/video0` capture, YOLO26n-pose inference on the Arc GPU, stable identity assignment, binary Protobuf v2 publication on `ws://127.0.0.1:8765`, and the Godot client in live mode. Set `MOCA_DEVICE=CPU make live` for CPU fallback. Inside the game, F1 selects simulation, F2 replay, and F3 live tracking.

Hand tracking is a replaceable tracker-service backend. The default
`--hand-tracker wrist` backend estimates the hand center from body-pose wrists;
`--hand-tracker none` disables it. Dedicated MediaPipe or RTMPose backends can
implement `moca::HandTracker` and publish palm centers plus optional landmarks
without changing the game client or wire transport.

### MediaPipe Hand Landmarker experiment

The optional `mediapipe` backend runs Google's MediaPipe Hand Landmarker on
each camera frame, publishes all 21 landmarks, and associates each detected
hand one-to-one with the closest YOLO body-pose wrist. Only identified hands
are sent to gameplay: YOLO supplies the stable player identity and MediaPipe
supplies the hand/wrist position. The default remains `wrist`, so the original
path is unchanged.

The game pointer uses the MediaPipe palm centroid rather than the wrist. A
target scores only when the palm overlaps it while at least three fingers are
detected as curled into a grip; an open hand can move the pointer but cannot
collect a target. When MediaPipe loses the hand, its pointer disappears and
cannot collide or score until the hand is detected again.

```sh
make mediapipe-setup  # downloads pinned MediaPipe 0.10.35 + float16 task model
make mediapipe-live
```

On the `experiment/mediapipe-hand-only` branch, `make mediapipe-live` does not
load or run YOLO. MediaPipe detects hands directly and uses handedness for the
left/right pointer IDs. The preserved `feature/yolo-mediapipe-hybrid` branch
contains the YOLO identity association version.

MediaPipe uses its GPU delegate by default in `make mediapipe-live`; set
`MOCA_MEDIAPIPE_DELEGATE=CPU` to compare its CPU path. `MOCA_DEVICE` separately
controls the YOLO pose device. To fall back, use `make live`, or switch back to
`main`. The downloaded runtime and model live under the gitignored
`models/mediapipe/` directory.

### 3D table tennis prototype

The `feature/mediapipe-table-tennis-3d` branch replaces the 2D target game with
a Jolt Physics 3D table-tennis prototype. The MediaPipe palm drives a
depth-constrained `AnimatableBody3D` racket; grip state enables its collider.
The ball is a continuous-collision `RigidBody3D`. This single-camera mapping is
isolated in `table_tennis_rules.gd` so calibrated stereo depth can replace it
without changing the physics scene.

If Protobuf is installed, CMake generates C++ protocol types. Without it, the dependency-free core and tests still build.

## Containers

```sh
docker compose -f deployments/compose/docker-compose.yml up --build
```

The tracker container receives `/dev/video0` and `/dev/dri`. Godot runs natively and will connect to the tracker through a C++ GDExtension once transport is implemented.

## Modules

- `protocol`: canonical Protobuf definitions and fixtures.
- `services/tracker`: capture, inference, identity tracking, and transport.
- `tools/models`: Python-only model export and metadata tooling.
- `games/godot`: active Godot 4 client with simulation, replay, and live tracking modes.

See [implementation plan](docs/implementation-plan.md) and [progress](docs/progress.md).
