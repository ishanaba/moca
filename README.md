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
- `games/unreal/Plugins/MocaTracking`: paused Unreal prototype retained for reference.

See [implementation plan](docs/implementation-plan.md) and [progress](docs/progress.md).
