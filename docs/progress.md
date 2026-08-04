# Progress

Updated: 2026-08-03

## Complete

- [x] Modular monorepo layout for tracker and Godot client.
- [x] Separate Docker images and root Compose configuration.
- [x] Exact `/dev/video0` GStreamer smoke-test command documented.
- [x] TrackingFrame v2 schema, generated C++ protocol types, and native decoder validation.
- [x] Deterministic replay and live WebSocket source with newest-frame delivery.
- [x] Identity retention/spatial seeding, One Euro filtering, calibration, prediction, loss fade, and segment-circle collision primitives.
- [x] Playable two-player versus/co-op vertical slice with pointer controls for development.
- [x] Unit/contract test foundations and deterministic benchmark report generation.

## Requires the Arc laptop/camera

- [ ] Record OS/kernel, OpenVINO CPU/GPU/NPU devices, driver versions, V4L2 formats/exposure, shutter behavior, and Godot Compatibility renderer support.
- [ ] Verify two-player framing and 1280×720 MJPG at 30 FPS.
- [ ] Capture and annotate the complete evaluation footage matrix.
- [x] Export YOLO26n-pose FP16 and implement its OpenVINO C++ adapter.
- [ ] Run ten-minute benchmark cases and select a shipping configuration.
- [ ] Perform physical two-player acceptance. No hardware result is claimed yet.

## Next — Godot client

- [x] Scaffold a Godot 4 project under `games/godot` using the Compatibility renderer.
- [x] Add a tested native decoder that maps Protobuf v2 envelopes to newest-only wrist snapshots.
- [x] Add a C++ GDExtension that consumes Protobuf v2 payloads and provides newest-only snapshots.
- [x] Connect camera capture and YOLO26n-pose OpenVINO inference through WebSocket to Godot live input.
- [ ] Port calibration and filtering from the existing vertical slice; blades, collisions, scoring, and round flow are now implemented.
- [x] Add deterministic replay with a bundled two-player fixture and runtime simulation/replay switching.
- [x] Run the headless smoke tests and a clean replay startup with Godot 4.7.1.
- [ ] Document and validate Linux export commands.
