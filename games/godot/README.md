# Godot client

This is the active lightweight desktop client. It targets Godot 4's Compatibility renderer and starts with simulated input, so camera and tracker hardware are not required during gameplay development.

## Run

```sh
godot --path games/godot --editor
godot --path games/godot
godot --path games/godot -- --replay
godot --path games/godot -- --replay=res://replays/demo.json
godot --path games/godot -- --live=ws://127.0.0.1:8765
```

Player 1 follows the mouse. Player 2 uses the arrow keys. Fruit awards 100 points, bombs remove 250 points without allowing a negative score, and Space restarts after the 60-second round.
Press F1 for simulated input, F2 for the bundled deterministic replay, or F3 for live tracking. Replay files contain timestamped, normalized player blade positions.

## Test

```sh
godot --headless --path games/godot --script res://tests/run_tests.gd
```

The next client step is replacing the simulated source with replay and live implementations behind `TrackingService`, followed by the C++ GDExtension Protobuf bridge.

## Native tracking bridge

`native/` contains the engine-independent decoder and the Godot 4.7.1 GDExtension wrapper. It decodes a serialized Protobuf v2 envelope, selects the stronger COCO-17 wrist for each person, and publishes only the newest complete snapshot. The extension is generated against `native/api/extension_api.json`, built into `bin/`, and exercised by the Godot smoke tests. `TrackingService` receives binary frames with `WebSocketPeer` and maps normalized wrist coordinates into the 1280×720 playfield.
