# C++ implementation plan

1. Finalize Protobuf v2 and deterministic replay.
2. Add bounded GStreamer capture with newest-frame semantics.
3. Add asynchronous FP16 OpenVINO inference and device validation.
4. Add stable multi-person identity tracking and telemetry.
5. Build a lightweight Godot 4 GDExtension that decodes Protobuf off the main thread and exposes newest-only tracking snapshots.
6. Add filtering, calibration, prediction, blades, and the playable Godot round using the Compatibility renderer.
7. Benchmark and physically validate on the Arc laptop.

Python remains restricted to model acquisition, YOLO export, conversion, quantization, and validation.
