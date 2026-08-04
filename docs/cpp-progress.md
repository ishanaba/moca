# C++ implementation progress

Updated: 2026-08-03

- [x] CMake workspace and module directories.
- [x] Protobuf v2 frame/negotiation/error/heartbeat envelope.
- [x] C++ newest-value primitive and identity retention.
- [x] Native core tests; compiled and passed with GCC 13.3.
- [x] Tracker replay-mode executable skeleton.
- [x] Python-only model export/manifest tool.
- [x] Separate tracker and model-tool containers.
- [x] Bounded GStreamer appsink capture with newest-frame dropping.
- [x] OpenVINO YOLO26n-pose inference adapter with CPU/GPU selection.
- [x] Binary Protobuf WebSocket transport and deterministic replay publication.
- [x] Scaffold the Godot 4 project with Compatibility rendering and simulated two-player input.
- [x] Add and test the native Protobuf v2-to-newest-snapshot bridge core.
- [x] Add the C++ GDExtension Protobuf/newest-snapshot boundary for Godot 4.7.1.
- [x] Godot Protobuf decoding, newest-frame handoff, WebSocket ingestion, and wrist input mapping.
- [x] Implement a playable Godot round with fruit, bombs, scoring, collision sweeps, and replay.
- [x] Validate the Godot project, replay startup, and smoke tests with Godot 4.7.1.
- [ ] Arc hardware benchmarks.

CMake discovers Protobuf and OpenVINO, generates the v2 C++ types, and the native CMake/CTest suite passes. Godot 4.7.1 is installed through Flatpak; the pinned `godot-cpp` binding is built against its generated API, engine smoke tests pass, and the live camera path starts without script errors. Python `pytest` remains unavailable, though the model-tool manifest smoke test passes directly.
