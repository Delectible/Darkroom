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
