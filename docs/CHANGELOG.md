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
