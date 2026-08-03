# Benchmarks

Status: **not measured on target hardware**.

The repository includes a deterministic report pipeline, but no synthetic result is presented as hardware evidence. A shipping backend will only be selected if it sustains at least 30 updates/s, p95 capture-to-result latency at most 80 ms, normal-light dropout below 5%, and zero ID switches in the annotated crossing clip.
# Smoke observations

These are short development checks, not accepted benchmark results.

- YOLO26n-pose FP16, 640×640, OpenVINO 2026.2.1, Arc `GPU.0`: 69.23 FPS model-only over two benchmark iterations.
- The camera → GPU inference → Protobuf/WebSocket → headless Godot path remained healthy for eight seconds and reported a visible person. No physical latency, ID-switch, or sustained-performance claim is made from this smoke run.

