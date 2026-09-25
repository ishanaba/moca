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

### Magic Garden Rescue

The active Godot client is a 45-second AR movement game for
one child. A mirrored live camera view is overlaid with seeds, falling magic
balls, final-stage sequential butterfly mazes, and a growing procedural garden. The UI
counts flowers planted and butterflies fed. Caught seeds animate into the bed;
unblocked magic balls spoil and remove flowers, while wand pops protect them.
Procedural sounds provide immediate feedback. Planting and magic-ball defense
last 45 seconds each, while butterfly guidance lasts 75 seconds. YOLO26n-pose supplies two stable
wrist inputs and swept-path collision catches fast touches. Tracking loss keeps
its warning visible without pausing the session timer.

Each activity begins with an English story narration through the local Speech
Dispatcher. Activity prompt text is hidden; statistics and the tracking warning
remain visible. Butterfly wind streaks rotate with the child's actual hand
movement direction.

Run it with `make magic-garden-live 1`, `make magic-garden-live 2`, or
`make magic-garden-live 3` to select easy, normal, or hard difficulty. Level 2
is used when no level is given. Mouse simulation and the bundled two-hand
replay support development without a camera. The previous table-tennis
controller remains in `games/godot/scripts/main.gd` and on its checkpoint branch.

### 3D table tennis prototype

The `feature/mediapipe-table-tennis-3d` branch replaces the 2D target game with
a Jolt Physics 3D table-tennis prototype. The active game uses YOLO26n-pose's
wrist estimate to drive a depth-constrained `AnimatableBody3D` racket;
MediaPipe Hand Landmarker is not loaded. The ball is a continuous-collision
`RigidBody3D`. Run it with `make table-tennis-live`.

The player-side racket mesh is hidden: the highlighted YOLO wrist is the racket.
Because a single camera cannot measure forward motion, covering an incoming
ball with the wrist collider creates forward contact toward the computer.
Measured wrist speed and screen-space direction are added to that contact, so
quick sideways and upward hand movements steer and accelerate the return.

Ball/table restitution is intentionally lossy, the net has very low bounce,
and a rally watchdog resets balls that stall near mid-table for more than one
second or remain in play for more than fifteen seconds.

The rally state tracks the last hitter and receiver-side bounces. Wrong-side
bounces, volleys before the required bounce, and double-bounces award a foul;
net contacts are called out on screen. Both player and computer returns use
controlled table-tennis arcs rather than accumulating raw collision energy.
Returns clear the net before their first bounce, and that first rebound is
bounded to a playable height so the computer does not create repeated low
double-bounces. The computer leads incoming shots to their projected baseline
crossing instead of chasing the ball's current position, giving it time to make
a natural return after the legal first bounce. It never volleys: its collider
activates only after that bounce, and the simple opponent completes its return
after a short reaction delay and always before a second bounce. Computer serves vary their starting
position, lateral angle, height, and speed within a safe envelope that clears
the net and lands comfortably inside the player's half.

Horizontal wrist movement is the sole positional control and spans the table
width; racket height and depth stay fixed for stability. The overlay highlights
the wrist at the end of the YOLO arm chain as the playable contact area.
The game locks onto one YOLO wrist until it disappears, preventing racket jumps
when a second wrist briefly enters the camera.

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
