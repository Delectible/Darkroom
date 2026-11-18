# Darkroom change log

Running list of requested changes and when each one landed.

**How to read it**

- `[ ]` planned · `[~]` in progress · `[x]` done · `[-]` dropped
- Done items end with `→ version · date · commit`.
- Item numbers (e.g. **3.2**) stay fixed, so you can say "do 3.2 next".
- New requests go at the bottom of the current revision, or into a new
  revision section.

---

Finished items live in `docs/CHANGELOG-archive.md`.

## Revision v0.2 (requested 2026-10-06)

Ships as app version **1.3.x**, one patch number per batch:
A = 1.3.0 (quick fixes), B = 1.3.1 (pipeline, Polaroid, zoom),
C1 = 1.3.2 (Win98, reels, landscape, feedback), C2 = 1.3.3 (mode switch,
darkroom, corkboard, ambience).

### 1. Carousel & navigation


### 0. Feedback on 1.3.1 (build 13)



### 2. Photo & video previews (film & digital)

- [ ] **2.5 Share sheet preview:** sharing a video on Android shows only the
  file name. Pass a thumbnail to the share sheet.
  Tried in 1.3.0 (build 11): a provider that serves a first-frame thumbnail.
  The owner confirmed the sheet still shows no thumbnail. Low priority; revisit.

### 3. Camera UI & viewfinder

- [~] **3.1 Mode transition:** replace the Film ↔ Digital fade with a large
  slide: the whole camera slides off and the other slides in. Possibly add a
  "swap device" sound. Remove the slider switch and add another obvious
  control for swapping. *Build a demo first for approval.* → 1.3.3 · 2026-10-06 · 3cd4a8f (build 15)
  Demo: the other camera peeks in from the screen edge; tap or pull it in and the bodies slide past each other with a swap sound. Tell me if you like it.
  Feedback on build 15: wants real physicality (tossing one camera aside, grabbing
  the other, seeing the rest of the body pass by). Brainstorming before rebuilding.
  Chosen: thumb toss + real camera body. Rebuilt: drag the body sideways (it
  follows the thumb, tips away in perspective) and flick or drag far enough
  to toss it; the other body comes in on the same motion and settles with a
  spring. Each body runs past the screen: rounded end, side wall with strap
  lug, neck strap (film) / wrist cord (digital). Tap the peek still works.
  → 1.3.6 · 2026-10-06 · 41bebd1 (build 21, first private-key build)

### 4. Windows 98 mode & darkroom


### 5. Performance & general


### 6. New feature: Polaroid camera (Film mode)


### 7. New stock / camera pipeline


### 8. Look quality (requested 2026-10-06)

- [~] **8.1 Film and digital looks:** the looks don't yet behave like the real
  formats and can read as a cheap filter. Plan to iterate (see chat): reference
  contact sheets per look, an on-phone tuning screen, then fixes per stock.
  - [x] Ektar 100 against the owner's 5 reference scans: azure skies (not navy),
    warm true reds, golden yellows, deep greens, deep slightly warm blacks,
    clean highlights, less halation. → 1.3.8 · 2026-10-06 · c9b7554 (build 23)
  - [x] Grain rebuilt for every stock: real grain structure (crisp, clumpy,
    mostly luminance) instead of soft blurred noise; strength sets amount and
    size (weak barely there, strong obviously film). Ektar Normal matches the
    scans. → 1.3.8 · 2026-10-06 · c9b7554 (build 23)
  - [x] Portra 400 against the owner's 5 reference scans, as the stock that reads
    most obviously as film: green-teal shadows, warm cream highlights, soft
    contrast, peachy skin, visible grain matched to the scans.
    → 1.3.9 · 2026-10-06 · 1c9e691 (build 24)
  - [x] HP5 400 against the owner's 4 reference scans: neutral, deep blacks,
    stronger contrast, crisp heavy grain that builds toward the highlights
    (as B&W negatives do), grey (not orange) glow round lamps.
    → 1.3.10 · 2026-10-06 · 286ae6f (build 25)
  - [x] Polaroid 600 against the owner's 5 reference scans: washed-out cream
    highlights (never white), navy-teal shadows, very compressed colour;
    frequent instant-film flaws (sparkles, roller streaks, a ragged
    undeveloped edge, a fogged corner); the frame everywhere in the app is
    now off-white with an embossed texture instead of flat white.
    → 1.3.11 · 2026-10-06 · a085f1e (build 26)
  - [x] Super 8 against the owner's 4 reference scans: always landscape (a
    landscape slice when the phone is upright); reels are full-gate scans
    with the sprocket hole on the left and slivers of the neighbouring frames,
    in the viewfinder too (rotates with the phone); faded colour (lifted
    blacks, soft highlights, olive mids), soft focus, clearly visible
    flicker, more dust / hairs / scratches and the odd warm flare.
    → 1.3.12 · 2026-10-06 · 667a263 (build 27)
  - [ ] The digital bodies: waiting on reference photos.

### 9. Distribution (requested 2026-10-06)

- [~] **9.2 Proper signing + Play Store:** a private upload key (GitHub
  secrets) replaces the public test key; CI also builds an .aab for the Play
  Console internal testing track, so installs come from Play with no
  warning. Signing → 2026-10-06 · cc84d67 (secrets added; first private-key
  build is the next push). Play Console waits on the owner's ID check; later, CI
  uploads each build to Play by itself.

### 10. Requested 2026-10-06 (after build 27)


### 11. Requested 2026-10-06 (after build 31)


### 12. Requested 2026-10-07 (after build 38)


### 13. Requested 2026-10-07 (after build 39)


### 14. Requested 2026-10-07 (after build 40)


### 15. Requested 2026-10-07 (after build 41)


## 18. Darkroom close-up, quieter, settings, tape audio (2026-10-07)

- [-] **18.6 Logo eyes:** blue X on the left, red X on the right (opposite
  their fringe colours). Sample sent; Owner: keep the old logo for now.

## 20. Big batch: Win98 swipe, crash reports, close-up, volume (2026-10-07)

Answers: 3D buttons pre-rendered; crash reports on the phone only; Win98
comes in with a CRT power-on; start screen also asks for a name; Win98
swipe is LEFT in digital mode (right still swaps to film).


## 21. Real 3D shutters, monitor slide, profile, battery (2026-10-08)

Answers: turntable renders, no 2D/3D switch.


## 23. CRT switch-off, steady LCD, SD Empty, 3D shutters on (2026-10-08)

- Monetization: parked until the app is further along (owner).
  → 21.1, 23.1-23.4: 1.4.1 · 2026-10-08 · 562cea4

## 24. Polish toward a public release (2026-10-08)

- [ ] **24.3 3D buttons** "pretty bogus": answered (cost of full 3D);
  decision pending, tracked in docs/RELEASE.md.

## 26. 3D controls, debug window, steady still (2026-10-08)

- [~] **26.1 3D controls** (24.3 decided: worth it; the live preview read as
  "budget", so a path-traced film body is being tried:
  `tool/render/items/filmback.js`, first test render lost its textures;
  parked for 27): every control (shutter,
  flash, zoom, flip, gallery) a 3D object turning with the body; body stays
  2D. First a live three.js preview page to tune the look
  (`tool/preview3d/index.html`, published as an artifact), then renders.

## 29. 1.5 on-device fixes (2026-10-08)

- [ ] **29.9 More 3D depth**: options shown (taller parts, stronger tilt,
  deeper shadows); parked for now.

## 47. Before production (2026-10-15)

12 closed testers opted in by 2026-10-14; production access can be applied
for from 2026-10-28 (reminder set for 2026-10-29).

- [~] **47.1 Monetization**: built in 1.7.0 (48.x); Play product still to create
- [ ] **47.2 Bug fixes and cleanup**
- [ ] **47.3 Store page**: finish the listing, take new screenshots
- [ ] **47.6 Google's publishing info**: the Play Console forms needed to
  publish (App content, production access questionnaire)

## 56. Skins, tablets, low graphics (2026-10-22)

- [ ] **56.7** Tablet swap frame rate: needs the tablet's model and a
  Performance Recorder report.
- [~] **56.11** Landing in landscape (Darkroom 98, corkboard): the page
  flickered upright for a frame as the app really turned. Android's
  jump-cut showed the last portrait frame turned; now seamless rotation.
  To confirm on the Pixel.
- [~] **56.12** Smoother: Android asks for the screen's fastest refresh
  rate (MainActivity `preferredDisplayModeId`; it ran at 60 Hz on the 90/120
  Hz Pixel); performance mode (Fancy graphics off) asks for 60 Hz
  (channel `darkroom/display`). To confirm on the Pixel.

## 57. Stocks (2026-10-25)

- [ ] **57.3** Owner tunes the new looks on the phone.
- [ ] **57.4** Owner fine-tunes the current film stocks (Vivid, Portrait,
  Classic, Instant, Super 8).
- [ ] **57.5** Real artwork for the new stocks and cameras (placeholders now
  reuse existing renders): 3 canisters, a disposable, a 70mm can, webcam,
  DSLR, toy cam, MiniDV camcorder.

## 58. Ideas after 2.0 (2026-11-02)

- [ ] **58.1 Request the film from the lab** (Pro only): every print belongs to
  its roll; in the print viewer "Request film from lab" offers:
  - **One strip:** the 6 frames of the roll's quarter the print is in
    (1-6, 7-12, 13-18, 19-24).
  - **The whole roll:** all 24 frames on a contact sheet (rows of strips,
    the photos keeping their shape; more practical than one long strip).
  Either as **negatives** (inverted, orange mask for colour, frame numbers
  and edge print along the rebate) or as the **corrected scan** (the prints
  as developed). Comes back as one image, made for sharing.
  - 35 mm first. Instant: not a roll, so something else, maybe a collage
    of the pack (could overlap a built-in collage feature, 58.2: decide
    together). Video stocks (Super 8, Epic 70): to figure out later.
- [ ] **58.2 Collage** (idea): a built-in collage of prints; may cover the
  instant-pack case of 58.1.
- [ ] **58.3 More camera settings** (idea): aperture / manual controls where
  the phone allows; pick a specific lens on multi-camera phones.
- [ ] **58.4 Fish-eye lens attachment** (idea).
- [ ] **58.5 Digital camera effects** (idea): filters and other in-camera
  effects of the era.
- [ ] **58.6 Double exposure** (idea) and other physical film camera tricks.

## 59. Smoothness and memory (2026-11-04)

- [x] **59.1** → 2.0.7 · Swap hiccup: the 3D model drew a frame behind its keys
  (parts reported while painting, after the model). `LiveBody.syncParts`
  reads every `LivePart` right before the model paints (`_SyncParts`).
- [x] **59.2** → 2.0.7 · RAM: `DeviceMemory` (channel `darkroom/device`) sizes
  prints developing at once (≤3.2 GB: 1, ≤4.5: 2, ≤6.5: 3, else cores/2 ≤ 4)
  and the image cache (40 / 64 / 100 MB). RAM shown in Debug > Development Stats.
- [x] **59.3** → 2.0.7 · 3D textures: `slim_glb.py` (run by bundle_live.py)
  splits each body into a base (one skin, body maps 2048, 9 maps), `_hd`
  (dropped later, 59.8) and
  `_skin_<k>` swatches (base colour + only the maps that differ). The app
  swaps a swatch's textures onto the one set of finish panels
  (`LiveBody.wear`) and releases each scene template after loading.
  Measured (desktop preview): film 96 MB hd / 48 MB normal, was ~208 MB.
  Download: 3D packages 61 → 43.5 MB.
- [x] **59.4** → 2.0.7 · Print viewer decodes at the screen's long edge;
  full size only for the print in view while zoomed (4096 cap on low RAM).
- [x] **59.5** → 2.0.7 · Low RAM (≤ 3.2 GB) is chosen for automatically:
  halation off, 60 Hz, 3D adaptive render quality (min 0.5) and ≤ 1080 px
  wide, studio light built at 512. Debug > Memory Report.
- [x] **59.6** → 2.0.7 · Six long, untimed sounds ship as AAC (.m4a): sfx 2.0 →
  1.1 MB. The slowest phones (≤ 2.2 GB, or ≤ 3.2 GB with ≤ 4 cores:
  `DeviceMemory.lowest`) start their first run with Fancy graphics off and a
  note after the tour (`PrefKeys.lowGraphicsNote`); Settings' Fancy graphics
  says effects are reduced on low-RAM phones.
- [x] **59.8** → 2.0.7 · Sharp (4096) body maps dropped after a side-by-side at
  Pixel size (only brushed-metal streaks a touch crisper): the `_hd`
  files are gone (3D packages ~34.6 MB). Screens >= 1100 px draw the 3D
  body at 90% (`renderScale`; labels and controls are on top, full
  sharpness). Artwork re-saved at 800 px (1.46 → 0.86 MB).
- [x] **59.9** → 2.0.7 · Low-RAM 3D quality is steered by our own `BodyQuality`
  (Flutter Scene's adaptive mode judged frame periods, so at 60 Hz it could
  never step back up): during swaps, 30-frame windows of build/raster time;
  6+ frames over 16.7 ms = 15% step down (then 2 windows' pause), no late
  frame and mean < 10 ms = 15% step up. Floor 60%, and never under 648 px
  wide. FLIP and the format dial's label soften with the body (`_soft`,
  a paint mask blur: no layer, keeps the OnTop lift).
- [x] **59.10** → 2.0.7 · Debug > Performance > 3D Quality Stats (`BodyQuality.report`:
  screen, normal / lowest / current draw width, time and frame times at
  each level, swaps, every step); steps marked in the Performance
  Recorder, a summary line in its report (`PerfRecorder.extras`).
- [ ] **59.7** Not done: a patched 3D loader skipping mip 0 (two-size files
  do the same), drawn cameras by default for existing low-end installs.


## 60. Smoothness, part two (2026-11-04)

- [x] **60.1** → 2.0.8 · Debug window: a long tool description scrolls
  (Win98 scrollbar; starts at the top for each pick).
- [x] **60.2** → 2.0.8 · Pixel 9 Pro sat near 60 Hz: the display mode alone
  doesn't hold an adaptive (LTPO) screen up. MainActivity now also sets
  `preferredRefreshRate`, votes the rate on Flutter's SurfaceView
  (`Surface.setFrameRate`, CHANGE_FRAME_RATE_ALWAYS, again when the surface
  is made) and, on Android 15+, asks every view for the HIGH frame-rate
  category (NORMAL in performance mode / low RAM). Performance Report: "slow"
  is now UI or GPU over budget (the old total span counted frames that were
  only late, not dropped), and each activity shows its real fps.
- [x] **60.3** → 2.0.8 · Keys jittering on the body mid-swipe: Flutter Scene
  re-showed the last body frame whenever one frame of GPU work was still
  running (`maxGpuFramesInFlight` 1, now 0), and renders into a ring of only
  two textures, so with the UI thread ahead of the GPU a frame could show a
  later body. `_BodyScene` (whole_body.dart) renders, copies each frame
  into its own ring of three, and draws that (falls back to the library's
  picture if a backend can't copy).

## 61. Speed on every phone, faster launch (2026-11-04)

Measure first. Already done: 59.x (low RAM, slim 3D, prints at screen
size, BodyQuality, AAC sounds), 60.x (full refresh rate, no 3D pacing).

- [x] **61.1** → 2.0.8 · Measuring build: time before Dart's main (Android
  `Process.getStartUptimeMillis`, iOS process start), Launch Timing marks
  for each 3D step (static resources, studio light, model, skin, shader
  warm-up). (Flutter Scene's own frame stats: not yet.)
- [x] **61.2** → 2.0.8 · Debug > Speed Tests switches (`SpeedTests`), marked in the recorder:
  3D anti-aliasing (auto = MSAA / FXAA / none), 3D render scale, viewfinder
  look off, halation off, CRT bulge off, Quick Launch (saved; 0.3 s
  floor, 150 + 0 ms holds, 300 ms fade). Frames get a "[...]" tag. (3D
  anti-aliasing: FXAA vs auto; 3D scale: 70%.)
- [ ] **61.3** Launch without waiting for the 3D body: open on the drawn
  body, cross-fade to the 3D one when it lands (visible: show first).
- [ ] **61.4** Studio light baked offline instead of built from studio.hdr
  each launch (if Flutter Scene loads prefiltered maps).
- [ ] **61.5** Settings by measured speed (a first-run GPU probe or the
  first swaps' frame times), not just RAM: 3D scale, AA, halation, rate.
  Covers mid-range phones, GLES-only phones (S10+) and tablets (#62).
- [ ] **61.6** (Owner's 4 fps at rest was the FPS counter's own redraw.)
  Darkroom 98 at rest: find what redraws (FPS counter > 0 with
  nothing moving re-runs the full-screen CRT filter each frame).
- [x] **61.7** → 2.0.8 · Debug tidied: one Performance Report (phone +
  frames + launches + 3D quality + memory, Clear / Copy), the recorder
  always on (15,000 frames); gone: Performance Recorder, 3D Quality Stats,
  Memory Report, Launch Timing, System Info (all in the report), Frame
  Timing Graphs (FPS Counter + report). Folders: Darkroom, Pro & Unlocks,
  Performance, Speed Tests, Diagnostics, First Run & Prompts.
- Owner's numbers (2.0.7, Pixel 9 Pro): launch 1.6-1.9 s; 3D in ~1.0 s and
  camera open ~1.1-1.4 s side by side, then the 450 ms hold. Camera at rest
  ~40 fps (film grain ticks at 24, camera 30, unsynced: idea, tick the grain
  on camera frames).
- Owner's Speed Tests (2.0.8, Pixel 9 Pro): Quick Launch 0.96-1.26 s (was
  1.6-1.9); the 3D model read (0.23-0.9 s) + skin (~0.17 s) is now the long
  pole, camera open ~0.35-0.64 s. 3D 70% / FXAA: no visible loss, little
  GPU change (swaps are UI-thread bound: UI 6-8 ms vs GPU 4-6). No CRT:
  no change in Win98 GPU (~8-9 ms): the cost is elsewhere. Memory: each 3D
  body 192 MB of textures = RGBA8 sizes (ASTC would be ~50): the compressed
  textures likely fall back to uncompressed on the Pixel. Render targets
  138 MB.
- [x] **61.8** → 2.0.9 · Quick Launch is the launch: curtain 0.3 s minimum,
  150 ms after the camera opens, 300 ms fade (was 1 s / 450 + 200 ms / 600 ms).
- [x] **61.9** → 2.0.9 · Low RAM: the 3D body uses FXAA (no multisampled
  render targets). The 70% switch made no visible difference on the Pixel:
  BodyQuality already steers low-RAM sizes, so not applied.
- [x] **61.10** → 2.0.9 · Performance Report memory: each 3D body's texture
  formats and the GPU's reported compression support (ASTC / BC / ETC2), to
  see why the Pixel holds 192 MB of rgba8 per body.
- [x] **61.11** → 2.0.9 · Speed Tests round 2 (one table in debug_menu
  `_speedTests`): grain at 12 fps, still viewfinder in swipes (the live one
  is `toImageSync` every frame), no strap; Darkroom 98 scan lines, glass,
  colour filter, square screen. Dropped: CRT bulge, halation, Quick Launch.
- [ ] **61.12** Grain on the camera's frames: not possible from Dart (a
  camera frame re-rasters without a framework frame); 12 fps grain is the
  test instead.
- [x] **61.13** → 2.0.10 · Debug > Performance > Run Speed Test (top of the
  Debug window, Performance open by default; `speed_test_run.dart`): ~4 min
  hands-off. Camera: base, each switch alone, "light" (all camera switches),
  classic bodies (Fancy graphics off, restored after); each 5 s rest + 4
  tosses + 2 half swipes (synthetic pointers through GestureBinding).
  Corkboard: rest + scrolls. Darkroom 98: base, each 98 switch, all off,
  redrawing every frame (`SpeedTestPulse`). Live panel on top (step, stage,
  countdown, last second's fps / UI / GPU, progress; refreshes once a
  second; tap stops). Result: one compact monospace text (device, screen,
  RAM, 3D texture formats + GPU compression, last launch in one line, then
  per step: fps, UI and GPU avg/p90, late %), shown at the end with Copy to
  Clipboard; "Last Result" from the same dialog. Old switches folder kept
  as "Speed Test Switches" for manual checks.
- Owner's first Run Speed Test (2.0.10, Pixel 9 Pro): swipes 53-58 fps, UI
  5-7 ms is the limit; no strap = UI 5.3, late 19% (base 32%). Camera at
  rest: 25-30 fps (the camera's rate), GPU 9-12 ms because the GPU clocks
  down (no look / 3D 70% didn't lower it): not a problem. Corkboard at rest
  61 fps (developing trays animating at full rate). Darkroom 98 redraws at
  117 fps; its switches changed nothing. GPU reports no texture compression
  at all (ASTC/BC/ETC2 no): 3D maps load as rgba8, 192 MB a body.
- [x] **61.14** → 2.0.11 · Strap: stitches and the cord's weave drawn as one
  path each (were ~190 / ~110 draw calls a frame).
- [x] **61.15** → 2.0.11 · Corkboard: the trays' rock and the tank's turn
  step 30 times a second (`SlowLoop`, a timer, off when covered) instead of
  every refresh.
- [x] **61.16** → 2.0.11 · Speed test: Darkroom 98 switches removed (no
  effect; code reverted), one Darkroom 98 step kept; "late" only for moving
  phases.
- [ ] **61.17** 3D maps on phones without GPU texture compression (the
  Pixel's Vulkan reports none): smaller maps there? Ask the owner (visual).
- [x] **61.18** → 2.0.11 · Speed test, generic: part one goes round the app
  (camera rest + swipes, picker open/close, settings open/close, corkboard
  slide in / scroll / slide out, Darkroom 98 slide in / redraw / slide out),
  part two swipes again with each switch, all of them, and the drawn bodies.
  Moving phases are judged on frames drawn while something moved
  (PerfRecorder tags each frame: a ticker running or a finger down, matched
  by vsync time): fps while moving and "drop" = refreshes with no new frame.
  The first run's swipe "55 fps" mixed in the still frames between swipes.
  3D/s: 3D camera renders a second (`PerfRecorder.scene3d`).
- Owner's speed test 2 (2.0.11, Pixel 9 Pro): everything with the camera
  closed moves at 104-116 fps (picker, corkboard, Darkroom 98); the camera
  swipe at 55 fps / 54% dropped with UI 5.9 and GPU 5.1 ms (both under the
  8.3 ms budget), drawn bodies the same: a 60 Hz cap while the camera runs,
  not drawing cost. Darkroom 98 slide-in 77 fps (the camera closing during
  it). Settings: the sheet recorded no motion (didn't open?).
- [x] **61.19** → 2.0.12 · Speed test: "disp Hz" (the display's rate read
  from Android during each step, `darkroom/display` displayHz), a "camera
  off" swipe (stream stopped), PROBLEMS lines (a screen that won't open).
- [x] **61.20** → 2.0.12 · Speed test header: battery saver, thermal status,
  Smooth display min-peak, free RAM at start and end (`deviceState`), the
  camera stream size. Variant "strong 120 ask": the SurfaceView's vote as
  FRAME_RATE_COMPATIBILITY_FIXED_SOURCE during the swipe (`strongVote`).
- [x] **61.21** → 2.0.12 · Speed test hardened for any phone: "max" (the
  fastest rate frames arrived while moving, from the gaps: 60 on a 120 Hz
  screen = held to 60, any phone incl. iPhone), "disp" now Android's render
  rate where it says (reflection `getRenderFrameRate`) else the mode's,
  "a%" at rest (frames with an animation running: should be 0). Swipes are
  a fixed number of evenly stamped moves (the same gesture whatever the
  frame rate; a stall no longer reads as no toss). A failing step is noted
  under PROBLEMS and the run goes on. Start dialog: portrait, battery saver off.
- [x] **61.22** → 2.0.13 · Speed test didn't start on the owner's Pixel (2.0.12:
  Start, then nothing). The run now shows its panel before anything else;
  the phone-state and header steps (new in 2.0.12, before the panel) and
  every Android request have a 3 s limit; any error ends the run with
  results and a PROBLEMS line instead of silently. Test: a run shows its
  panel at once and a stopped run still gives results.
- [x] **61.23** → 2.0.14 · The real cause (Crash Reports): Pixels store
  Smooth display's peak_refresh_rate as Infinity; `.round()` threw in the
  phone-state line, the second time in the results step, so no results.
  `stateLine` shows "max", every Android number is checked finite, the
  screen rate falls back to 60 if odd, and building the results can't
  throw (a failure still ends with text to send). Test with Infinity/NaN.
- Owner's tablet (Galaxy Tab, SM-X218U, 3.3 GB, 90 Hz, 2.0.14): GPU-bound
  (UI 1-5 ms, GPU 20-48 ms with the camera live); camera swipe 30 fps / 66%
  dropped, settings 18 fps / 80%; with the camera's stream stopped the swipe
  ran 84 fps / 7%. ~540 MB free RAM. ASTC works there (3D 48 MB a body).
  2.2 s before Dart's main (Pixel 0.1-0.25).
- [x] **61.24** → 2.0.15 · Settings stops the camera's stream while it's open
  (as the picker; a still in its place). `_openSettings`.
- [x] **61.25** → 2.0.15 · Swipes on every phone: a still viewfinder, the
  camera's stream stopped until the camera lands (owner's choice after the
  Pixel run: with the camera running Android held the screen at 60 Hz,
  107 fps with it stopped; tablet 30 vs 84). Debug switch "Live Viewfinder
  in Swipes" and speed test step "live vf" for the old way. Dropped:
  "Still Viewfinder in Swipes", the "camera off" step (both superseded).
- [x] **61.26** → 2.0.15 · Low RAM cutoff 3.2 → 4.2 GB (`DeviceMemory.lowGb`).
- [x] **61.27** → 2.0.15 · Start-up investigation: FFmpegKit's plugin loads
  FFmpeg's native libraries in `registerGlobalCallbacks` (FFmpegKitConfig's
  static init) on the main thread before Dart starts. MainActivity now
  starts that class loading on its own thread first (`videoLibMs`), and
  Launch Timing breaks the time before Dart's main down: Android to the
  activity, onCreate, plugin registration, video library (alongside).
- [x] **61.28** → 2.0.15 · Quality manager (`core/performance/quality.dart`):
  two ladders, judged on moving frames (PerfRecorder feeds every frame) in
  48-frame windows: GPU (cheap 3D edges, no halation, 3D 90%, 80%, 60 Hz,
  70%) and UI (simple strap, grain 12 fps, 60 Hz). Two bad windows (over a
  fifth of refreshes dropped with our own work a real part of a frame) =
  one step down the bottleneck's ladder; six clean = the last step back up;
  a step up that goes wrong = settled for the run. Frames that are cheap but
  come slow (Android holding 60 Hz) are judged at the rate they can come.
  Saved per install; a first start on low RAM begins at GPU step 2 (the
  slowest at 5). Replaces low-RAM's fixed 60 Hz / halation / FXAA and
  BodyQuality's own low-RAM steering (BodyQuality follows `scale3d` on every
  phone, labels soften to match). The slow prompt only once every step is
  taken (`Quality.exhausted`). Debug > Performance > Quality Manager (steps,
  verdicts, by hand, auto off, reset); in the Performance Report and the
  speed test header (paused during a run).
- [x] **61.29** → 2.0.15 · Launch picture (`launch_picture.dart`): a PNG of
  exactly what the 3D model in hand draws (its box), saved when it has been
  redrawn and stood still 2 s, with what it shows (body, skin, camera,
  video shutter, GPU step, app version). At launch, if it matches, the 3D
  loader returns the layout at once (`WholeArt.load(early:)`) and loads the
  model behind it: the curtain lifts on the live face and viewfinder over
  the picture (only if it is exactly the box's size), and the model fades in
  over it (320 ms, from the frame after the model has drawn) when it lands.
  The curtain lifts on it only with the moving parts (flash tab, dials,
  nothing pressed) where they were in it. Touches and the volume keys wait
  meanwhile (trying anything shows the note); given up after 10 s. Failure:
  picture off, the provider reloads as before.
  LivePart registration moved from LiveBody to WholeBody and the face is
  always wrapped in LiveFace, so nothing rebuilds when the model arrives.
- [x] **61.30** → 2.0.15 · "Loading film…" / "Putting in SD card…": a dark
  box over the viewfinder (`CameraNote`) that fades in and out, only when you
  try to use a camera that's still loading (was a snackbar).
- [x] **61.31** → 2.0.15 · Launch curtain: lifts 200 ms after everything is
  ready (the first slow frames under it drawn: on the tablet the fade ran on
  them and read as a cut), fade 550 ms ease-in-out (was 300).
- [x] **61.32** → 2.0.15 · Corkboard slide-in shadow: a gradient strip, not a
  full-height blur. Viewfinder / body stills at the screen's resolution
  (were 60%; 80% on the slowest phones).

- [x] **61.33** → 2.1.0 · A quick flick toward the other camera while its
  3D model is still loading no longer tosses to a camera with no body (the
  note shows, the camera stays). 3D quality report: stale low-RAM wording.
- [x] **61.34** → 2.1.0 · Settings on slow tablets (44 fps, half the
  refreshes dropped): the camera screen under the sheet was drawn again
  every frame, all its layers. Now it's one picture of itself while the
  sheet is up (`_coverScreen`, taken as it opens: the same pixels), dropped
  at once if a setting changes the camera so the change shows.
- [x] **61.35** → 2.1.0 · The viewfinder shuts while the camera is off
  (swipes, Settings, the picker) instead of holding a still: film = mirror
  up (dark from the edges, the focusing screen's etched circle left),
  digital = LCD sleep (bigger pixels as the backlight goes). Opens over the
  live picture when the camera's back (`viewfinder_shut.dart`; mockups of
  six ideas, F3 and D2 picked). The focusing screen's etched circle and
  split line stay on the film viewfinder all the time (not in photos).

## 62. Ideas (2026-11-05)

- [ ] **62.1** Zoom on the film cameras (as the digital rocker).
- [ ] **62.2** iPhone Camera Control: slide to zoom, press to shoot (needs our
  own copy of the camera plugin's iPhone session; was the "slide to zoom"
  checklist item).

## 63. 2.1: UI and design (2026-11-05)

- [x] **63.1** → 2.1.1 · Launch onto a shut viewfinder: the curtain no
  longer waits for the camera or its look (it lifts once the face and the
  3D body or launch picture are in); the viewfinder opens like a camera
  powering up once the picture is live with its look loaded. Same after
  any restart (back from the background, a new stock: no plain picture
  first). The shutter while starting shows "Winding on…" / "Warming up…";
  so does a camera still not up 3 s after the curtain. No spinner under it.
  Launch Timing records camera open / look loaded / viewfinder opens after
  the curtain (`LaunchTimer.after`).
- [x] **63.2** → 2.1.1 · One look for messages (`core/theme/note_box.dart`:
  `NoteBox`, `Notes.show(text, action:)`), the camera's dark box. Trial on
  the print viewer's Saved notes and the corkboard's shake note; the other
  snackbars wait for a yes.
- [x] **63.3** → 2.1.1 · Frames (trial): Classic, Borderless, Deckle,
  Darkroom (filed carrier, frame number in the edge). Frame button in the
  print viewer opens a row of the print in each; per print, in prefs
  (`print.frames`). Viewer only for now (not the board, not saved files).
- [x] **63.5** → 2.1.1 · Frames go out with the print: Share and Save draw
  the chosen frame into the file (`exportFramedPrint`; a print never given
  a frame leaves bare as before), and the board shows it. Instant prints
  get papers: Classic, Black, Vintage, Sky, Blush, Mint, Stripes, each with
  its own ink so the note always reads (`InstantStyle`). One store for
  both (`PrintFrames`, prefs `print.frames`).
- [x] **63.6** → 2.1.1 · Every message in the new box (`Notes`); a tap on it
  closes it (the missing-prints note then stays away, as its X did).
- [x] **63.7** → 2.1.1 · Once saved, always saved: a print whose copy left
  the phone (deleted, or Google Photos' Free up space) stays saved, so Save
  all never saves it twice; the viewer offers Save again (PrefKeys.
  galleryGone), the note says it may be in the cloud backup. Prints an
  older version unmarked and the user waved off are marked saved again.
  Same on C: (Copy to Photos works on any file there).
- [x] **63.8** → 2.1.1 · Swaps: the new body's camera starts 150 ms after
  the toss is committed, not once it lands; a body nearly in (85%) can be
  caught by the next swipe (it lands at once); a swipe back before the
  camera starts cancels it, so spamming swipes queues nothing.
- [x] **63.9** → 2.1.1 · Digital viewfinder waking: big pixels shrinking
  as the LCD comes on (over a still of the first live picture), not a
  plain fade.
- [x] **63.4** → 2.1.1 · Sample prints on a new corkboard (`sample_prints.dart`,
  assets/samples, 0.7 MB): the owner's photos developed through the app's
  own pipeline: an instant print "Sydney Trip '26", Portrait 400, Golden 200
  in the darkroom frame. Put up once per install (existing ones too), after
  the launch. Count as saved, never offered Save or Share, skipped by the
  photo library check; thrown away like any print. Ids `sample-*`.
- [x] **63.10** → 2.1.1 · Half-size 3D textures where they can't be
  compressed (Pixel 9 Pro: 192 -> ~48 MB a camera): our own copy of
  flutter_scene 0.24.3 in packages/flutter_scene with one patch in its rgba8
  fallback (DARKROOM.md). iPhones and the tablet (ASTC) untouched. Check
  pub.dev for updates now and then (CLAUDE.md).

## 64. Camera controls, film first (2026-11-05)

- [x] **64.1** → 2.1.2 · Zoom ring on the film viewfinder (`film_dials.dart`):
  the top of a lens barrel along the bottom edge, marked in mm, dragged
  sideways; faint at rest, lit while in use, clicks (haptics) at each mark,
  coasts and bounces off the lens's ends. Every stock zooms, its own range
  (`ZoomSpec.wideMm`, `max`: 35 mm 28-70, single-use 32-48, instant
  116-175, Super 8 9-36, Epic 70 50-100), drives the phone zoom.
- [x] **64.2** → 2.1.2 · Exposure scale up the right edge (`ExposureSpec`:
  thirds; Super 8 halves; single-use whole stops; instant D • L). Moves the
  phone's exposure (`exposureCompProvider`, per camera, 0 each launch); the
  shot carries it (`PhotoJob.exposureComp`) so the film reads the scene's
  real brightness (lab notes too).
- [x] **64.6** → 2.1.3 · Switching stock keeps the focal length when the new
  lens reaches it, else the nearest end (`ZoomController._filmMm`).
- [x] **64.3** → 2.1.3 · The changing button: a chip in the film viewfinder's
  top-right corner (owner's pick over a 3D button). `CameraSpec.special`;
  blank ring where a camera has none. ME (35 mm stills): armed, the next shot
  is held (no frame used, `multi_exposure_controller.dart`), the second is
  blended onto it (`MultiExposure.blend`: light added, each ~2/3 stop under,
  soft shoulder) before queueing, so processing sees one frame. Super 8 FADE
  still to do.
- [x] **64.7** → 2.1.3 · The picker's ^ arrow is gone: film has the memo
  holder's thumb notch above the box end, digital an SD card-door tab
  (`PickerCaret`).
- [x] **64.4** → 2.1.4 · Lenses on the film stills cameras (`LensKind`,
  `CameraSpec.lenses`): wide, fish-eye, plastic, soft focus, swirl,
  tilt-shift, star filter, anamorphic, pinhole. Soft focus only where the
  plastic lens isn't (instant gets soft, 35 mm and single-use plastic). Lens
  ring top-left in the viewfinder opens a tray of caps; the viewfinder shows
  it (shaders/lens.frag via `LensPreview`), the photo gets it in Dart
  (`LensRenderer`, before the film look; blurs/streaks on a <=1024 px copy).
  Per camera while the app runs. Cine cameras (video): later.
- [x] **64.5** → 2.1.6 · The same for the digital cameras (64.26).
- [x] **64.8** → 2.1.4 · Zoom carries across stocks as the zoom level itself
  (not the mm), clamped to the new lens. Picker notch / SD tab removed (the
  tour explains the picker). Message box: 64 dp in from each side, at most
  340 wide. ME: the second exposure goes to the darkroom at once; the first
  is blended into it in the queue before it develops (`enqueuePhoto(prepare:)`).
- [x] **64.9** → 2.1.4 · Focus mark (`_FocusMark` in viewport.dart): film, a
  microprism ring tightening to an amber dot; digital, AF brackets that snap
  in, blink and go green. Replaces the square.
- [x] **64.10** → 2.1.4 · Focus marks wait for the camera: they hunt until
  setFocusPoint/ExposurePoint complete, then lock (green / amber dot); no
  answer in 1.5 s or unsupported: they fade without locking.
- [x] **64.11** → 2.1.4 · Android, upright: the status bar stays hidden but
  the gesture navigation bar stays active (transparent), so one swipe goes
  home (immersive sticky needed two or three). Turned: immersive as before
  (`UprightApp.applySystemUi`).
- [x] **64.12** → 2.1.5 · Wide and fish-eye take the phone's widest camera:
  the film zoom reaches below 1x (the phone's logical camera switches to its
  ultra-wide itself, e.g. a Pixel's 0.5x); another lens returns to the zoom
  before. Phones whose camera starts at 1x (the iPhone with today's camera
  plugin) keep the main camera.
- [x] **64.13** → 2.1.5 · iPhone: wide and fish-eye open the ultra-wide
  camera (the plugin lists it apart; `_Config.ultraWide`), the viewfinder
  shutter covering the switch; the main camera is picked by lens type, never
  an ultra-wide/tele by accident. Camera Control press: already the shutter
  since 2.0 (AVCaptureEventInteraction, AppDelegate.captureButtons); it comes
  in as volume-down, so with "volume zoom" on a digital body it zooms.
- [ ] **64.14** Camera Control slide-to-zoom (needs our copy of
  camera_avfoundation for AVCaptureSlider).
- [x] **64.15** → 2.1.5 · iPhones with the Camera Control: detected at launch
  (`AVCaptureSession().supportsControls`, iOS 18+; `CameraControl.present`);
  there the volume buttons are only ever the shutter (the Camera Control's
  press arrives as volume-down) and "Volume buttons zoom" is hidden.

- [x] **64.16** → 2.1.5 · Frozen viewfinder (Pixel 9 Pro). The still shown
  during a swipe dropped once, ~0.35 s after "ready", and only if nothing
  was touching: a touch at that moment left it up until the next swipe. Now
  it waits for the finger and drops then (`_dropWhenIdle`). And "ready" only
  means the camera opened: `PreviewProbe` reads two 64 px pictures of the
  raw preview texture a moment apart (identical twice = frozen), after each
  open and every 6 s; a frozen picture is logged and the camera reopened
  (twice at most until frames come back).
- [x] **64.17** → 2.1.5 · Camera Log: kept in a file across launches (150
  lines, a "launch" marker between runs), Copy (with version and system)
  and Clear; logs the lens on open, frames ok / frozen, and a still held
  over a ready camera.
- [x] **64.18** → 2.1.5 · Crash as the app closes ("FlutterJNI is not
  attached to native", Pixel): the camera handed Flutter's ImageReader
  texture a frame after the engine had gone. From the activity's
  onDestroy the main loop runs inside `LateFrameGuard`, which drops only
  that throw.
- [x] **64.19** → 2.1.6 · Viewfinder stuck on the other body's still over a
  stopped camera after quick swipes on resume (Pixel, log ended on "screen
  covered"): `_checkStuck` at rest restarts the camera / drops the still /
  lands a toss that never landed after 3 s, and logs "unstuck: …".
- [x] **64.20** → 2.1.6 · Fish-eye after the owner's references: an
  equisolid 180° circle filling 96% of the short side, the picture bent to
  fill it, light falling off to the rim, colour fringe, a blue coating line
  and a faint halo outside; the black is unexposed (no grain or fade after
  the film, `LensRenderer.finish`). The lens sits on the frame, not the
  whole preview (uCrop). Then after a second reference: the glass bevel
  (the last 7% jogs the picture back, lines curl at the edge), a soft
  edge, stronger fringes there, and a faint rainbow outside where the rim
  is bright (in place of the blue halo).
- [x] **64.21** → 2.1.6 · Star filter and anamorphic removed.
- [x] **64.22** → 2.1.6 · Wide lens only where there's an ultra-wide (the
  only way to reach it, with the fish-eye).
- [x] **64.23** → 2.1.6 · Changing lens shuts the viewfinder (the shutter
  animation), puts the lens on, waits for the camera's zoom / ultra-wide
  switch, then opens: lens and camera arrive together.
- [x] **64.24** → 2.1.6 · Another stock / camera whose viewfinder differs
  (film <-> movie, photo <-> video): the old shape is held while it shuts,
  the new one laid out in the dark, and it opens on the new picture.
- [x] **64.25** → 2.1.6 · Specials on every camera (`CameraSpecial`,
  `specialProvider`, `CameraSpecials`): Single-Use LEAK (a warm light leak
  from one edge, different each frame, before the film; `Specials`),
  Instant SELF (self-timer: 10 s, ticking, the chip counts down, pressed
  again it stops), Super 8 / Epic 70 / camcorders FADE (picture and sound
  fade in and out, 0.8 s or a third of a short take).
- [x] **64.26** → 2.1.6 · Digital stills: conversion lenses (standard,
  wide, fish-eye, soft, swirl, tilt-shift) and FX (colour, B&W, sepia; the
  viewfinder shows it, the photo gets it after the look). OSD keys in the
  pixel font (`DigitalKeys`): lens under the flash readout, FX top right
  (hidden while recording); the same tray of caps as film. Wide and
  fish-eye reach the ultra-wide on digital too.
- [x] **64.27** → 2.1.7 · An instant print developing showed the photo as
  taken, without its lens (fine once developed): the print's lens (from its
  queued job) now goes over it, the viewfinder's shader (`LensFilter`).
- [x] **64.28** → 2.1.7 · Super 8 shoots the way it's held: upright a
  portrait frame with the sprocket holes along the top (the strip turned,
  `CameraViewport.stripTurns`; the export lays the frame in on its side and
  turns the strip back, `stripPortrait`), sideways landscape with them on
  the left as before. No swing any more (the frame keeps its shape).
- [x] **64.29** → 2.1.7 · Photo <-> video camera: the old viewfinder is held
  until it has shut even though the new sensor mode has already stopped
  the camera (the session hears of the change first; `_canHoldForChange`).
- [x] **64.30** → 2.1.7 · The focusing screen's marks keep one size (the
  smaller, video one: `ViewfinderShutter.markSide` from the viewport's
  space, not the stream's box). Single-Use 27: no zoom, no exposure scale.
  The message over the viewfinder (`CameraNote`) is held well in from the
  frame's edges (at most 300 wide, 72% of the frame); 64.8 had only fixed
  the app-wide one.
- [x] **64.31** → 2.1.7 · Win98 player: a clip run to its end, wound back
  and played again sat still (Android's player stuck "ended"): it reopens at
  that spot; and any play that hasn't moved after 1.2 s reopens there.
- [x] **64.32** → 2.1.7 · Camcorder tape hiss halved.
- [x] **64.33** → 2.1.7 · A new ratio: the frame's edges glide to it (280 ms;
  a new camera's change happens behind the shutter).
- [x] **64.34** → 2.1.7 · Movie lenses on every video camera: fish-eye, mist,
  anamorphic (`LensKind.mist/anamorphic`, lens.frag 8/9; in the video,
  `VideoLens`: fish-eye by remap with written maps on a doubled picture plus
  an overlay, mist and anamorphic by LGPL filters; before the strip / OSD).
- [x] **64.35** → 2.1.7 · Lens caps redrawn, each its own lens (knurled
  standard, petal-hood wide, fish-eye dome, red toy, hazy soft, brass
  Petzval swirl, shifted tilt-shift with knobs, pinhole body cap, frosted
  mist filter, oval anamorphic).
- [x] **64.36** → 2.1.7 · Native crash reports read the tombstone: signal,
  cause, the crashing thread's frames, the last log lines (`Tombstone`;
  the readable-strings dump stays as a fallback). After a background crash
  on the tablet (SIGSEGV, null pointer, camera + video player open) whose
  report was cut short.
- [x] **64.37** → 2.1.7 · SLOW replaces FADE on every movie camera: the take
  plays at half speed (`setpts` + `framerate` blending the frames between),
  the sound stretched (`atempo=0.5`); cue marks, OSD and zoom bar follow
  the longer take. FADE removed.
- [x] **64.38** → 2.1.7 · The movie lenses checked on all four video cameras
  (FFmpeg test, Epic 70 included). On a 16:9 frame the fish-eye's circle is
  15% wider than the short side (cropped top and bottom: a small dot in
  black looked odd; `FISH_FILL_WIDE`, `LensRenderer.fishRadius`).
- [ ] **64.39** Tablet / squarer screens: a bigger viewfinder. The 3D body
  only stretches in height (body.top / mid / bot split at cutY); widening
  the viewfinder needs a column split too (export_glb.py `split_band` in x)
  and a re-export of both bodies in Blender, then the app stretching the
  middle column on wide screens and moving the lower controls in.
- [x] **64.40** → 2.1.8 · Win98 windows (the viewer, dialogs) closed as if
  they'd vanished: only a thin outline shrank. Now the window itself
  shrinks back to the file it opened from and fades, outline with it (220
  ms); and it stays built while it opens (`Win98ZoomTransition`, its state
  kept under a GlobalKey; it used to be rebuilt as the zoom ended).
- [x] **64.41** → 2.1.8 · Held sideways / upside down, the viewfinder's
  controls and readouts stay in place and turn upright (film: lens ring,
  special chip, zoom ring and exposure labels, lens caps, counter, date;
  digital: flash readout, keys, REC, zoom readout, date; the message box).
  The HUD used to be laid out again for the viewer (UprightBox), which put
  the shots-left counter under the lens ring. Digital's lens key steps
  beside the flash readout when sideways. `viewfinder_turn_screens_test`
  (SHOTS=dir: each mode, each way round).
- [x] **64.42** → 2.1.8 · Settings redressed per camera (owner's pick from
  three mockups): film, the owner's manual (printed paper, numbered
  sections, inked option boxes, tick boxes, a printed sound scale; Dial
  face for headings); digital, the camera's menu screen (dot-matrix W98
  face, CAMERA / SOUND / SETUP / PRO tabs, < > values, the touched row
  inverted, today's battery as a meter). Same settings; per-camera ones for
  any film / camera through < name > arrows. `settings_screens_test`.
- [x] **64.43** → 2.1.9 · Owner's manual: its text in Barlow Semi Condensed
  Medium (bundled, family `Manual`, beside the dial's Barlow Condensed);
  volume-buttons zoom only in the digital menu; weak grain inks dark blue,
  strong dark orange; sound in steps of 10%.
- [x] **64.44** → 2.1.9 · "Film Settings" / "Digital Settings". Film: the
  stock's specs under its name (badge · exposures · develop time), Pro a
  line at the back. Digital: Sound merged into Setup (three tabs). Clearer
  names (frame shape, film grain, vibrate on taps, 3D camera bodies, print
  ready alerts...). New: keep lens and special after closing the app
  (`GlobalSettings.rememberLens`, `Remembered` in the key store), save to
  Photos automatically (`autoSaveSince`, `autoSaveProvider`: film prints as
  they develop, digital photos when ready (to C:), only what finishes after
  it went on). Grid lines (`gridLines`, `_GridPainter`) built but not in
  Settings until the owner picks it from the mock.
- [x] **64.45** → 2.1.9 · Swapping to a stock with the same camera setup
  but another frame shape glides the frame (as a ratio change does) instead
  of fading out and in; the fade stays for a real camera restart.
- [x] **64.46** → 2.1.9 · Turning the phone: the readouts (shots left, flash,
  REC, date, keys, notes) fade round to the new way instead of snapping, and
  the dial labels swing round. The zoom ring's "mm" readout sits clear of the
  ring's numbers however the labels read. Digital Settings: sound effects as
  an old TV's volume bar (ten glowing boxes, slide or tap, - and +).
- [x] **64.47** → 2.1.9 · Grid lines: tried, not wanted; taken out.
- [x] **64.48** → 2.1.10 · Digital keys (lens, FX) turned smoothly then
  jumped into place: the turn's box grew to hold both ways round and shrank
  back when the old one had gone. The box is now the new way round's from
  the start (the lens caps had the same jump), each key turning from its
  own corner. test/turn_fade_test.dart.
- [x] **64.49** → 2.1.10 · Super 8's lamp by the RUN button jumped
  sideways as a swap went from it to a film release: the whole shutter
  widget moved by the release's hub offset at once, while the RUN face (and
  its lamp) were still fading out. The offset is now per face inside the
  button (ShutterButton.hubOf), so the face going out stays put. Seen and
  checked in the desktop 3D preview (SWITCH=, frame by frame).
- [x] **64.50** → 2.1.10 · RUN button less like a toy, no re-render: the
  press mesh gets its own copy of the parts material (before the scene takes
  the model), x(0.86, 0.80, 0.72) and roughness x3.2: satin, a warmer red,
  cream lettering (option D of four shown).
- [x] **64.51** → 2.1.10 · 3D quality: the body drawn at full size on all
  but low-RAM phones (was 90% on big screens). The quality manager stepped
  the Pixel all the way down: a 120 Hz screen held to 60 by Android with the
  camera on was judged against 120 unless frames were under ~6 ms. Now
  never judged against more than 60 a second; three bad windows in a row
  to step down (was two); steps saved under the old judging dropped (new
  keys).
- [x] **64.52** → 2.1.11 · 2.1.10 failed to start ("storage: quality.v2.gpu
  is not included in the PreferencesFilter allowlist"): the quality
  manager's new keys weren't in PrefKeys.all. Added (old ones too, so they
  can be removed); test/pref_keys_test.dart checks Quality's keys are there.
- [x] **64.53** → 2.1.12 · The film counter ("FRAME 12" -> "3 LEFT") faded
  across, then shifted: the switcher centred both words in the longer one's
  width and shrank once the old had gone. Lined up on their left now.
- [x] **64.54** → 2.1.12 · Front flash: on the front camera the screen
  lights warm white at full brightness (darkroom/display "brightness" on
  Android, darkroom/device on iPhone), 420 ms to settle, then the shot;
  flash on: always; auto: when the live picture is dark (PreviewProbe
  brightness < 0.22). Photos only. lib/core/device/screen_flash.dart.
- [x] **64.55** → 2.1.12 · Digital Settings: the whole sheet is the LCD (no
  screen set in a grey panel); How it works / Camera Shop / Feedback /
  Privacy out of Setup, a 2x2 of keys at the foot under every tab (a row
  of four sideways). Pull down to close, only a pull that starts with the
  list at the top (test/settings_swipe_test.dart).
- [x] **64.56** → 2.2.0 · Zoom ring numbers ran together (a lens's own end,
  34, beside the 35 mark; 48 by 50): the bigger one stays, each kept clear
  of the others (upright and sideways).
- [x] **64.57** → 2.2.0 · Version 2.2.0: main, the App Store (from 2.0.3) and
  Play closed testing.
- [x] **64.58** → 2.2.1 · ANR on 2.2.0 (Pixel 9 Pro, 2026-11-08 11:32): a
  SLOW clip finished in the Win98 player, the screen went black and the app
  stopped answering; leaving it, the main thread waited 5 s in
  FlutterJNI.nativeSurfaceChanged on the raster thread. The raster thread's
  stack wasn't in the report (cut at 8000 characters): now the head plus
  Flutter's and the camera's threads (MainActivity.anrDigest). SLOW files
  are clean (video 4.004 s, audio 4.013 s). Likely Android's player
  reaching the end of a file (cf. 64.31): both players (Win98, projector)
  now pause 200 ms short of the end, and every seek (slider, fast-forward,
  shuttle, reopen) is kept out of that last stretch (StopShort.safe), so
  nothing runs out (test/stop_short_test.dart). If it comes back, the next report shows the
  raster thread.
- [x] **64.59** → 2.2.2 · Prints as real paper (PaperWear,
  lib/core/processing/paper_wear.dart): corners a touch round, edges
  wandering a hair, the sheet bowed (light falling off across it), a cut
  edge catching the light, a shadow from its own outline lifted more at one
  end. Instant prints: the picture sunk below the frame, its corners round,
  the developer's uneven pale edge along the top. Age: fresh out of the
  darkroom, handled by three weeks (a little yellowing, a worn corner, a
  faint thumbprint). Board, viewer and saved files alike (a saved copy is
  remade as it ages). New frames: Mat (cream board, bevel-cut window) and
  Snapshot (round corners, glossy). Taped not taken.
- [x] **64.60** → 2.2.3 · The "frozen viewfinder" (Pixel, the digital OSD
  stuck over a film camera, a flip or new stock didn't clear it): the
  digital screen's waking still (ViewfinderShutter.waking) was dropped only
  when the opening finished (`whenComplete`); cut short (a toss, a flip,
  `_shutter.value = 1`) it stayed, and the film branch of the shutter draws
  its still even open. Dropped on complete or cancel, on every toss and
  every close, drawn only while the digital screen wakes, and _checkStuck
  drops one left up ("unstuck: a waking still left up").
- [x] **64.61** → 2.2.3 · 2D: the stock label's swipe took the whole row
  (the label is drawn at its left, narrower): only the label now.
- [x] **64.62** → 2.2.3 · Quality manager too lenient (a tablet only a few
  steps down): a refresh counted missed past 30% late (rounding let a
  jittery 40-45 fps pass as none missed); a very bad window (a third
  missed) steps down twice; two bad windows a step, as before 2.1.10.
- [x] **64.63** → 2.2.3 · A stock change that moves to or from the
  ultra-wide (wide, fish-eye on one and not the other) shuts the
  viewfinder over the camera change (takesWidest).
- [x] **64.64** → 2.2.3 · Win98 × closed suddenly: the close moved the live
  viewer into a scaled, faded layer, whose first frames ate the 220 ms on
  a phone. It shrinks a picture of the window now (toImageSync at the
  start of the close).
- [x] **64.65** → 2.2.3 · Turning the phone with a window open over a Win98
  page: the fade was per page, the window stayed up. The fade covers the
  whole app (UprightApp) while it turns.
- [x] **64.66** → 2.2.3 · Flipping front/back held the last picture: the
  flip shuts the viewfinder over the restart (CameraFlip, like a lens).
- [x] **64.67** → 2.2.3 · The corkboard's "no longer on your phone" note
  lingered over the camera after sliding back: notes can belong to a
  screen (Notes.show context) and go with it; swiped away or closed with
  their × (notes with an action). Win98's is a message box (closes with its
  buttons, can't be slid away).

## 65. App inspiration: Toned (2026-11-06)

Toned: Halation & Darkroom (iPhone, Aug 2026; an editor for library
photos, not a camera): expose, push/pull, negative, enlarger onto paper
(grades, 5 papers), dodge and burn, toners; 13 films, half frame to 4x5;
free tier + $14.99 once, "TONED" in the edge print on free exports. No
reviews yet. Ideas kept (on the checklist under App Inspiration):

- [ ] **65.1** Push / pull a roll at the lab (Pro), the lab note says what changed.
- [ ] **65.2** The negative as part of the story (lab film strips; hold a print to see its negative).
- [ ] **65.3** Paper per film (glossy, matte, warmtone fibre) and toners for B&W prints, shown on the corkboard.
- [ ] **65.4** Halation only from blown highlights, per stock; grain thinner in deep shadows / highlights: side-by-side check.
- [ ] **65.5** "DARKROOM" in the edge print on free lab exports instead of a watermark.
- [ ] **65.6** Hold a print to compare with the phone's original (where kept).
- [ ] **65.7** More formats: half frame, medium format 6x6 / 6x7.
- [ ] **65.8** Pro price vs theirs; translated store listings.

## 66. Tooling (2026-11-12)

- [x] **66.1** → 2.2.3 · CI pinned to Flutter 3.47.9: stable 3.50 broke the
  build (material.dart deprecated, analyze failed; test_api moved, the
  locked pub get failed).
- [ ] **66.2** Move up to Flutter 3.50: `material_ui` imports, refresh
  `pubspec.lock`, drop the pin (on the checklist under Speed).

## 67. After 2.2.3 (2026-11-12)

- [x] **67.1** → 2.2.4 · Win98 × still closed suddenly (video): the CRT
  bulge (CrtWarp) put a still of the screen over everything while its
  route went back, so the window sat frozen for the 220 ms, then vanished.
  The viewer's monitor stays put (ExplorerMonitor inPlace): the live bulge
  stays on and the shrink shows. Tests have no shader filter, so missed it.
- [x] **67.2** → 2.2.4 · Photo viewer: "Send To" is "Send", room round
  "13 of 53", a Close button at the bottom right.
- [x] **67.3** → 2.2.4 · The explorer's × shuts its window (shrinking to the
  taskbar) and leaves the desktop; Start > My Pictures opens it again;
  leaving Darkroom 98 and coming back opens it as before.
- [ ] **67.4** 2D: a flip still holds the last picture (2.2.3's shut over
  the flip doesn't happen). Not found by reading: 2.2.4 logs why in
  Debug > Camera Log ("flip, not shut: …" / "flip: no still to shut
  over"); waiting on that line from the phone.
- [x] **67.5** → 2.2.4 · The viewfinder's dark screen fills its whole space
  all the time; the camera's picture is scaled so the frame is as big as
  the space allows, centred (it was boxed to the stream's shape, which
  jumped between stocks and wasted room). A ratio change glides the frame;
  the screen's edges never move.
- [x] **67.6** → 2.2.5 · 67.4's cause: no "flip" line at all in the Camera
  Log. A rebuilt camera screen set CameraFlip.handler, then the old one's
  dispose cleared it, so flips fell back to a plain toggle. Cleared only if
  still its own (as LensChange already was).
- [x] **67.7** → 2.2.5 · Digital flash feel (a digicam's bang-and-done):
  Debug > Digital Flash picks Phone (the phone's pre-flash sequence),
  Locked (focus and exposure locked first) or Torch (the light on, the
  picture at once, preview exposure held). Camera Log: "photo: N ms press
  to capture (…)" for every photo. Next: pick one from the numbers; a
  digicam flash look in processing could go with the torch.
- [x] **67.8** → 2.2.5 · Late prints: the darkroom note is just "The lab has
  requested more time on these N photos." with an ⓘ: why (Darkroom only
  develops while it's open), and "Play a game", which slides Darkroom 98 in
  over the board and opens a random game (ExplorerScreen.slideIn(playGame)).
- [x] **67.9** → 2.2.5 · Developing prints sometimes showed no picture: the
  tray waited for the finished thumbnail, so a print still being made (big
  frame, slow phone) stayed blank. It shows the photo as taken meanwhile
  (monochrome under the safelight, as instant prints already did).
- [x] **67.10** → 2.2.5 · Debug > Darkroom Development off: the trays count
  up (how long each print takes to process), show the picture in full from
  the start, and never say "extra time".
- [x] **67.11** → 2.2.6 · Debug > Digital Flash showed nothing on the phone
  (its pick-one box never came up). Now two switches in a Camera folder,
  Flash: Lock First and Flash: Torch Pulse (one on at a time; both off =
  the phone's flash), showing Turn On / Turn Off like the others. Kept
  until the app restarts.
- [x] **67.12** → 2.2.7 · 3D swap, film: the live picture overlapped the
  polished ring (it filled the screen box, a hair bigger than the ring's
  opening, with tighter corners: whole_body.py), seen as the body turned.
  The film picture now fills the opening exactly (0.65 in, corner 7.35),
  and the turn's side clip (_RimClip, rim height x tan yaw, both sides:
  near rim edge and far wall) keeps the window's round corners. A first
  try in 2.2.6 rounded and inset it by eye; replaced.
- [x] **67.13** 2D flip still doesn't shut (2.2.5): see 67.15.
- [x] **67.14** → 2.2.7 · Launch splash: the rabbit was centred on its
  picture (the ears lean right), so its face sat left. Face centred
  (LaunchCurtain.faceShift = 27.5/384 of its width) on the curtain and
  Android's splash images; iOS's launch image is now the same rabbit (it
  was the bust with shoulders), face centred. The line below was centred
  already.
- [x] **67.15** → 2.2.7 · 67.13's real cause (the owner's "camera flip" is
  the swipe to the other body, not front/back; the Camera Log had no
  flips): in 2D the dragged body is one picture (_dragFace) taken as the
  drag starts, before the viewfinder begins to shut, so the shut ran
  unseen under it. The viewfinder's shutter is drawn over the picture now
  (_pictureShutting, at the viewfinder's place in it), and stays shut on
  the leaving body after the commit.
- [x] **67.16** → 2.2.8 · Flash test done (Pixel 9 Pro, digital, Camera
  Log): phone flash ~2.1 s press to capture, lock first 1.8-2.7 s (no
  help), torch pulse 1.2-1.3 s (and much dimmer). The test switches are
  gone; the press-to-capture time stays in the Camera Log.
- [x] **67.17** → 2.2.8 · Digital photos at once, like a 2000s digicam:
  - Android, flash On (back camera): our copy of the camera plugin
    (packages/camera_android_camerax, DARKROOM.md) builds the photo capture
    with the flash fired on the still frame itself (Camera2Interop
    FLASH_MODE_SINGLE, AE on), CameraX's flash and its pre-flash off, the
    lowest-latency capture mode (FastFlash arms it, rebuilds the capture
    through setJpegImageQuality; disarmed before every camera opens).
    Auto keeps the phone's flash.
  - iPhone, back camera: the photo is the live picture's next frame
    (PreviewSnap), lit by the torch for a flash, where the frame holds the
    camera's real resolution (lowResLongEdge ?? maxLongEdge after the crop;
    the 2008 DSLR keeps the photo capture). Front camera unchanged.
  - Camera Log says which: "fast flash", "preview frame[, torch]".
  - Not done (owner): saving the low-res cameras at their real size
    (phone galleries smooth small images).
- [x] **67.18** → 2.2.9 · Fast flash on the Pixel: 450-650 ms press to
  capture (was ~2.1 s), but shots about a second apart went off without
  the flash. Not the charge (the phone's own flash fires once a second, the
  owner checked): each fast-flash still now logs what the camera says it
  did (DarkroomFastFlash.report: flash mode asked, FLASH_STATE, AE state,
  "fast flash: …" in the Camera Log) and the gap since the last.
- [x] **67.19** → 2.2.10 · The log (2.2.9) showed why: the interop options
  reached every preview frame (a line every ~40 ms), so FLASH_MODE_SINGLE
  fired the flash on the preview just after arming and the photos showed
  READY (not fired). Now AE ON_ALWAYS_FLASH (the camera fires it for still
  captures only), and only the still's line is logged.
- [x] **67.20** → 2.2.11 · ON_ALWAYS_FLASH without a pre-flash: the Pixel
  never fired (flash READY on every still). Back to FLASH_MODE_SINGLE on
  the still, with the preview's repeating requests set to FLASH_MODE_OFF
  through Camera2CameraControl before the first photo (it overrides the
  session's options for repeating requests, not the still's own: checked
  in CameraX 1.6.2's CaptureConfigAdapter / UseCaseCameraRequestControl).
  Cleared again when the fast flash goes off or a camera opens.
- [x] **67.21** → 2.2.12 · Fast flash worked (2.2.11: lit, ~0.5 s) but
  without metering close scenes came out far too bright. The owner chose
  the phone's metered flash and its ~2 s again: our copy of
  camera_android_camerax, FastFlash and the iPhone's preview-frame shot
  (PreviewSnap) are removed; back to the hosted plugin and the normal photo
  capture on both. The press-to-capture time stays in the Camera Log.
  (Android 15's flash strength level was the one middle way left: one
  fixed strength, not tried.)
- [x] **67.22** → 2.2.13 · Flutter 3.50.0 (Dart 3.14): Material from
  `material_ui` 1.11 (`dart fix --code=migrate_design_widgets`, 100 files),
  SDK constraints 3.14 / 3.50, CI pinned to 3.50.0 (AGP 9.3.1, Gradle 9.5
  from flutter create; our build.gradle.kts already matches the template).
  Packages up: camera 0.12.2 (CameraX 0.7.6+1: video length fix;
  avfoundation 0.11.1: crash switching camera while recording fixed), gal
  3.0 (renames via dart fix), flutter_local_notifications 22.3.3 (iOS 27
  permission errors), Riverpod 3.5, image 4.12, sqflite 2.4.6 and the rest.
  Held: shared_preferences_android 2.4.28 (dependency_overrides), and
  flutter_local_notifications 23 (needs compileSdk 37; later). flutter_scene
  0.24.3 is still the newest (our copy stays).
  Taken up: zero shutter lag (camera 0.12.2; Android, iOS 17+), on for every
  camera except phones low on RAM: a no-flash photo is the frame at the
  press (the phone turns it off for a flash). Free with 3.50: a frame less
  touch latency on iPhone, a quicker first frame on Android with OpenGL.
- [x] **67.23** → 2.2.13 · Save to Photos automatically on: the SD card and
  floppy say "Auto Transfer is Enabled" under their "no files" line
  (ExplorerFilePane.emptyNote).
- [x] **67.24** → 2.2.13 · Darkroom 98's desktop (seen with the explorer
  window shut): My Pictures (opens the window on C:), Camera (back out),
  Games, Settings (Options). Games is a folder window with each game and
  High Scores as big icons (games_folder.dart; new pixel icons: cards,
  mine, bricks, pinball, trophy, joystick, settings, also on the games'
  own windows). High Scores (HighScores, in shared prefs): Solitaire's
  fastest win and wins, Minefield's best times, Bricks' and Pinball's high
  scores, Pinball's best rank; kept from now on.
- [x] **67.25** → 2.2.13 · First 3.50 build: Android failed in lint
  (AGP 9.3.1's lint calls List.removeLast, Java 21; CI ran Java 17). CI
  builds Android with Java 21 now (the app's jvmTarget stays 17). iOS built
  and went to TestFlight.
- [x] **67.26** → 2.3.0 · High Scores came up as a blank box: the prefs
  cache only allows keys in PrefKeys.all, and the hs.* keys weren't there
  (reads threw; no score was ever kept). Keys added (PrefKeys.highScores),
  reads and writes made safe. Desktop and Games folder icons: a tap selects
  (the 9x highlight), a second tap or a double tap opens (IconGroup).
- 2.3.0 released to main, Play closed testing and the App Store.

## 68. The Studio (2026-11-13)

- [x] **68.1** → 2.4.0 (renamed 2.3.2: the owner wanted no minor bump) · The Studio, off the corkboard (lib/features/studio):
  - The way in: a Studio button in the board's header, badged with the prints
    waiting there (mockups: artifact Darkroom Studio Mockups, option A).
  - Prints go in from the print viewer (Add to Studio); their spot on the
    board keeps its pin, a dashed outline and an "In studio" note; a tap
    asks to bring it back (StudioSpot). Kept in prefs (PrefKeys.studioItems).
    Photos only, no reels.
  - Inside, on a wooden work table: the prints in a tray (tap: back to the
    board), "Return all to the board", and four cards that say how many
    prints each takes: Photo Strip 3-4, Collage 2/4/6/9, Scrapbook 1-8,
    Flip Book 4-24 (StudioNeeds); too many or a collage's count off: pick
    which (PickPrints). After making one: "Send the photos back to the
    corkboard? Send them / Keep them".
  - Photo Strip: booth paper (black, white, cream), date stamp, slightly
    uneven gaps. Collage: Grid, Edge to edge, Loose (turned bordered prints,
    a little overlap), on white, black, cream or kraft. Every photo cropped
    to the piece's own shape (4:3 windows, squares), so formats mix. Strips
    and collages drop the prints' frames; the scrapbook keeps them.
  - Scrapbook: drag, pinch to size and turn each print, writing (double-tap
    to change it), a title, a page colour; saved 2400 px across.
  - Flip Book: snap cuts, a white flash and a small handheld shake each
    page (~0.4 s), a 4:5 MP4 (the app's MPEG-4 encoder), for Instagram.
  - The book (studio/book.json in app support): strips and collages share
    pages, a scrapbook fills one; tap one for Save to Photos (album
    "Darkroom Studio"), Share, Remove. All free for now.
- 68.1 Studio feedback (2026-11-13)
  - Corkboard header: a labelled "Studio" button (icon, badge of prints
    waiting); Save all moved under the title as a tappable line.
  - Scrapbook: pieces keyed (lifting one reordered the pile and the
    gestures went to the wrong print); one page gesture picks the piece on
    top under your finger, pinching beside the picked one still works.
    Size slider for the picked piece; six pen colours for writing.
  - Kraft is textured everywhere (mottling, fibres, flecks: paintPaper /
    StudioPaperView), in the previews and the saved pieces.
  - Flip Book: speed slider (0.15-0.9 s a page); the white flash covers
    only the print, not the paper round it, in the preview and the video.
- 68.2 The book as an album, the page turn, flip books as booklets (2026-11-13)
  - Style A (approved from mockups): cream grained pages in a stitched
    leather cover, page edges beneath, the spine's shadow, "— n —" in serif.
  - Page turn (studio_page_turn.dart): drag anywhere, the page folds along
    the line under the finger (the corner reflected across it), its back
    showing, shadows in the fold and beneath; past halfway or a flick goes
    over; ‹ › turn it for you. Save page to Photos.
  - Packing (studio_layout.dart): pages are 3:4; for each page every split
    of the next pieces (up to 6) into rows or columns is tried, scored on
    paper covered and pieces placed, none under a third or over two thirds
    of the page; then each is turned and nudged a little by its id. Strips
    are taped, collages held by photo corners.
  - A scrapbook is its page: the picture edge to edge.
  - Flip books keep their photos (flipbook_<id>/) with paper and speed; on
    the page a clipped booklet that riffles now and then; tapped, it's held
    big, flicking through at a speed slider, Replay, Share / Save video
    (made again at the new speed). Older ones show their video.
  - Corkboard: dog-ear cut out so the cork shows under the fold, no tick;
    Studio house icon; Save all and Return all without underlines.
- 68.3 Studio round 3 (2026-11-14), 2.3.3
  - Print viewer (option A): Share, Save, Studio, Frame; Write sits under
    the frames for instant prints (and on the print's border); Throw away
    is a red-ringed bin at the top right.
  - Flip book speed: the slider changes the pace, not the page (position
    kept in pages, moved on at the current speed), in the maker and the
    book's viewer.
  - Scrapbook (studio_scrapbook.dart): prints drawn live in a frame chosen
    for the page only, instant writing editable there; writing in Hand,
    Typewriter, Marker, Serif and Label (fonts added: Special Elite,
    Permanent Marker, Libre Baskerville); Remove; stickers (star, heart,
    arrow, sticky note with words, washi tape, flower: studio_stickers.dart);
    the page is the biggest 3:4 that fits and the tools below keep one
    height; prints laid out in an even grid to start.
  - Studio: a green felt tray in a wooden rim, bigger prints, hold to
    reorder; tap a print for a "Send Back" bubble under it; open-album Book
    button; images fade in; the book decodes its pictures before showing.
  - Making something: white flash, the maker closes under it, the piece
    held up then dropped onto the table, settles and fades (studio_snapshot).
  - Book viewer zooms over the whole screen. Corkboard Studio badge amber
    and bigger.

## 69. Photo Room in Darkroom 98 (2026-11-14), 2.3.4
- A wizard (option B, approved from mockups): welcome page with the five
  makes (Collage, Contact sheet, Greeting card or poster, Animated GIF,
  Photo booth strip), then Pick your photos (C:\My Pictures\Darkroom only;
  tap to pick in order, numbered; Select All up to the make's limit,
  Deselect All), then the look (backgrounds from the 98 palette, wide
  border; GIF speed slider and size; the card maker), Save, and Completing
  the wizard with "Open the Photo Room folder".
- Card maker: WordArt in Fire, Rainbow, Chrome, Ocean, Classic; pixel clip
  art (sun, balloon, cake, heart, star, flower, note, smiley, computer);
  photos; paper colours; drag, pinch, tap to pick, double-tap to edit.
- Saved to C:\My Pictures\Photo Room (its own folder in the explorer's
  tree, camera id `photoroom` from camera_catalog.dart), named 8.3 style
  (COLLG001.JPG, SHEET001.JPG, CARD0001.JPG, ANIM0001.GIF, STRIP001.JPG),
  and copied to the photo library like everything on C:.
- Opens from a desktop icon, Tools > Photo Room... and Start > Photo Room.
- 69.1 Photo Room strip, paint-program style (B, from mockups): a
  bucket-fill background (Lemon, Mint, Sky, Bubblegum, Lilac, Paper), shots
  outlined in black with a hard pixel shadow, doodles round the corners and
  in the gaps (the clip art, spray paint, sparkles, squiggles; never over a
  photo's middle), the caption in pixel letters with a shadow, the date.
  Caption..., Shuffle doodles (a new seed), Doodles and Date checkboxes.
- 69.2 Strip: Brown and Black fills (white outlines, bright inks, light
  date on them), a Crooked checkbox (each shot a little off true), the date
  as a PC writes it (11/14/26).
- Landscape pass over everything new: Studio cards in one row and a lower
  tray; the makers and the scrapbook put the piece on the left, options
  and Save on the right; the flip book viewer sizes the booklet to fit with
  its controls beside it; Photo Room puts previews beside their options
  when the window is wide. Studio and Photo Room screen tests now run
  upright and sideways (no overflow either way).
- 69.3 Studio lettering (studio_ui.dart): no stock app bars left. Makers
  and Pick prints get the spaced-capitals title (like FLIP BOOK) with a
  line saying what's being made; the scrapbook's title is handwritten and
  a touch tilted; a book piece shows its name and the day it was made.
  Option labels in small spaced capitals (STYLE, PAPER, PAGE, SPEED);
  choices are brass pills (the scrapbook's fonts each shown in their own
  lettering); dialogs and notes in the Studio's warm dark with brass
  buttons; bolder button lettering.
- 69.4 Photo Room fixes (2026-11-15), 2.3.5
  - Opening a Photo Room piece showed another picture: the explorer looked
    it up in the Darkroom folder's list (not found, so the first). Now each
    file opens in its own folder's list, and a file not found opens nothing.
  - The Photo Room folder sits first in C:\My Pictures\Darkroom (every
    view); Up from it goes back to C:.
  - Checkbox ticks in the window's ink (dark schemes showed black on black).
  - Win98Button keeps its size when pressed (the face shifts, the button
    doesn't grow): the 1-pixel jump when tapping Shuffle doodles, and
    anywhere else.
  - Wizard up to 820 tall; pinch to zoom the collage / strip preview;
    a stale preview from another make never shows while one draws.
  - Collage and contact sheet merged: 2 to 36 photos (short last rows
    centred), a "Contact sheet look" checkbox.
  - GIF changes: Cut, Fade, Circle, Slide, Dissolve, Blinds, in the preview
    and the file (5 in-between frames, 3 on long GIFs). The encoder now
    sends only bytes to its isolate (a closure had carried dart:ui images).
- 69.5 Photo Room and screens pass (2026-11-15), 2.3.6
  - Card save failed ("the card is not on screen") every time: the page
    changed to Saving before the card was captured. Captured first now;
    one save at a time.
  - Card maker: a paint-palette tool opens an Edit Colors panel (48 basic
    colours, Red/Green/Blue sliders) for any card colour; an Add a photo
    tool picks from the pictures on C:. Tools column scrolls on short
    windows.
  - GIF: slowest speed 2 s a photo (was 1 s; default still about 0.56 s);
    Blinds and Dissolve drawn in whole pixels with hard clip edges (no
    leftover lines).
  - Wizard sized like the explorer's window (desktop round it, room for
    the taskbar) and ignores the keyboard (showWin98Window avoidKeyboard);
    its own small dialogs still move up. Options scroll under the picture
    upright, so the preview keeps its room on small phones.
  - 98 glyphs (caption buttons, arrows) in the scheme's ink, so dark
    schemes show them; Win98Slider can have no ticks.
  - Help text: trimmed (flip book length line, pick hint, card hint);
    added "Hold a print to move it along" under the Studio tray.
  - Screens pass: Studio and Photo Room tests now run on a big phone and a
    small one (360 x 640), upright and sideways, with the keyboard up for
    the writing and caption boxes. Fixed what that found: Studio cards
    sideways (set height), scrapbook tools (scroll, page ignores the
    keyboard), flip book viewer buttons (shrink to fit the side panel).
  - Garbled strip thumbnails in the Photo Room folder (bits of other screens
    in them): the thumbnail was drawn from the on-screen picture's GPU
    texture. Now made on the CPU from the saved file; old ones redrawn from
    their files the first time the folder opens.
  - Card tools: a clearer paint palette (tan, colour dabs, thumb hole) and
    Add a photo as a picture with a green +.
- 68.4 Studio round 4 (2026-11-15), 2.3.7
  - Scrapbook (and the Photo Room card): a piece is picked the moment a
    finger lands (the double-tap recogniser made every tap wait ~0.3 s+);
    a second tap soon after edits it.
  - Stickers: bookmark tabs (yellow, pink, blue), short and wide, words
    along them, laid nearly flat.
  - Studio screens don't resize for the keyboard; only the text boxes move.
  - Book: arrives shut (front cover with gold lettering) and swings open
    once its pictures are decoded (no spinner); the left page shows (a
    strip upright, all of it sideways), the cover's red lining facing page
    one, page backs after. Page turn rewritten: the corner is bound to the
    spine (no folds off the page or perpendicular to it), the turned page
    lands on the left page, each page keeps its widgets through a turn
    (GlobalKeys: no reloads), the new page is set before the turn ends (no
    flashed frame), and arrow taps queue (later turns 300 ms). Pieces drift
    first-to-top-left, last-to-bottom-right; flip books loop on the page.
  - Flip books: studio_flip_frames.dart draws every frame for both the app
    and the video (keyframes: changes at 30 fps, still parts once), so they
    match. Styles: Page flip (spiral-bound booklet, page flicked over in
    perspective), Shutter (the old snap / flash / shake), Pile (each print
    dropped onto the last). No speed change after making (the viewer just
    plays; reflip removed).
  - Strip and collage makers: tap a photo to move and zoom it in its frame
    (PhotoCrop; stripCells / collageCells give the frames).
  - Corkboard sideways: a left swipe no longer puts the board away (only
    the pull down does, as the long side runs up/down).
- 68.5 Studio round 5 (2026-11-15), 2.3.8
  - Book: the cover swings up towards you (the rotation's sign was wrong:
    it sank into the table). Boards drawn once and uncovered as it opens;
    page blocks as leaf lines with the top page's shadow on them (the flat
    line under the book); no left block at page one. A turning page isn't
    clipped above or below the book; the spine-fold overlay (it showed on
    top of a turning page) is gone. Upright the book runs off the left of
    the screen; sideways both pages show, with room for the buttons.
  - Flip book, Page flip: a top-bound spiral pad on the table; the page
    lifts towards you, bows (14 strips, each tilted a little more), goes
    over the top onto the pages already turned. Loops (the last page flips
    to the first). Default 0.7 s a page, slowest 1.4 s.
  - Pile: every print drops in (the first too); at the end the pile is
    swept off to the left, top first, so it loops from a bare table.
  - No play badge on the book's flip books.
  - Scrapbook / card: only the first finger picks; a second finger
    anywhere sizes and turns the piece already held.
  - After making: no "send the photos back" question (they stay); the new
    piece drops onto the bare wooden table, then the Studio fades back in.
- 68.6 Photo strip options (2026-11-15), 2.3.9: Date (Printed,
  Handwritten in pen and a touch off level, None); Film holes (sprockets
  down both edges, frames a little narrower); Caption (your own words in
  place of DARKROOM, or none; bigger when there's no date).
- 68.7 Book rebuilt as a book; landscape (2026-11-15), 2.3.9
  - Landscape never worked on a phone: the Studio's routes weren't
    UprightApp.landscape / UprightPage like the corkboard's. All of them
    are now (Studio, pick prints, makers, book, viewers, the drop).
  - _OpenBook: a back board under the pages, a rounded leather spine with
    striped headbands, pages whose gutter corners dip (_PageShape) showing
    the dark of the gutter, and ONE front board hinged at the spine for the
    whole swing and after (it becomes the left board: nothing swaps as it
    lands, so no lining before there's a board, no stitches sliding, no
    red flash at page one). Left page and its block only once it's down.
  - Buttons woke only after a manual turn (opened was read outside the
    animation's builder): a status listener now.
  - Page drag: up/down counts for less and is capped (a wandering drag
    threw the corner across the page), and letting go lays the fold down
    over at least 260 ms (it could take 140 ms: a snap).
  - Book sideways: the heading stands in a column on the left, the page
    buttons and Save in one on the right, so the book takes the screen's
    whole height (about twice the size).
- 68.8 Book fixes; both pages filled sideways (2026-11-16), 2.3.11
  - Turning back to page one showed a page over the cover's lining until
    the turn ended: the left block of leaves was drawn whenever at > 0.
    Now _OpenBook gets a count of leaves lying on the left (one fewer while
    a page is lifted to come back: PageTurn.onTurning), the block only
    for leaves beneath the top one.
  - Headband half cut off until the board landed (the gutter's clip took
    it too): the clip is the gutter's only; the band comes out from under
    the board over the first half of the swing.
  - Valley shadows flickering when a part-turned page is let go: the last
    frames of the fall (fold all but flat) drew the page alone, without
    the left page. Same two pages now as when it's down.
  - Grey line under the page: the shadow on the leaves' edges was 45%
    black; now a light warm one.
  - Sideways both pages are filled, as a book's are: page 1 faces the
    lining, then 2-3, 4-5 (an even count ends on a left page facing a
    blank one). PageTurn's box is now both pages (the left one takes taps
    and drags), and a turning page's back is the left page it becomes
    (PageTurn.back is gone). Save takes the right page (the left if
    there's no right). Upright is as before.
- 68.9 Book polish, flip books, card save, clip art (2026-11-16), 2.3.12
  - Greeting cards saved as noise (Pixel 9 Pro): the card's picture was
    taken from the screen, then the page changed to Saving before its
    pixels were read, and the GPU had reused them. readStudioPixels reads
    them at once (through a plain 8-bit copy); keepOnC takes a width and
    height, not an image.
  - Book: left of the hinge the spine and headbands stay under the front
    board until it's nearly down (they drew over it in the air); the tail
    headband sits below the whole block of pages, not in the page's dip.
  - Page turn: its shadows scale with how far the page is off the pages
    (_Shade.lift), so nothing is left to vanish when it lands.
  - Studio: "Hold a print to move it along" 10 px lower, clear of the
    tray's shadow.
  - Flip book, Page flip: the wire coils are gone (drawn flat over the
    turning page). Pile: after the last print's time the pile is swept
    off (620 ms) and the table left bare (260 ms) before it loops
    (totalMs is longer by that for piles; the video too).
  - Photo Room clip art: confetti cannon in place of the cake; gift,
    crown, rocket, rainbow, lightning bolt added.
- 68.10 Darkroom 98: Multi-Select, menus and large text (2026-11-16), 2.3.12
  - Edit: Deselect All, and Multi-Select (checked while on): each tap
    adds a file to the selection or takes it out, nothing opens (no
    double tap or hold either, so taps land at once). A navy bar over the
    files says so, with Done. Off: a tap selects that one file alone.
  - Menus ran off the right of the screen (Tools at any resolution): the
    drop-down assumed 200 wide. _MenuPlace moves it left to fit; it stays
    under its title (never up over the bar, where a finger still down
    would pick from it) and scrolls if too tall for the room below.
  - 640 x 480 with large fonts, checked by running every Darkroom 98
    screen test with that as the default: the menu bar lost Help (titles
    now shrink to fit), the viewer's Send/Rename/Delete ran off (they
    shrink to fit), the Photo Room wizard's first page overflowed on
    short screens (it scrolls).
- 68.11 Book and Studio touches (2026-11-16), 2.3.12
  - The black notch above the tail headband was the gutter's dark wedge
    showing in the page's dip: right at the head, wrong at the tail (the
    pages below are there). Paper colour at the tail now.
  - Pieces kept clear of the page number: placed by their turned bounds
    (corners reach further than the box), bottom limit 0.125 page widths
    up, shrunk if they can't fit.
  - Flip books in the album: StapledFlipBook, a little book of prints
    stapled down its left edge, each page flicking up on the staples to
    show the next photo, at the book's own pace. Same for every style
    (the style plays when it's opened). No photos kept: the old booklet.
  - Studio: the tray's prints slide in from the right each time it's
    opened, staggered, after their thumbnails are decoded (1.2 s at most),
    so none is seen loading.
- 68.12 Scrambled saves, card limit, GIF changes, book (2026-11-16), 2.3.13
  - Still noise on the Pixel 9 Pro: a greeting card (every time), a flip
    book's cover and one of its pages. Reading pixels back from the GPU
    (toByteData) returns noise there now and then, whatever made the
    image. Not reproduced here; so every save now checks: looksScrambled
    (neighbouring pixels unlike all over a 5 x 5 grid of patches), and
    readStudioPixels reads again, later and by another route, up to 4
    times; drawStudioPixels draws afresh too. The card falls back to
    screen resolution, then says so (StudioScrambled) rather than save
    snow. GIF frames and the flip book's video frames (now PNGs encoded
    from the checked pixels, slower) go through it too. IF IT STILL
    HAPPENS: the card needs drawing on a canvas instead of from the screen.
  - Card: 1 to 8 photos (three across past four); Add a photo refuses a
    ninth (delete one first).
  - GIF: a change is a frame every 55 ms or so, 6 at least, eased, however
    many photos (long GIFs had 3 steps: read as a glitch).
  - New flip book's drop: the stapled book itself, shut (StapledFlipBook
    still), not its video's frame with the table in it.
  - Book: the front board's hinge moves 10 px out across the spine as it
    opens, and the spine and headbands show only up to it (uncovered by
    the board, not grown). Pages are straight at the foot (dip at the
    head only; no wedge there). The left block is leaves + 1 edges thick,
    5 like the right after four turns.
- 68.13 Snow: a cure tried, a test, and flip books at once (2026-11-16), 2.3.13
  - Nothing found on the Flutter tracker matching it. Best guess: a
    picture made off screen (Picture.toImage, a boundary's toImage) isn't
    certain to be finished by the GPU until a frame has gone through, and
    toByteData read sooner gets whatever was in that memory. settleGpu
    (schedule a frame, wait for it, 120 ms at most) now comes before
    every single save's read, and before every re-read. The check and
    retries of 68.12 stay as the fallback. NOT CONFIRMED on the phone.
  - Debug > Diagnostics > Picture Readback Test: 20 pictures each of four
    ways (read at once; after a frame; toImageSync; through a copy),
    counting scrambled ones and whether a second read cures them. Ask for
    its result before guessing again.
  - Flip book pages are copied on the CPU (copyStudioPhoto, image
    package, four at a time): no GPU, can't be snow.
  - Flip book at once: flipBook makes the pages and cover and returns;
    the MP4 (StudioMake.flipVideo) is made 5 s later in the background,
    or when Save/Share video first wants it ("Making video…"), or again
    from the kept pages if it was cut short. The book lists a flip book
    by its pages, not its video. Frames' PNGs are written on other cores,
    three at a time.
- 68.14 Readback test, round two (2026-11-16), 2.3.14
  - Pixel 9 Pro, 2.3.13: all four drawn-picture rows 0 of 20 scrambled.
    So a plain drawn picture reads back fine, at once or after a frame:
    the "read too soon" guess of 68.13 is not it (settleGpu is harmless,
    left in). What the test didn't cover and the failures all had: real
    photos (decoded files) and pictures taken from the screen
    (boundary.toImage, the card's). The test now adds: photo read at
    once; photo drawn into a picture; the screen as it is, at 1500
    across, and at 1500 after a frame (8 each). Next step depends on
    which row shows snow: photos -> decode them on the CPU; screen ->
    draw the card on a canvas.
- 68.15 Strip text colour; GIFs made side by side (2026-11-16), 2.3.14
  - 2.3.13 on the Pixel: new card, flip book and GIFs all fine (which of
    68.12/68.13's changes did it isn't known: the checked re-read, the
    frame's wait, or the pages off the GPU).
  - Strip: StripInk, the lettering's colour (Auto + 8), a row of swatches
    under Background. Auto is by the background alone now: it was drawn
    from the doodles' random run, so it changed with them.
  - GIF: each frame's 256 colours (NeuQuant + dither, the slow part) are
    found on 2 to 6 cores at once (_indexOff), then one pass writes the
    file (the encoder takes ready palette images as they are).
- 68.16 Book performance, first pass (2026-11-16), 2.3.14
  - The book's leather (up to 30,000 pits a board), paper (20,000 specks
    and 18 blurred blotches a page) and lining were CustomPainters: on
    Impeller, drawn in full every frame while the cover swung or a page
    turned. Baked (studio_ui.dart): painted once into a picture per size
    (at most 2x), one textured rect a frame after. Same look.
  - StapledFlipBook set state every tick: now only while a page is
    flicking, and once as it rests.
  - Pieces decoded at 640 wide (tall strips narrower, 240 at least), a
    scrapbook at 1000, not 900 / 1400; one table (_decodeWidths) for the
    page and the precache so they match.
  - Not measured on a phone yet: ask for Debug > Performance Report after
    using the corkboard, Studio and book, then do the corkboard from it.
- 68.17 Readback test, round two's result (2026-11-16)
  - Pixel 9 Pro, 2.3.14: every row 0 scrambled, photos and screen
    captures (as shown and at 1500) included. The test can't make the
    snow; cards, flip books and GIFs have been fine since 2.3.13. Cause
    still unknown (it needed something the test lacks: the wizard's page
    change mid-save, memory pressure, many reads in a row). The check and
    retries stay. If snow comes back: get the exact steps, and whether
    "The picture came out scrambled" was shown.
- 68.18 Corkboard performance from the report (2026-11-16), 2.3.15
  - Report (Pixel 9 Pro, 2.3.14, quality manager at all steps, 60 Hz):
    idle corkboard 2113 frames, 50 fps, GPU 8.8 avg / 16 p90 / 88 max,
    UI spikes ~20 ms; the board was drawing constantly while idle.
  - Whole board rebuilt every second (secondTickerProvider at the top of
    its build). Now built on a Timer for the next print's readyAt; only
    the darkroom strip keeps the per-second clock (a Consumer).
  - Each developing tray's SlowLoop had its own 30 fps timer, out of step:
    four trays asked for up to 120 frames a second, so the board redrew
    at the screen's full rate. One shared beat now.
  - Trays: Opacity + ColorFiltered (two offscreen layers a frame) merged
    into one ColorFiltered with the fade in its alpha row; the print
    image in a RepaintBoundary apart from the rocking tray.
  - Report labels: screens 'studio' and 'book'; marks 'book opening' and
    'book page turn' (the last report had no Studio/book lines at all).
  - Owner: thinks the quality manager steps down too readily. Next.
- 68.19 Quality manager tuned; makers labelled (2026-11-16), 2.3.16
  - 2.3.15 report: idle corkboard 149 frames (was 2113), scroll 105 fps,
    book turns 117 fps, quality full. Idle studio 96 fps / 243 slow: the
    makers and the drop were counted as the Studio.
  - Quality judged on the camera screen's frames only
    (PerfRecorder.screen == 'camera'): every step lightens the camera, so
    other screens stepping it down cost it for nothing (2.3.14: all steps
    taken, mostly from the idle corkboard).
  - Steps down: three bad windows of the last four (very bad counts
    twice), one step at a time (was two in a row, very bad = two steps).
  - Each launch starts one step above the saved steps (the side with
    more taken gives one back).
  - Report: makers as 'maker: strip/collage/scrapbook/flipbook', marks
    'studio drop' and 'studio prints slide in'.

## 70. Store pages and release words (2026-11-17)
- [x] 70.1 Play production access granted (2026-11-16): Google Play section
  taken off the checklist. "push" = internal testing + TestFlight;
  "publish" = Play production (`promote-production.yml`, straight from
  internal, no closed step) + App Store (`appstore-release.yml`).
  CLAUDE.md, NOTES.md, RELEASE.md updated.
- [ ] 70.2 Store videos and hero image: one ~25 s portrait clip recorded
  on the iPhone (shutter, develop, print, film swap, Win98) as the App
  Store preview (886×1920, 15–30 s, app footage only); the same on YouTube
  (unlisted, no ads, landscape canvas) as Play's promo video, which turns
  the 1024×500 feature graphic into the big banner at the top of the page.
  Optional: a fresh feature graphic / cover frame (2–3 options first).

## 71. Sounds in the Studio; flip book look (2026-11-17), 2.3.17
- [x] 71.1 Page turns in the Book: four recorded takes (CC0, OpenGameArt
  "80 CC0 RPG SFX" book_01..04), 8 players (each take pitched low and high), shuffled, so quick taps
  overlap; on each tap / queued turn, and when a dragged page goes over.
- [x] 71.2 Studio snapshot: an old shutter's cha-chunk (CC0, OpenGameArt
  "Camera") with the white flash after a strip / collage / scrapbook page
  / flip book is made.
- [x] 71.3 Owner picked page set 1 and shutter 1 (the ones built in).
- [ ] 71.4 Flip book: the stapled look as the default style, made more
  real. Mockups A (stiff swing, lit), B (page bows over from the free
  edge), C (corner first, like a thumb riffle): owner picked C; where
  the turned pages go is still open.
- [x] 71.5 Performance Report expanded (hitches, stalls, events, one clock).
- [x] 71.6 "Stapled" flip style, the new default (mockup 1d): corner-first
  turn pinned at the spine, pile on the left (half in frame), riffle back;
  stack edges a few px, timed to lift / land. Page sound once a turn, a
  riffle on the way back (in the video, mixed per page; in the Book as it
  plays). Album flip books stay shut until tapped.
- [x] 71.7 Flip book videos: quality-based MPEG-4 (was a fixed 6 Mbps) and
  each frame marked and checked on readback (the owner's videos had a frame
  of stale GPU memory and a black last frame).

## 72. Flip book follow-ups (2026-11-17), 2.3.18
- [x] 72.1 Riffle back: pages in the air drawn flattest first (the more
  upright one covers the flatter), not in the order they left the pile.
- [x] 72.2 Speaker button in the flip book maker (styles with sounds):
  off = the video has no sound track (`StudioWork.silent`). The Book still
  plays page sounds as it plays.
- [x] 72.3 Page flip style off the maker's list (`FlipStyle.offered`); old
  books in it still play.
- [x] 72.4 Framing a stapled flip book's photos: tap the preview for a
  strip of every photo at the page's shape; tap one for the crop sheet
  (as the strip / collage). The kept pages are saved cut to that framing
  (`copyStudioPhoto(aspect:, crop:)`), so the video and the Book need no
  more. Other styles show photos whole (a note says so).
- [x] 72.5 The speaker button also governs the maker's preview (page
  sounds as it plays when on) and the Book (a silent book plays silent).
- [x] 72.6 With flash on / auto (and the screen flash), the viewfinder's
  shutter blink waits for takePicture to return (the pre-flash metering
  made the blink at the press read as done). Without flash it stays at
  the press.
- [x] 72.7 Digital with Auto Transfer (`autoSave`) on: the gallery
  button's review screen shows C:'s newest picture; "STORAGE EMPTY" when
  C: has none (still "SD EMPTY" otherwise).
- [x] 72.8 From the owner's 2.3.17 report: the stapled page mesh built in
  typed lists (no objects a vertex), 30 x 28 cells, the pile's top drawn as
  one mirrored picture: ~4x less work a frame (maker preview was 40% slow,
  UI up to 80 ms). Report: gap hitches / hiccups only while something
  moves (idle Win98 showed seconds-long "gaps"); the second 3D camera's
  load logs each step's ms (it held the thread 485 ms at 2.8 s: the
  stutter after launch).
- [x] 72.9 A picture frozen through two reopens gets a third after a
  1.5 s rest (camera list read afresh). Flip maker photos at 640 px (was
  800), the Book's playing flip book at 800 (was 1000).
- [ ] 72.10 The stutter after launch (second 3D camera's load held the
  thread 485 ms): the next report's "3D ... loaded (ms)" event says which
  step; then move that step off the thread (owner chose this over loading
  it behind the curtain).

## 73. From the 2.3.18 report (2026-11-17), 2.3.19
- [x] 73.1 3D drawing buffers (~80 MB a camera; 157 MB with both) let go:
  a camera's own when no view draws it (put away after a swap), all of
  them 1.2 s after the camera screen is covered or the app leaves.
- [x] 73.2 Report: a mark repeated while it holds (a drag's every move) is
  one event (corkboard scroll flooded the 120 events, so the 3D load line
  scrolled off); each 3D load step logs its end; the steps are kept in
  the launch's times too.
- [x] 73.3 The stall after launch: the 2.3.19 report put it in the "read"
  step (flutter_scene's loadScene: 428 ms busy at 2.0 s of 856). Its
  realize builds every mesh at once, synchronously; our copy's preload now
  builds them first in ~6 ms slices, yielding between (second patch,
  packages/flutter_scene/DARKROOM.md), 2.3.20.
- [x] 73.4 2.3.19 report: buffers let go as planned (78 MB twice; render
  targets 0 MB in Win98).
- [x] 73.5 The Book's page blocks like the flip book's: thin edges (fine
  lines), each side as deep as its share of all the book's pages (full
  book 2.5-7 px), the side a page lifts from losing it at once, the side
  it lands on gaining it once down (`_turning`, both directions).
- [x] 73.6 Shut flip books on an album page no longer flash blank as the
  page opens: their first photo is decoded with the page's other pieces
  (`StapledFlipBook.warm`, kept for 24), drawn from the first frame; an
  old one's cover is precached.
- [ ] 73.7 2.3.20 report: the stall after launch is down to 342 ms (was
  428): still inside loadScene but not mostly the meshes. The loader now
  reports its steps (`darkroomTrace`: textures, each upload, materials,
  meshes with their ms, realize) into the report's events; next report says
  which.

## 74. Corkboard fast scroll (2026-11-17), 2.3.21
- [x] 74.1 Prints that hadn't decoded showed blank paper in a fast scroll.
  `BoardPhoto`: a 64 px copy of every print, decoded when the board opens
  (~25 KB each), shown under the sharp one until it's decoded; the sharp
  one decoded at the size shown (was always 420 px: ~1.7x the pixels a
  portrait phone's tile needs).

## 75. The stall after launch, found (2026-11-18), 2.3.22
- [x] 75.1 2.3.21 report: the 500 ms stall loading a 3D camera sat
  between "document read" and the first texture upload. Each texture's
  bytes were a view into the whole scene file, and sending a view to an
  isolate copies its whole buffer: nine ~50 MB copies on the UI thread.
  Now a `TransferableTypedData` of the texture alone (flutter_scene patch
  3). Measured on desktop: 9 sends 240-260 ms -> 22-30 ms. Same at launch
  (the 354 ms stall behind the curtain).
- [-] 75.2 Text over the controls in landscape: meant for another thread
  (not this app).
- [ ] 75.3 2.3.22 report: the stall is still there (403 ms at 1.9 s,
  around "document read" to the first upload), so the view copy wasn't the
  main cost (kept: it's cheaper). Isolate spawns ruled out (cheap with a big
  heap, tested). Finer trace now: asset in (size), handing it to the reader,
  reader done, preload start, texture loads started, each hand-over of 3 ms+.

## 76. Darkroom 98 thumbnails on a fast scroll (2026-11-18), 2.3.23
- [x] 76.1 As the corkboard (74.1): Large Icons thumbnails show a 32 px
  copy (blocky, fits the 9x look) at once, decoded for every file when the
  folder shows (`_Thumb.warm`), the real one over it once decoded; the grid
  builds 1.5 screens ahead.

## 77. Apple SDK deadline (2026-11-18)
- [x] 77.1 Apple's ITMS-90725 (on the owner's other app, Duel): from April
  2027 uploads need the iOS 27 SDK / Xcode 27. The `ios` job now prints its
  Xcode / SDK and warns while it's under 27; CLAUDE.md says to select
  Xcode 27 in that job before then. Passed on to the Duel, Roadie and
  Sisyphus sessions.
- [ ] 77.2 Before April 2027: select Xcode 27 in the `ios` job.
