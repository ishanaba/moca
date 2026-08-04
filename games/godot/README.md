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
catch seeds, pop falling magic balls with a pointed wand, and finally guide a
butterfly through multiple mazes during a guided three-minute session. Caught seeds animate into the
flower bed, and the UI counts flowers planted and butterflies fed. During the
final stage, magic balls fall toward planted flowers: wand pops protect the
garden, while a missed ball visibly spoils and removes one flower. Planting,
popping, and damage play synthesized effects. Space starts, ends, or restarts
the session; the on-screen button pauses, R restarts, and Escape exits. Run the camera experience from the repository root with `make
magic-garden-live`.

Two seeds remain available so both hands can scoop them independently. The
butterfly stage renders wind streaks aligned with each hand's current movement,
and the magic-ball stage
renders only pointed wands; only the moving pointed tip pops a ball. Tracking
loss keeps its on-screen warning but does not stop the session countdown.
Flowers planted, butterflies fed, and the timer share a top-right statistics
panel. Activity instructions are narrated as a short story instead of being
shown as text; the tracking warning remains on the left when hands disappear.
The closing celebration plays a bright chord and rains rotating, colorful
flowers across the live camera view for fifteen seconds.

The butterfly remains centered inside a narrow maze above the flower bed. Up/down,
side-to-side, and diagonal hand movement advances only through a corridor with
the same direction; mismatched movement stops it. A yellow arrow shows the
direction required for the current section. Three different mazes run in
sequence. Their longer routes do not cross themselves, and each final corridor enters one of the flowers actually planted
during the seed stage.

## Test

```sh
godot --headless --path games/godot --script res://tests/run_tests.gd
```

## Native tracking bridge

`native/` contains the engine-independent decoder and Godot GDExtension. It
exposes stable hand, person, and side metadata. `TrackingService` receives
camera JPEGs and tracking snapshots over WebSocket, mirrors them into the
1280×720 AR playfield, and publishes only the newest complete values.
