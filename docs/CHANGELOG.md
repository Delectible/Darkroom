# Darkroom change log

Running list of requested changes and when each one landed.

**How to read it**

- `[ ]` planned · `[~]` in progress · `[x]` done · `[-]` dropped
- Done items end with `→ version · date · commit`.
- Item numbers (e.g. **3.2**) stay fixed, so you can say "do 3.2 next".
- New requests go at the bottom of the current revision, or into a new
  revision section.

---

## Revision v0.2 (requested 2026-10-06)

Ships as app version **1.3.x**, one patch number per batch:
A = 1.3.0 (quick fixes), B = 1.3.1 (pipeline, Polaroid, zoom),
C1 = 1.3.2 (Win98, reels, landscape, feedback), C2 = 1.3.3 (mode switch,
darkroom, corkboard, ambience).

### 1. Carousel & navigation

- [x] **1.1 Swipe hitbox:** swiping anywhere on the screen scrolls the
  carousel, not just on the item icon. → 1.3.0 · 2026-10-06 · c1ca3d1 (build 11)
- [x] **1.2 Gesture deadzone:** add a deadzone for up/down swipes so a
  horizontal swipe doesn't close or open the carousel by accident. → 1.3.0 · 2026-10-06 · c1ca3d1 (build 11)
- [x] **1.3 Swipe targets:** swiping on the film icon or on the text label at
  the bottom both cycle through the choices. → 1.3.0 · 2026-10-06 · c1ca3d1 (build 11)
  Works on the camera screen too: swipe the name or film box sideways.
- [x] **1.4 Animation polish:** smooth the jumpy transition between items
  that have tags (grain strength, movie). → 1.3.0 · 2026-10-06 · c1ca3d1 (build 11)
- [x] **1.5 Alignment:** centre the film stock element properly. → 1.3.0 · 2026-10-06 · c1ca3d1 (build 11)
- [x] **1.6 Caret placement:** move the small arrow caret next to the film
  name from the left to the centre. → 1.3.0 · 2026-10-06 · c1ca3d1 (build 11)

### 0. Feedback on 1.3.1 (build 13)

- [x] **0.1 Smooth zoom:** the zoom moved in visible ~0.1x steps.
  Zoom requests now stream every frame instead of waiting for each to land. → 1.3.2 · 2026-10-06 · ccb81b6 (build 14)
- [x] **0.2 Zoom bar in the video:** camcorder recordings carry the sliding
  zoom bar (found-footage style), plus blinking REC, SP and battery. → 1.3.2 · 2026-10-06 · ccb81b6 (build 14)
- [x] **0.3 Home gesture:** swiping up from the bottom edge to go home
  flashed the carousel open. Swipes from the bottom ~56dp are ignored. → 1.3.2 · 2026-10-06 · ccb81b6 (build 14)

- [x] **0.4 Flip shape:** a turned-over Polaroid changed size. The front now
  holds the card's size while the back shows. → 1.3.4 · 2026-10-06 · dab895a
- [x] **0.5 Win98 bounds:** the My Computer tab ran past the window. Tabs now
  share the strip by width; also fixed the Transfer/Copy button label, the menu
  bar and Drive Properties rows. A test opens every tab, menu and dialog at
  phone size (real fonts) and fails on any overflow. → 1.3.4 · 2026-10-06 · dab895a
- [x] **0.6 Swap sound:** now a soft cloth-on-cloth swish, quieter, no clack. → 1.3.4 · 2026-10-06 · dab895a
- [x] **0.7 Win98 font:** Roboto looked too modern. Windows 98 screens now use
  a pixel font (DotGothic16, OFL); □ ▲ ▶ ✓ etc. are painted pixel glyphs.
  → 1.3.5 · 2026-10-06 · 428d7e8
- [x] **0.8 Edge gestures:** dragging from the screen edges fought the phone's
  back gesture (sides) and could fight the notification shade (top). Our
  drags now ignore touches starting in those strips (camera and carousel);
  level with the peeking camera Android gives both edges to the app so it
  can be pulled in from the very edge. → 1.3.7 · 2026-10-06 · 908cebb (build 22)

### 2. Photo & video previews (film & digital)

- [x] **2.1 Pan vs. swipe:** when zoomed into a photo, panning must not
  trigger swipe-to-next. Applies to film and digital. → 1.3.0 · 2026-10-06 · c1ca3d1 (build 11)
- [x] **2.2 Film video replay:** film videos won't play again after reaching
  the end (digital videos are fine). → 1.3.0 · 2026-10-06 · c1ca3d1 (build 11)
  Not reproducible off-device; please confirm on the Pixel.
- [x] **2.3 Film video thumbnails:** a stylised image of the first frame so
  each reel can be identified. Idea: a print glued to the front of the
  spool. Come up with something that makes physical sense. → 1.3.2 · 2026-10-06 · ccb81b6 (build 14)
  A short tail of film hangs from behind each reel; its frames show how the clip opens.
- [x] **2.4 Developing state:** a distinct, stylised look for film videos
  that are still developing. → 1.3.2 · 2026-10-06 · ccb81b6 (build 14)
  Reels develop in a daylight tank: the reel turns in the chemistry, stage shows DEV → BLEACH → FIX → WASH.
- [ ] **2.5 Share sheet preview:** sharing a video on Android shows only the
  file name. Pass a thumbnail to the share sheet.
  Tried in 1.3.0 (build 11): a provider that serves a first-frame thumbnail.
  Gabe confirmed the sheet still shows no thumbnail. Low priority; revisit.

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
- [x] **3.2 Motorised zoom:** fixed-rate zoom on dedicated buttons for the 90s
  Camcorder (no pinch). The buttons also work in the other digital cameras.
  Realistic zoom limits per camera. **No zoom at all in Film mode.** → 1.3.1 · 2026-10-06 · 4a676b7 (build 13)
  Floppy/CCD 3x, flip phone 4x, camcorder 10x (slow motor); capped by the phone.
- [x] **3.3 Zoom indicator:** retro sliding zoom bar overlaid on the camcorder
  screen. → 1.3.1 · 2026-10-06 · 4a676b7 (build 13)
- [x] **3.4 Zoom buttons always shown:** keep the zoom buttons on every digital
  camera so buttons don't appear or vanish when switching cameras. → 1.3.1 · 2026-10-06 · 4a676b7 (build 13)
- [x] **3.5 Front camera button:** redesign the switch-camera button; the
  current one is too plain. → 1.3.2 · 2026-10-06 · ccb81b6 (build 14)
  A knurled dial with a lens in it; it turns half a turn when you flip cameras.
- [x] **3.6 Landscape fixes:** the flash and aspect ratio buttons shouldn't
  stretch or rotate awkwardly. The settings menu, carousel and filters must
  lay out properly when the phone is held sideways. → 1.3.2 · 2026-10-06 · ccb81b6 (build 14)
  Flash/aspect keys have fixed sizes (icon-only sideways). Settings and the picker filter open as a sideways panel when held in landscape.

### 4. Windows 98 mode & darkroom

- [x] **4.1 Win98 UI scale:** make the Win98 UI bigger, especially the photo
  navigation buttons, for touch. Keep the proportions and the Win98 look. → 1.3.2 · 2026-10-06 · ccb81b6 (build 14)
  Everything Win98 is drawn 1.3x larger, same proportions; bigger ◀ ▶.
- [x] **4.2 Win98 navigation:** no left/right swiping. Add a zoom slider and a
  "Reset Zoom" button; pinch-to-zoom still works. → 1.3.2 · 2026-10-06 · ccb81b6 (build 14)
- [x] **4.3 Win98 video player:** Win98-style buttons instead of tap to
  play/pause: rewind, fast forward, previous, next, stop, play/pause. Glitchy
  VHS-style artefacts while rewinding and fast-forwarding. Progress slider,
  elapsed/total time, and the other things a player would normally show. → 1.3.2 · 2026-10-06 · ccb81b6 (build 14)
  |◀ ◀◀ ▶/❚❚ ■ ▶▶ ▶| with seek bar and time; hold ◀◀/▶▶ to scan with rolling snow bars and jitter.
- [x] **4.4 Win98 metadata:** read the camera type from the photo's
  Exif/metadata and show it at the bottom of the Win98 viewer. → 1.3.2 · 2026-10-06 · ccb81b6 (build 14)
  Photos now carry Make/Model EXIF; the viewer reads it back ("Camera: 2003 CCD Compact"). Older files fall back to the catalog.
- [x] **4.5 Floppy drive easter egg:** the camcorder transfers videos by a
  different route than the SD card, worked in through a floppy drive (A:) in a
  way that still makes sense, since a camcorder has no floppy. → 1.3.2 · 2026-10-06 · ccb81b6 (build 14)
  Camcorder clips live on 3½ Floppy (A:). Copying to C: asks you to swap disks ("insert disk 2 of N"); after three swaps it offers to do the rest.
- [x] **4.6 Darkroom progress visual:** replace the plain white square with a
  more immersive progress visual that follows real film development
  (simplified). → 1.3.3 · 2026-10-06 · 3cd4a8f (build 15)
  Prints move through DEV → STOP → FIX → WASH trays under the safelight; the image comes up in the developer.

### 5. Performance & general

- [x] **5.1 Red square:** remove the unexplained red square at the top of the
  screen. → 1.3.0 · 2026-10-06 · c1ca3d1 (build 11)
  It was the hidden "prints ready" banner peeking out above the safe area.
- [x] **5.2 Mode ambience:** add visual touches unique to Film and Digital mode
  that pull you in and match real-world equipment. → 1.3.3 · 2026-10-06 · 3cd4a8f (build 15)
  Film: the box end sits in a memo holder on the back. Digital: a segment-LCD panel with battery and card/tape left.
- [x] **5.3 Flip phone artwork:** it looks folded backwards. Keep the style,
  fix the orientation. → 1.3.0 · 2026-10-06 · c1ca3d1 (build 11)
- [x] **5.4 Corkboard loading:** fast scrolling leaves blank spaces that fade
  in slowly. Optimise photo lazy-loading. → 1.3.0 · 2026-10-06 · c1ca3d1 (build 11)
- [x] **5.5 Corkboard wall:** the background scrolls with the photos, so you
  slide the whole wall instead of a fixed backdrop. Refine the cartoony cork
  with imperfections that show as you scroll. Better-looking pins. → 1.3.3 · 2026-10-06 · 3cd4a8f (build 15)
  The cork scrolls with the prints and shows wear (old pin holes, a coffee ring, sun-faded patches); new glossy two-tier pins.
- [x] **5.6 Corkboard easter eggs:** more hidden interactions, like Win98's.
  For example: tap a pin → "Would you like to discard this image?" → the photo
  and pin fall off the screen (same effect as the bin button in the preview). → 1.3.3 · 2026-10-06 · 3cd4a8f (build 15)
  Tap a pin to take a print down (it falls off). Tap a print's folded corner to turn it over and read the lab stamp.

### 6. New feature: Polaroid camera (Film mode)

- [x] **6.1 Aspect:** viewfinder locked to the Polaroid frame (square). → 1.3.1 · 2026-10-06 · 4a676b7 (build 13)
- [x] **6.2 Corkboard frame:** shown on the corkboard with an authentic
  Polaroid frame. → 1.3.1 · 2026-10-06 · 4a676b7 (build 13)
- [x] **6.3 Handwritten note:** type a note at the preview stage; it's drawn in
  a handwritten font on the bottom border. → 1.3.1 · 2026-10-06 · 4a676b7 (build 13)
  Typed in the print viewer: Write button, or tap the bottom border.
- [x] **6.4 Export:** the white border and note are baked into saved and shared
  images. → 1.3.1 · 2026-10-06 · 4a676b7 (build 13)
- [x] **6.5 Development time:** 20 seconds. → 1.3.1 · 2026-10-06 · 4a676b7 (build 13)
- [x] **6.6 Darkroom visual:** the Polaroid visibly fades in as it develops. → 1.3.1 · 2026-10-06 · 4a676b7 (build 13)

### 7. New stock / camera pipeline

- [x] **7.1 Consistent pipeline:** adding a film stock or camera should touch
  as little code as possible. Film and Digital each follow one consistent
  pattern. → 1.3.1 · 2026-10-06 · 4a676b7 (build 13)
  Every trait lives on the catalog entry; a contract test checks each one.
- [x] **7.2 Intake form:** a fill-in sheet for each new stock or camera. See
  [`NEW_CAMERA_FORM.md`](NEW_CAMERA_FORM.md). Draft; fields marked *(after
  7.1)* go live once 7.1 lands. → docs only · 2026-10-06

### 8. Look quality (requested 2026-10-06)

- [~] **8.1 Film and digital looks:** the looks don't yet behave like the real
  formats and can read as a cheap filter. Plan to iterate (see chat): reference
  contact sheets per look, an on-phone tuning screen, then fixes per stock.
  - [x] Ektar 100 against Gabe's 5 reference scans: azure skies (not navy),
    warm true reds, golden yellows, deep greens, deep slightly warm blacks,
    clean highlights, less halation. → 1.3.8 · 2026-10-06 · c9b7554 (build 23)
  - [x] Grain rebuilt for every stock: real grain structure (crisp, clumpy,
    mostly luminance) instead of soft blurred noise; strength sets amount and
    size (weak barely there, strong obviously film). Ektar Normal matches the
    scans. → 1.3.8 · 2026-10-06 · c9b7554 (build 23)
  - [x] Portra 400 against Gabe's 5 reference scans, as the stock that reads
    most obviously as film: green-teal shadows, warm cream highlights, soft
    contrast, peachy skin, visible grain matched to the scans.
    → 1.3.9 · 2026-10-06 · 1c9e691 (build 24)
  - [x] HP5 400 against Gabe's 4 reference scans: neutral, deep blacks,
    stronger contrast, crisp heavy grain that builds toward the highlights
    (as B&W negatives do), grey (not orange) glow round lamps.
    → 1.3.10 · 2026-10-06 · (pending)
  - [ ] Polaroid 600, Super 8 and the digital bodies: waiting on reference
    photos.
- [x] **8.2 Film defects:** small, tasteful flaws here and there, different on
  every frame (most have none worth noticing): dust specks, the odd hair, a
  faint scratch along the film, a rare light leak. Developed photos only.
  → 1.3.9 · 2026-10-06 · 1c9e691 (build 24)

### 9. Distribution (requested 2026-10-06)

- [x] **9.1 iPhone build:** the CI .ipa failed ("sandbox is not in sync with
  the Podfile.lock"). Dropped the Podfile; plugins come in as Swift Packages.
  → build 19 · 2026-10-06 · 1ced0ae
- [~] **9.2 Proper signing + Play Store:** a private upload key (GitHub
  secrets) replaces the public test key; CI also builds an .aab for the Play
  Console internal testing track, so installs come from Play with no
  warning. Signing → 2026-10-06 · cc84d67 (secrets added; first private-key
  build is the next push). Play Console waits on Gabe's ID check; later, CI
  uploads each build to Play by itself.
