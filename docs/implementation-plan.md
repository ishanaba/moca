# Implementation plan

## Milestone 1 — runnable vertical slice

- Establish separate tracker, protocol, input, and game modules.
- Define `TrackingFrame` v2 schema and generated C++ protocol types.
- Provide replay and WebSocket sources, newest-frame semantics, filtering, calibration, and blade trails.
- Deliver a complete versus/co-op round with fruit, bombs, scoring, results, and replay.
- Package the tracker and Godot client for local deployment.

## Milestone 1.5 — Godot client pivot

- Use Godot 4 with the Compatibility renderer and a 2D-first presentation so development does not depend on an 8 GB GPU.
- Create `games/godot` with a small autoloaded tracking service, connection status UI, and deterministic replay mode.
- Reuse the Protobuf v2 contract through a lightweight C++ GDExtension; decode and publish only the newest complete tracking snapshot to the Godot main thread.
- Port calibration, filtering, prediction, loss fade, blade trails, and collision behavior from the existing vertical slice before adding new gameplay.
- Deliver one complete local versus/co-op round in Godot with keyboard/mouse simulation when no camera or tracker is available.
- Add headless smoke tests for protocol fixtures and core gameplay rules, then document editor/export steps for Linux.

## Milestone 2 — hardware and evidence gate

- Run the documented GStreamer and `v4l2-ctl` checks on `/dev/video0`.
- Confirm 1280×720 MJPG at 30 FPS, exposure controls, field of view, Arc device enumeration, drivers, and Godot Compatibility renderer startup.
- Record the required lighting, movement, occlusion, and exposure clips with manifests and annotations.
- Calibrate wide-angle optics and configure undistortion.

## Milestone 3 — model adapters and benchmark

- Install/export RTMPose-t/s/m, RTMO, and YOLO26n-pose model assets.
- Implement each adapter behind the common backend interface and normalize to COCO-17.
- Sweep device, resolution, detector cadence, exposure, and participant count.
- Run accepted cases for ten minutes after warm-up and generate `docs/benchmarks.md`.
- Stop before claiming physical acceptance unless one setup meets all latency, FPS, dropout, and ID-switch gates.

## Milestone 4 — physical acceptance

- Validate two-player calibration, crossing stability, jitter, fast swings, fair spawning, audio, bombs, and sustained 60 FPS rendering in the Godot client.
- Enable optical-flow fusion only if the measured benchmark meets its improvement/cost gate.
