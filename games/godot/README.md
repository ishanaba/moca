# Godot client

This is the active Magic Garden Rescue AR client. It targets Godot 4's
Compatibility renderer and starts with mouse-simulated hand input, so camera
and tracker hardware are not required during gameplay development.

## Run

```sh
godot --path games/godot --editor
godot --path games/godot
godot --path games/godot -- --replay
godot --path games/godot -- --replay=res://replays/demo.json
godot --path games/godot -- --live=ws://127.0.0.1:8765
```

The child sees a mirrored live camera feed and uses either YOLO-tracked wrist to
catch seeds, guide a butterfly through a maze, and pop bubbles with a pointed
magic wand during a guided three-minute session. Caught seeds animate into the
flower bed, planting and popping play synthesized effects, and stars grow a
procedural garden. Missed targets carry no penalty. Space pauses, R restarts,
and Escape exits. Run the camera experience from the repository root with
`make magic-garden-live`.

The butterfly remains centered inside a maze above the flower bed. Up/down,
side-to-side, and diagonal hand movement advances only through a corridor with
the same direction; mismatched movement stops it. A yellow arrow shows the
direction required for the current section.

## Test

```sh
godot --headless --path games/godot --script res://tests/run_tests.gd
```

## Native tracking bridge

`native/` contains the engine-independent decoder and Godot GDExtension. It
exposes stable hand, person, and side metadata. `TrackingService` receives
camera JPEGs and tracking snapshots over WebSocket, mirrors them into the
1280×720 AR playfield, and publishes only the newest complete values.
