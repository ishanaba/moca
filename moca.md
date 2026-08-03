# Motion Playground — Project Plan (rev. 2)


A multi-player motion gaming app in the spirit of Nex Playground, with a Fruit Ninja clone
as the flagship game — built on open-source models and used primarily as an instrument for
**evaluating what an Intel Arc laptop and current open-source pose models can actually do**.


> **Revision 2 changes:** multi-player is now a day-one requirement, and hardware/model
> evaluation is the top-priority goal. Both change the architecture materially. See
> [§1](#1-what-multi-player-changes) and [§2](#2-what-evaluation-first-changes).


---


## 0. Context


**Development machine:** MacBook Pro, Apple M3 Pro, 36 GB RAM, 18-core GPU, macOS 26.5.2,
Node 26, Python 3.14.


**Target machine:** Intel i7 laptop, 16 GB RAM, **Intel Arc graphics, Linux**.


**Goals, in the user's stated priority order:**


1. **Evaluate the laptop and the open-source model landscape.** The benchmark writeup is the
   real deliverable; the game is the test harness.
2. A Fruit Ninja clone supporting **two or more simultaneous players**.
3. A playground shell hosting multiple mini-games. (Reduced scope — see Phase 6.)


### Why Linux + Arc is the good case


- **MediaPipe's Python GPU delegate works on Linux** (0.10.8+). On Windows it raises
  `NotImplementedError` and Google recommends the JS API instead. Linux keeps Python viable.
- **OpenVINO 2026 fully supports Arc on Linux**, so RTMPose, RTMO, and the Open Model Zoo
  models run on the GPU. Arc's XMX matrix engines are a large step up from Iris Xe.
- If the chip is a Core Ultra rather than a classic i7, there is likely **also an NPU** as a
  third inference device. Confirmed in Phase 0.


---


## 1. What multi-player changes


This is the single largest revision, and it invalidates the obvious model choice.


### Hand Landmarker cannot be the primary tracker


Three independent reasons:


1. **No player identity.** MediaPipe reports hands with left/right handedness but no notion
   of *whose* hand it is. With two players it will happily report four hands and give you no
   way to attribute them.
2. **Designed for single-person scenarios.** The RTMPose authors state directly that
   BlazePose and MoveNet "are designed primarily for single-person or sparse scenarios."
   Recent multi-person benchmarking reaches the same conclusion.
3. **Physical geometry.** Two players side by side need roughly 2.5 m of standoff to fit in
   a typical 78° webcam FOV. At that distance a hand occupies too few pixels for reliable
   21-point landmarking, regardless of model quality.


### The replacement is simpler, not more complex


**Use multi-person pose estimation and take the wrist as the blade origin.** Fruit Ninja
needs a point that tracks your hand; it does not need finger articulation. This collapses
three problems into one model.


Published guidance maps cleanly onto this project:


- **RTMPose** (top-down) is the recommended choice for scenes with **up to four people**,
  which is exactly the target. RTMPose-s reaches 72.2% AP at 200+ FPS on an i7 CPU alone.
- **RTMO** (bottom-up) is preferred once scenes get crowded, and its cost is constant
  regardless of person count.
- Top-down cost scales with the number of people (one detector pass plus N crops); bottom-up
  does not. **Which one wins at 2–4 players is an empirical question — and answering it is
  precisely what this project is for.** Benchmark both.


MediaPipe is demoted to two supporting roles: **Hand Landmarker + Gesture Recognizer for
single-player menu navigation at close range**, and an in-browser single-player source that
lets you develop on the Mac without running the sidecar.


### New requirements multi-player introduces


- **Player identity tracking across frames.** Skeletons must keep stable IDs when players
  cross or briefly occlude each other. ByteTrack, or IoU plus Hungarian matching on keypoint
  centroids. **ID-switch rate becomes a benchmark metric.**
- **Per-player calibration.** Each player gets their own reach box, plus a spatial
  assignment (left half / right half of the camera frame) to seed identity.
- **Higher capture resolution.** Two people at 2.5 m means each is smaller in frame, pushing
  you toward 1280×720 — roughly 4× the pixels of 640×480. This is a real cost and a
  first-class benchmark axis.
- **Camera FOV becomes a hard constraint.** Verify in Phase 0 that two adults actually fit.


---


## 2. What evaluation-first changes


Since the benchmark is the deliverable rather than a byproduct:


- **The headless benchmark harness moves to Phase 1**, ahead of any game or UI work.
- **The game is instrumented as a live benchmark** (Phase 5): runtime model switching,
  session recording, and a stats overlay, so you can measure models under real gameplay load
  rather than only on canned footage.
- **The playground shell shrinks** to whatever is needed to launch and configure things.
- `docs/benchmarks.md` is the artifact the project is judged by.


---


## 3. Architecture


The Python sidecar is now the **primary and mandatory** tracker, not an optional lab bench.


```
┌──────────────────────────────────────────────────────────────┐
│ TRACKER SERVICE (Python, mandatory)                          │
│                                                              │
│  camera → backend → multi-person keypoints → ID tracker      │
│                                                              │
│  backends: RTMPose-t/s/m (OpenVINO)  ← primary candidates    │
│            RTMO (OpenVINO)                                   │
│            human-pose-estimation-0007 (OpenVINO)             │
│            YOLO11n/s-pose (OpenVINO / ONNX)                  │
│            MediaPipe Pose (Linux GPU delegate)               │
│                                                              │
│  devices: CPU · Arc GPU · NPU (if Core Ultra)                │
└───────────────────────────┬──────────────────────────────────┘
                            │  TrackingFrame over WebSocket
                            ▼
┌──────────────────────────────────────────────────────────────┐
│ INPUT LAYER (TypeScript)                                     │
│  per-player smoothing · per-player calibration               │
│  latency compensation · blade cursors · gestures             │
└───────────────────────────┬──────────────────────────────────┘
                            ▼
┌──────────────────────────────────────────────────────────────┐
│ GAME LAYER (Phaser 4)                                        │
│  fruit-ninja (multiplayer) · benchmark overlay · shell       │
└──────────────────────────────────────────────────────────────┘


  (dev-only side path: in-browser MediaPipe source, single player,
   so the Mac can run the game without the sidecar)
```


### The tracking protocol


Person-centric rather than hand-centric — the key structural change from rev. 1.


```ts
interface TrackingFrame {
  v: 2;
  tCapture: number;          // ms, monotonic, camera frame grab
  tInferEnd: number;
  source: string;            // "rtmpose-s@GPU" | "rtmo@NPU" | ...
  frame: { w: number; h: number };
  persons: Person[];
}


interface Person {
  id: number;                // stable across frames; assigned by the ID tracker
  score: number;
  keypoints: Keypoint[];     // COCO-17 or COCO-WholeBody, normalized 0..1,
                             //   origin top-left, already un-mirrored
  hands?: Hand[];            // optional, close-range single-player only
}


interface Keypoint { x: number; y: number; score: number }
```


Two rules that are easy to get wrong:


- **Coordinates are normalized and un-mirrored by the producer.** Never leave mirroring to
  the consumer.
- **Always render the newest frame; discard anything older. Never queue.** A buffered
  pipeline degrades into visible lag under load, which feels far worse than dropped frames.


### Repo layout


```
motion-playground/
├── services/tracker/            # Python — the heart of the project
│   ├── backends/                # one module per model, common interface
│   ├── tracking/                # ByteTrack / ID assignment
│   ├── server.py                # WebSocket
│   ├── bench.py                 # headless benchmark runner
│   └── capture/                 # reference footage recording tools
├── apps/web/                    # Vite + TypeScript + Phaser 4
│   └── src/
│       ├── tracking/            # TrackingSource iface, WebSocketSource,
│       │                        #   MediaPipeWorkerSource (dev only)
│       ├── input/               # OneEuroFilter, per-player calibration,
│       │                        #   PlaySpaceMapper, BladeCursor
│       ├── games/{shell,fruit-ninja}/
│       └── diagnostics/         # HUD, latency probe, live benchmark overlay
├── models/                      # .xml / .onnx / .task (gitignored)
└── docs/
    └── benchmarks.md            # ← the primary deliverable
```


---


## 4. Technology choices


### Where the models actually run


**All perception models run in one place: the Python tracker service, locally on the Linux
laptop.** No cloud, no network calls at inference time. The browser runs zero models in the
target configuration — it receives normalized keypoints over a localhost WebSocket and does
nothing but smooth, map, and render them.


```
┌─ Linux laptop (Intel i7 + Arc) ──────────────────────────────┐
│                                                              │
│  PROCESS A — Python tracker service   ← ALL MODELS RUN HERE  │
│    camera → pose model → ID tracker → WebSocket              │
│    device: Arc GPU via OpenVINO (CPU fallback, NPU if avail) │
│                                │                             │
│                                │ localhost WS, keypoints only│
│                                ▼                             │
│  PROCESS B — Browser / Phaser 4       ← NO MODELS            │
│    smoothing → calibration → rendering                       │
└──────────────────────────────────────────────────────────────┘
```


Process A owns the camera exclusively; Process B never opens it. **Only exception:** on the
M3 Mac during development, the browser may run MediaPipe on Metal via WebGL for a solo-player
path, so game code can be worked on without the sidecar. Development convenience only.


### Stack


| Layer | Choice | License | Why |
|---|---|---|---|
| Inference runtime | **OpenVINO 2026** | Apache 2.0 | Full Arc GPU + NPU support on Linux; Python 3.10–3.14 |
| Model library | **`rtmlib`** | Apache 2.0 | Runs the whole RTMPose family **without mmcv / mmpose / mmdet** — only numpy, opencv, onnxruntime. OpenVINO backend targets Arc directly; auto-downloads ONNX from the OpenMMLab zoo; `performance`/`lightweight`/`balanced` presets make the benchmark sweep nearly free; supports `mps` so the same code runs on the M3. **Removes the project's worst dependency risk.** |
| Primary models | **RTMPose / RTMO** | Apache 2.0 | Best accuracy-per-millisecond; recommended for ≤4 people and crowded scenes respectively |
| Player ID tracking | `supervision` (ByteTrack) | MIT | Stable IDs across crossings without a bespoke tracker |
| Capture | `opencv-python` | Apache 2.0 | V4L2 capture and preprocessing |
| Transport | `websockets` | BSD | Newest-frame-wins, no queueing |
| Env management | `uv`, Python 3.11/3.12 | MIT/Apache 2.0 | System 3.14 is too new for MediaPipe wheels |
| Game engine | **Phaser 4** | MIT | Stable since April 2026; rebuilt WebGL2 renderer. Phaser 3 is feature-frozen. Ships agent skill files in `skills/`. |
| Build tooling | Vite + TypeScript | MIT | Fast HMR; trivial Mac → Linux deploy |
| Close-range hands | MediaPipe Tasks, or RTMPose 21-kp hand | Apache 2.0 | Menu gestures. `rtmlib` also offers a 21-keypoint hand model, keeping everything in one family. |
| Desktop wrapper | Tauri | MIT/Apache 2.0 | Small binary, kiosk mode, Linux-friendly |


Two `rtmlib` features worth exploiting: the **21-keypoint hand model** (an alternative to
MediaPipe for gestures) and the **`PoseTracker` solution**, which runs the person detector
only every N frames — a large speedup for the top-down RTMPose path and a parameter worth
sweeping in Phase 1.


### Models under evaluation


| Model | License | Multi-person | Role |
|---|---|---|---|
| **RTMPose-t / -s / -m** | Apache 2.0 | Top-down | **Primary candidate.** 68.5 / 72.2 / 75.8 AP at 300+ / 200+ / 90+ FPS on i7 CPU alone |
| **RTMO** | Apache 2.0 | Bottom-up | **Primary candidate.** Constant cost vs. person count; best under occlusion |
| **YOLO26-pose** | **AGPL-3.0** | Bottom-up | **Primary candidate (added rev. 3).** NMS-free → *predictable* latency; RLE keypoint localization; reported to hold through wide arm swings. See §6.2. Home use only. |
| YOLO11n/s-pose | **AGPL-3.0** | Bottom-up | Superseded by YOLO26-pose; keep only as a regression baseline |
| `human-pose-estimation-0007` | Apache 2.0 | Yes | Intel-tuned reference for the Arc comparison |
| MediaPipe Pose Landmarker | Apache 2.0 | Weak | Reference point; expected to degrade with 2+ people |
| MoveNet MultiPose | Apache 2.0 | Up to 6 | Speed floor; lowest accuracy |
| MediaPipe Hand + Gesture | Apache 2.0 | No | Close-range menu navigation only |
| ~~OpenPose~~ | Non-commercial | — | **Skip.** ~10 FPS and a restrictive license |


---


## 5. Phases


### Phase 0 — Environment and physical-setup spike (half a day)


Prove the hardware and the room before writing code.


1. **Identify the chip.** `lscpu`, `lspci | grep -i vga`. Classic i7 with discrete Arc, or
   Core Ultra with integrated Arc plus an NPU?
2. **Intel compute runtime:** `intel-opencl-icd`, `intel-level-zero-gpu`, `level-zero`,
   `ocl-icd-libopencl1`. Kernel ≥ 6.2 recommended for Arc.
3. **Confirm OpenVINO devices:**
   `python -c "import openvino; print(openvino.Core().available_devices)"` →
   expect `['CPU','GPU']`, plus `'NPU'` on Core Ultra.
4. **Camera capability:** `v4l2-ctl --list-formats-ext`. Need MJPG at **1280×720@30**
   for multi-player, not just 640×480. Many webcams collapse to 5–10 FPS at higher
   resolutions — no GPU rescues you from a slow sensor.
   **Also determine shutter type.** Assume rolling unless the spec sheet says otherwise.
   Quick test: film a fast horizontal hand swing and look for a skewed/leaning forearm — that
   is rolling-shutter distortion, and it is unfixable in software (§6.1).
   Then check exposure control: `v4l2-ctl -d /dev/video0 --list-ctrls` should expose
   `auto_exposure` and `exposure_time_absolute`. **Locking a short exposure is the cheapest
   fast-motion improvement available**, so verify it's controllable before anything else.
5. **Physical setup test — and the camera FOV maths.** Usable width is
   `2 × distance × tan(FOV/2)`. Benchmarked against Nex Playground's published 6 ft (1.83 m)
   play distance:


   | Camera FOV | Usable width at 1.83 m | Supports |
   |---|---|---|
   | 78° (typical webcam) | ~2.9 m | **2 players** with arms extended (~2 m needed) |
   | 100°+ (wide-angle) | ~4.4 m+ | **4 players** (~4 m needed) |


   **A standard webcam hard-caps you at two players.** Nex solves this with an ultra
   wide-angle lens, and matching their four-player count requires the same. Decide before
   buying hardware.


   **Caveat:** wide-angle lenses introduce barrel distortion that skews keypoints toward the
   frame edges. Budget for `cv2.calibrateCamera` and undistortion **before** inference —
   this is a required step, not a refinement.
6. **Browser acceleration:** `chrome://gpu` reports hardware-accelerated WebGL2.


**Exit criteria:** OpenVINO enumerates GPU (and NPU if present); camera does 1280×720@30
MJPG; two players verifiably fit in frame at a comfortable distance.


---


### Phase 1 — Benchmark harness (the primary deliverable)


Headless, reproducible, before any game code exists.


**Record reference footage on the target machine, in the target room.** Live-camera
benchmarking is not reproducible. Capture a matrix of clips:


- 1, 2, 3, and 4 people in frame
- Distances of roughly 1.5 m, 2.5 m, 3.5 m
- Bright, normal, and dim lighting
- **Fast arm swings at full slicing speed** — the single most important clip, since this is
  the exact motion the game depends on and the known weak point (§6, §7)
- Players crossing paths, to stress ID tracking
- **Exposure sweep on the fast-swing clip:** auto-exposure versus short locked exposure. This
  isolates how much of the fast-motion error is photographic rather than model-related, and
  it is the cheapest fix available.
- **If a mono global-shutter camera is in play:** the same fast-swing clip in grayscale, to
  test whether RGB-trained models tolerate replicated-channel input (§6.1)


**Measure, per model × device × resolution × person-count:**


| Metric | Why it matters |
|---|---|
| FPS, and **p50 / p95 latency** | Means hide the stutters that ruin game feel |
| CPU %, GPU % (`intel_gpu_top`), RAM | The actual "can this laptop do it" answer |
| **Power draw** (RAPL / `powerstat`) | Laptop thermals throttle; sustained ≠ burst |
| **Keypoint jitter on a static subject** | Predicts game feel better than COCO AP does |
| **Detection dropout rate** | Frames where a present player isn't found |
| **ID-switch rate** | New in rev. 2; decides whether multi-player is viable at all |
| **FPS vs. person count slope** | The top-down/bottom-up crossover — the headline result |


Run every model on CPU, Arc GPU, and NPU where supported.


**Exit criteria:** `docs/benchmarks.md` populated with a defensible recommendation for which
model and device to ship, the top-down/bottom-up crossover identified, and — since the
supported player count is being decided empirically — **the person count at which latency or
ID stability stops being playable.** That number becomes the game's supported ceiling, so
nothing downstream may hardcode an assumption of two players.


---


### Phase 2 — Tracking service


- **Pin Python 3.11 or 3.12 via `uv`.** Not the system 3.14 — MediaPipe has no wheels for
  it. Applies on both machines.
- Wrap the winning backends behind one interface; keep at least two switchable at runtime.
- **Player ID tracking:** ByteTrack or IoU + Hungarian on keypoint centroids. Seed identity
  from initial spatial position (left/right).
- WebSocket server emitting `TrackingFrame` v2, newest-frame-wins with no queueing.
- Graceful degradation: when a player is lost, hold their ID for ~1 s before releasing it.


**Exit criteria:** two people move in front of the camera and keep stable, correct IDs
through a crossing.


---


### Phase 3 — Input layer (where game feel is won or lost)


Do not skip to the game. None of this is a model problem.


- **One Euro filter per keypoint per player.** Start `mincutoff ≈ 1.0`, `beta ≈ 0.007`,
  `dcutoff ≈ 1.0`, then tune. A moving average is the obvious alternative and it is wrong:
  it trades jitter for lag uniformly, while One Euro adapts to hand speed and gives you a
  still cursor at rest *and* a responsive one in motion.
- **Per-player reach calibration.** Each player traces a rectangle with an extended arm for
  ~5 s; store the bounding box of their real reach and map it to their screen region with a
  ~10% inset. This is the highest-leverage item in the project — mapping raw camera
  coordinates to the screen makes the corners physically unreachable, and it is the main
  thing separating a hobby demo from something that feels like a product. With children and
  adults playing together, per-player calibration stops being optional.
- **Latency compensation.** Measure mean end-to-end latency `L`; extrapolate the blade by
  `velocity × L`, clamped so it doesn't overshoot on direction reversals.
- **Rate decoupling.** Tracker at ~30 Hz, render at 60. Interpolate between the last two
  samples, then extrapolate.
- **Blade source:** wrist keypoint, optionally extended along the elbow→wrist vector to
  approximate the hand.
- **Tracking loss:** fade the blade over ~300 ms rather than snapping it away.


**Exit criteria:** two people dragging blades around an empty screen both feel 1:1, with no
jitter at rest and no identity swapping.


---


### Phase 4 — Fruit Ninja, multiplayer


- **Screen model:** shared screen, colour-coded blades per player, with each player's
  calibrated reach box mapped to their own half. Shared beats split-screen for fun and for
  rendering simplicity, and it makes stolen fruit a feature.
- **Spawner:** ballistic launches from below, apexing inside the union of the active play
  areas. Balance so each player gets comparable opportunities.
- **Slice detection:** per player, a ring buffer of the last ~8 blade samples with
  timestamps. Each frame, form segments from consecutive samples and test
  segment-versus-circle against every fruit. **Gate on blade speed** (start near 800 px/s):
  the speed gate is what makes it read as *slicing* rather than *touching*.
- **Slice response:** cut angle from the segment direction; split the sprite into halves with
  opposing normal velocity and spin. Then the juice — particle burst, persistent splatter
  decal, ~40 ms freeze on combos, subtle screen shake.
- **Scoring: both versus and co-op**, selectable. Versus keeps per-player scores and combo
  multipliers separate; co-op pools them against a shared target, with a combo bonus when
  players slice the same wave. Co-op is what makes an adult and a child playable together,
  so it is not a stretch goal.
- **Bombs** end the run for whoever sliced them. Distinct silhouette, audio cue on spawn, and
  drawn slightly larger than their hitbox so near-misses feel generous.
- **Audio is not optional.** Removing sound from a slicing game removes most of the feedback
  loop.


**Exit criteria:** two people play a full round and it is genuinely fun.


---


### Phase 5 — Live benchmark instrumentation


Elevated in rev. 2, because canned footage doesn't capture real load.


- Runtime model and device switching from within the game.
- Stats overlay: current model, FPS, p50/p95 latency, per-player tracking confidence.
- Session recording: dump raw frames plus tracking output so a session can be replayed
  offline against a different model.
- A/B mode: run two backends on alternating frames and compare them on identical input.


**Exit criteria:** you can answer "does RTMPose-s actually feel better than RTMO during a
two-player round?" with data rather than impressions.


---


### Phase 6 — Minimal shell (reduced scope)


Deliberately small, given the evaluation priority.


- Player registration and calibration flow for 2+ players.
- Dwell-based selection (~1.2 s with a radial progress ring) — far more reliable than pinch
  or push gestures, which false-fire constantly.
- Settings: model, device, resolution, difficulty, mirror.
- **One** additional mini-game, only to prove the input abstraction generalizes. If it needs
  changes to the input layer, the abstraction was wrong.


---


### Phase 7 — Packaging and writeup


- Tauri kiosk wrapper; systemd user unit for the tracker service; sleep inhibition.
- Finish `docs/benchmarks.md`. **This is the deliverable.** Include the person-count scaling
  curves, the device comparison, the sustained-versus-burst thermal story, and a clear
  recommendation.


---


## 6. Fast-motion capture stack


The game's core motion is a fast arm swing, which is the weakest point for COCO-trained
open models (see §7). Research conclusion: **the largest single win is at the sensor, not
the model**, and the layers below compound.


| Layer | Mechanism |
|---|---|
| **Sensor** | Global shutter, short locked exposure, more room light, 60+ fps |
| **Model** | YOLO26-pose / RTMO / RTMPose, benchmarked on a fast-swing clip |
| **Interpolation** | Lucas-Kanade wrist tracking at camera rate between inferences |
| **Fusion** | Kalman filter, weighting optical flow above model output short-term |
| **Prediction** | Velocity extrapolation by measured latency (Phase 3) |


### 6.1 Global shutter — the highest-leverage hardware change


A rolling-shutter sensor exposes row by row, so during a fast swing the top and bottom of
the frame are captured at different instants and **the limb is geometrically skewed, not
merely blurred**. No model can invert this: the input depicts a shape that never existed. A
global shutter exposes all pixels simultaneously, so the frame is a single instant at any
speed. A 2026 multimodal SLAM benchmark found global shutter produced the lowest tracking
error across *every* framework tested, with rolling-shutter configurations suffering
"catastrophic tracking divergence" under rapid motion.


**Costs, which are real:** per-pixel storage circuitry shrinks the photodiode, so
global-shutter sensors are less sensitive and noisier. Maximum exposure is the frame period
*minus* full readout, so a longer exposure cannot compensate. **More room light is
required** — which aligns with the short-exposure strategy anyway.


**Monochrome option:** many affordable global-shutter USB cameras are mono, and losing the
Bayer filter recovers much of the sensitivity. Pose models are RGB-trained, so replicated
grayscale input must be **benchmarked, not assumed** — cheap test, potentially large payoff.


**Combined with the wide-angle requirement from §7, the target camera is: wide-angle, global
shutter, 60+ fps, possibly mono.** This is the highest-leverage purchase in the project.


### 6.2 YOLO26-pose — new primary candidate


Announced September 2025; directly relevant on two counts:


- **NMS-free end-to-end inference** gives *predictable* latency rather than latency varying
  with scene content. For motion control this matters more than raw speed, because jitter in
  latency invalidates the extrapolation constant in Phase 3.
- **Residual Log-Likelihood Estimation** for keypoint localization.


Reported to track "through wide arm swings and rapid orientation changes without dropping
detections" on fast rhythmic movement — the exact target motion. Nano variant ~1.8 ms/frame
on a T4; exports to ONNX and OpenVINO. **AGPL-3.0** — fine at home, not shippable.


### 6.3 Decoupling tracking rate from model rate


Run full pose inference at a decimated rate; track **only the wrists** at camera rate with
pyramidal Lucas-Kanade (`cv2.calcOpticalFlowPyrLK`), fusing both via a Kalman filter.
Published implementations run the model every ~10 frames with flow between, and weight the
**flow measurement as more trustworthy short-term** than the model output. Use a
forward-backward consistency check to reject bad tracks.


This decouples blade update rate from model throughput — precisely what a slicing game
wants. **Caveat:** optical flow itself degrades under motion blur, so this compounds with
§6.1 rather than substituting for it.


### 6.4 Evaluated and rejected


- **SmoothNet** (ECCV 2022) looks ideal — plug-and-play temporal refinement, any backbone,
  improves exactly the "challenging frames" we care about. **Rejected for the game loop:**
  pretrained models use a 32-frame sliding window, roughly one second of latency at 30 fps.
  The authors call it "near-online," and a Sept 2025 user report says online-mode quality is
  poor. **Retained for one offline use:** generating better pseudo-ground-truth to score the
  real-time models in Phase 1.
- **WildPose** (CVPR 2026) and **Unblur-SLAM** — surface prominently when searching this
  space and genuinely concern motion blur, but "pose" there means *camera trajectory*
  (SLAM), not human keypoints. Not applicable.


---


## 7. Reference point: what Nex Playground actually runs


Researched to calibrate expectations. **Their motion engine is fully proprietary** — Play OS
is a closed system, no third-party software, no public OSS attribution page. The only
confirmed open-source component is **AOSP**, which Play OS is built on. Their game engine is
**Unity** (proprietary), exposed to developers via the Nex Motion Developer Kit plugin.


The published hardware specs proved more useful than a library list:


| | Nex Playground |
|---|---|
| SoC | Amlogic A311D2-N0D, 12 nm, 8-core ARM (4×A73 + 4×A53) |
| NPU | **3.2 TOPS** |
| GPU | Mali-G52 MP8, ~326 GFLOPS FP32 |
| Keypoints | **18 body nodes** (COCO-18 / OpenPose convention) |
| Players | **Up to 4 concurrent** |
| Camera | Built-in **ultra wide-angle** |
| Play distance | **~6 feet** |
| Inference | Fully on-device, offline capable |


**What this establishes:**


1. **Feasibility is not in question.** Four-player real-time tracking runs on a 3.2 TOPS NPU
   in a 12 nm set-top-box SoC. The Arc target has roughly an order of magnitude more
   inference capability. The design question is how to spend the surplus, not whether it
   fits.
2. **Keypoint parity.** Their 18 nodes are COCO-17 plus a neck point, and neck is the
   midpoint of the shoulders. RTMPose's COCO-17 output is equivalent — derive the neck.
3. **Camera FOV is the binding hardware constraint** (see Phase 0 step 5).
4. **Architecture converges.** Their MDK abstracts tracking behind a plugin boundary so game
   developers never touch the model — the same split as this plan's `TrackingSource`.
5. **Their real advantage is training data, not architecture.** Nex states they tuned their
   engine for "speed, complex movements... that other engines just weren't trained to
   handle." Open models are trained largely on COCO, which is mostly static photography, so
   **fast arm swings are where this project will be weakest** — unfortunate for a slicing
   game.


   **Mitigation is mostly photographic, not architectural.** Motion blur is what breaks
   keypoint detection on fast limbs. Lock a short exposure via `v4l2-ctl` and add room light
   rather than letting the camera auto-expose to 1/30 s. Prefer RTMPose `body7` checkpoints,
   trained across seven merged datasets rather than COCO alone. **Add a fast-motion
   condition to the Phase 1 benchmark matrix** — measure keypoint dropout during a full-speed
   arm swing, since that is the exact motion the game depends on.


### Component mapping


| Nex component | This project's equivalent |
|---|---|
| Proprietary Nex Motion Engine | RTMPose / RTMO via `rtmlib` |
| 3.2 TOPS Amlogic NPU | Intel Arc GPU via OpenVINO |
| Unity + MDK plugin | Phaser 4 + `TrackingSource` interface |
| Play OS (AOSP) | Linux + Tauri kiosk wrapper |
| Ultra wide-angle camera | Wide-angle USB webcam + OpenCV undistortion |
| Active-player auto-detection | ByteTrack via `supervision` |


---


## 8. Risks


| Risk | Mitigation |
|---|---|
| **Two players don't physically fit in the camera FOV** at a workable distance. | Phase 0 step 5, before anything else. Budget for a wide-FOV camera. |
| **The webcam caps frame rate, not the GPU.** A 30 FPS sensor makes Arc irrelevant. | `v4l2-ctl --list-formats-ext` in Phase 0. Consider a 60 FPS camera. |
| **1280×720 for multi-player is ~4× the pixels of 640×480** and may blow the latency budget. | Resolution is a benchmark axis in Phase 1; decide from data. |
| ID switching when players cross makes multi-player unplayable. | ID-switch rate is a Phase 1 metric; ByteTrack in Phase 2; spatial seeding. |
| Top-down RTMPose degrades as players are added. | Benchmark RTMO head to head; the crossover is a headline result, not a surprise. |
| Laptop thermal throttling — burst numbers won't hold. | Measure sustained draw and clocks over 10+ minutes, not 30 seconds. |
| Lighting degrades detection more than any other environmental factor. | Lock exposure via `v4l2-ctl`; benchmark a dim-light condition explicitly. |
| **Motion blur and rolling-shutter skew on fast arm swings** — COCO-trained open models are weakest at exactly the motion this game depends on. This is Nex's main advantage. | The full §6 stack: global-shutter sensor, short locked exposure, more light, YOLO26-pose, optical-flow interpolation, Kalman fusion. Skew in particular is **unfixable in software** — it must be solved at the sensor. |
| Barrel distortion from a wide-angle lens skews edge keypoints. | `cv2.calibrateCamera` + undistort before inference; required, not optional. |
| Arm fatigue; motion games are more tiring than they look while designing. | 60–90 second rounds; comfortable play-box height. |
| Scope creep into the shell. | Phase 6 is deliberately last and deliberately small. |


---


## 9. Open decisions


- ~~Maximum player count~~ — **decided: determined empirically.** Phase 1 measures where
  tracking quality and latency stop being playable, and that number becomes the supported
  ceiling. Design for N players; do not hardcode 2 anywhere.
- ~~Versus, co-op, or both~~ — **decided: both.** Mixed-ability households need the choice.
- **Does the target machine have an NPU?** Resolved in Phase 0; if yes it becomes a third
  benchmark device.
- **Camera hardware — now the most consequential purchase decision.** Three requirements
  point the same way: wide-angle (for 3–4 players, §7), **global shutter** (for fast-motion
  fidelity, §6.1), and 60+ fps. Mono is worth considering for light sensitivity if the
  grayscale benchmark passes. The built-in webcam almost certainly satisfies none of these.
  Resolve after Phase 0 measures the actual gap.




