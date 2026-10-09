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
    → 1.3.10 · 2026-10-06 · 286ae6f (build 25)
  - [x] Polaroid 600 against Gabe's 5 reference scans: washed-out cream
    highlights (never white), navy-teal shadows, very compressed colour;
    frequent instant-film flaws (sparkles, roller streaks, a ragged
    undeveloped edge, a fogged corner); the frame everywhere in the app is
    now off-white with an embossed texture instead of flat white.
    → 1.3.11 · 2026-10-06 · a085f1e (build 26)
  - [x] Super 8 against Gabe's 4 reference scans: always landscape (a
    landscape slice when the phone is upright); reels are full-gate scans
    with the sprocket hole on the left and slivers of the neighbouring frames,
    in the viewfinder too (rotates with the phone); faded colour (lifted
    blacks, soft highlights, olive mids), soft focus, clearly visible
    flicker, more dust / hairs / scratches and the odd warm flare.
    → 1.3.12 · 2026-10-06 · 667a263 (build 27)
  - [ ] The digital bodies: waiting on reference photos.
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

### 10. Requested 2026-10-06 (after build 27)

- [x] **10.1 Super 8 REC badge:** the film counter is enough; no REC badge in
  the Super 8 viewfinder. → 1.3.13 · 2026-10-06 · fae6ed4
- [x] **10.2 Projector player:** a deck under the screen: the reel with a
  masking-tape label (tap to rename the reel and its file), an amber dial
  with a needle to wind to a point, a drum counter for the time left, and
  piano keys (start, prev, rewind, play/pause, fast forward, next). Fast
  forward / rewind spin up like the machine (smeared picture, rolling frame
  line, harder flicker, sound off) and stop at the ends. No feet counter;
  no swiping between reels. → 1.3.13 · 2026-10-06 · fae6ed4
- [x] **10.3 Polaroid note box in dark mode:** the box is now the print's
  own paper with felt-tip ink, readable in light and dark mode.
  → 1.3.13 · 2026-10-06 · fae6ed4
- [x] **10.4 Darkroom branding** on the artwork and elsewhere; the rabbit
  logo used sparingly, a pixel version in Windows 98. In-app (rabbit on the
  camera bodies' top bar and the print-back lab stamp; pixel rabbit on the
  Start button, Start menu and About box; DCIM folder shown as 100DRKRM)
  → 1.3.14 · 2026-10-06 · 40ae988. Artwork re-rendered at 1024 px with
  DARKROOM labels, the rabbit on the film boxes / cartridge / instant
  camera and a darker film leader → 1.3.15 · 2026-10-06 · 4775de3
- [x] **10.5 Repository tidy-up**, README, repository image: README
  rewritten; CI runs `flutter analyze` + `flutter test` and only publishes a
  build that passes; `pubspec.lock` committed; the old zip-upload step
  removed; render tool files ignored properly; `docs/social_preview.png`
  (made by `make_icons.py`) for GitHub's social preview. → (no app change) ·
  2026-10-06 · 15a92e3

### 11. Requested 2026-10-06 (after build 31)

- [x] **11.1 Google Play:** Gabe registered the app in the Play Console as
  `com.dingo.darkroom`; the app id moves there (Kotlin package too, and the
  iOS bundle id via `--org com.dingo`). CI uploads each `main` build's .aab
  to the internal testing track once the `PLAY_SERVICE_ACCOUNT_JSON` secret
  is set; GitHub Releases keep the APK/IPA. Privacy policy in
  `docs/PRIVACY.md`. → 1.3.16 · 2026-10-06 · 0093c76. First automatic
  upload to Play: build 35 (2026-10-07).
- [x] **11.2 iPhone develops while closed:** it already did (prints carry an
  absolute ready time and iOS notifications are scheduled ahead); the gap
  was a shot still processing when you leave the app, which iOS paused until
  the next launch. The app now asks iOS for ~30 s of background time while
  shots are processing. No battery prompts. → 1.3.17 · 2026-10-06 · 9db90d4
- [x] **11.3 Upside-down viewfinder on Galaxy S10+ (Android 12):** every
  look, both cameras. The phone runs Impeller on GLES; since Flutter 3.45
  the engine no longer needs the shaders' GLES y-flip, so ours flipped the
  picture. Removed it (photos were fine: they're rendered on the CPU).
  → 1.3.18 · 2026-10-07 · 479ca98
- [x] **11.4 Play Store page from the repo:** title, short and full
  description, icon and feature graphic in `fastlane/metadata/android/en-US/`,
  published by `play-listing.yml`; Play's "What's new" is now the version
  plus the newest About line (was the commit subject). → (no app change) ·
  2026-10-07 · 9e1513b
- [x] **11.5 Store listing language:** the app's default language is
  English (Australia), so the listing and "What's new" move to `en-AU`.
  → (no app change) · 2026-10-07 · 6f31c8c

### 12. Requested 2026-10-07 (after build 38)

- [x] **12.1 Projector keys:** REW / F.FWD run only while held (the reel
  carries on playing on release if it was playing); START still spools
  back with one press. No tap-to-play on the screen any more.
- [x] **12.2 Projector stuck after the end:** after a reel ran out and was
  rewound (or the needle moved), PLAY spun the reel but the picture didn't
  move. A reel that has ended now re-threads a fresh player on PLAY, and a
  watchdog re-threads once if the picture doesn't move after PLAY.
- [x] **12.3 Dial lag:** seeks are coalesced (one in flight, newest target
  waits) and the needle follows the finger, so the frame catches up fast.
  → 1.3.19 · 2026-10-07 · 7b5dd65

### 13. Requested 2026-10-07 (after build 39)

- [x] **13.1 Print corner flip:** bigger tap target round the dog-ear
  (46 px, the fold itself unchanged).
- [x] **13.2 Projector dial:** the frame didn't follow the needle and froze
  for a second after letting go. The reel now pauses while the needle is
  dragged and seeks are spaced out so each frame gets drawn; it runs on
  afterwards if it was running.
- [x] **13.3 Swap swoosh** 70% quieter.
- [x] **13.6 Polaroid artwork:** the print now comes straight out of a slot
  under the lens (forward, image up) instead of hanging off the bottom.
- [x] **13.7 Zoom rocker:** bigger (100x40), and sliding across switches
  W/T; the rocker claims the touch so a slide never tosses the camera.
- [x] **13.8 Volume buttons:** the shutter on every camera (Android). New
  setting "Volume buttons zoom": digital bodies zoom with them instead.
- [x] **13.9 Swap dead zone:** no camera toss from the bottom gesture strip.
- [x] **13.12 Viewfinder dropping out (Pixel 9 Pro):** the camera was closed
  on every "inactive" blip (Android sends it for focus changes), so it kept
  closing and reopening. Now only a real background closes it; errors wait
  a moment before reopening. Win98 Help > Camera Log shows the camera's
  recent events if it happens again.
- [x] **13.4 Projector key clicks:** a heavier clunk on press, a lighter
  tick on release (synthesised, `tool/sfx/make_sfx.py`).
- [x] **13.5 Windows 98 sounds:** a soft click on buttons, menus and the
  Start menu; a bong for error boxes, a ding for warnings (questions stay
  quiet); a short chime when leaving the explorer. All original sounds.
- [x] **13.10 Run...:** RABBIT, DEVELOP, PING, README and MINESWEEPER open
  little programs (any case, with or without .exe/.bat/.txt); Tip of the
  Day hints at them; unknown names get the classic "Cannot find the file".
- [x] **13.11 Gallery buttons:** film shows the latest print as a little
  photograph on a second one; digital shows it on a camera review LCD.
- [x] **13.13 Shut Down:** sky-and-clouds shutdown screen with the rabbit
  and an original shutdown tune, "It's now safe to turn off your
  computer", then the CRT switching off (picture collapses to a white line,
  then a dot). Tap to skip ahead.
  → 1.3.20 · 2026-10-07 · 381b2fe

### 14. Requested 2026-10-07 (after build 40)

- [x] **14.1 Win98 controls:** menu titles are bigger targets and open on
  touch-down; with a menu open, touching another title switches straight
  to it (one tap, not two). Toolbar buttons and window caption buttons
  have bigger touch areas; menu rows are taller.
- [x] **14.2 Zoom motor sound:** a quiet geared whir loops while a digital
  body's zoom moves (`zoom_motor.wav`, `Sfx.zoomMotor`).
- [x] **14.3 Games in Start > Run:** SOL (Klondike, tap a card to move it),
  BRICKS (brick breaker), PINBALL (Space Rabbit Pinball: hold either half
  for that flipper, hold to pull the plunger, light R-A-B-B-I-T). Listed in
  README.TXT and hinted in Tip of the Day.
  → 1.3.21 · 2026-10-07 · 9a112d5

### 15. Requested 2026-10-07 (after build 41)

- [x] **15.1 Shut Down:** no confirmation box and no "safe to turn off"
  screen: straight to the shutdown screen, then the CRT switch-off. The
  logo is now chunky pixel art (`PixelRabbit`) with a trail of loose
  pixels; the clipped left edge is fixed (DarkroomMark's layer was too
  tight for the colour split).
- [x] **15.2 Zoom at end of travel:** holding the rocker at the limit no
  longer re-triggers (motor + haptics) on every finger twitch.
- [x] **15.3 Volume buttons:** didn't work. Now taken in MainActivity
  (`darkroom/volume`) while the camera is on screen, so Android can't turn
  them into a volume change first.
- [x] **15.4 Bricks:** the bat stays inside the field.
- [x] **15.5 Sound levels:** every sound 50% quieter.
- [x] **15.6 Rabbit badge:** off the top bar; it's now pressed into the cap
  of the lens-flip button.
- [x] **15.7 Win98 login chime** when the explorer opens.
  → 1.3.22 · 2026-10-07 · aea0f03
- [x] **15.8 Mode tag:** no longer part of the body: it floats over the
  desk, tucks away (with a wind-up) as a swap starts and springs back out
  (elastic) when the new body has settled.
- [x] **15.9 Shutters:** digital = a squared compact shutter key in a
  brushed bezel (camcorder adds a red record dot), quiet deep click;
  film = a chrome release in the hub of a film-advance lever that swings
  out and springs home every frame, mechanical clack + ratchet; Super 8 =
  a red RUN button in a ribbed lock collar that stays in (lamp lit) while
  filming. They swap with a pop when changing body; the volume-key shutter
  plays the same stroke and sound (`shutterPulseProvider`).
- [x] **15.10 Strap and lug:** a machined lug with a slot on the side
  wall; the leather strap has a split ring, a folded end tab through a
  keeper, edge stitching, a rounded highlight and a buckle; the digital
  wrist cord is braided with a cord lock and a connector loop.
  → 1.3.23 · 2026-10-07 · 60df9c0
- [x] **15.11 Corkboard:** slides in from the left (with a little
  overshoot) inside a wooden picture frame (mitred, grained), with a deep
  woody swoosh in and out (`cork_swoosh.wav`).
- [x] **15.12 Minesweeper (WINMINE):** the real thing: LED mine counter and
  timer, smiley (worried while pressing, dead, cool), Beginner 9x9/10 and
  Intermediate 16x16/40, tap to dig, hold to flag, tap a satisfied number to
  clear round it, first dig always safe. Rules tested.
- [x] **15.13 Pinball + game sounds:** Space Rabbit rebuilt in the spirit of
  Space Cadet: a mission panel (score, ball, rank, mission), three attack
  bumpers, slingshots, in/outlanes, FUEL drop targets, a wormhole that
  throws the ball back in up top, R-A-B-B-I-T rollovers, missions that
  promote you Cadet -> Admiral; start-up tune, flipper, bumper, sling,
  target, warp, launch and drain sounds. Bricks bops and blips, cards snap
  and riffle, mines go boom; win and lose jingles.
  → 1.3.24 · 2026-10-07 · 98b1939
- [x] **15.14 Strap through the lug:** the strap was drawn at the body's
  front edge while the lug sits half the wall's depth back, so the ring
  floated beside the slot. The strap now has its own matrix at the lug's
  depth and the ring / cord loop is centred on the slot.
  → 1.3.24 · 2026-10-07 · b340f7c

## 16. Cork, slide-in, Super 8 turning (2026-10-07)

- [x] **16.1 Super 8 viewfinder turning:** turning the phone used to snap
  the film strip into its new orientation (it sat still until the phone was
  most of the way round). Now the new layout starts where the old one was
  and swings round (rotating and growing into place, `_StripTurn` in
  viewport.dart).
- [x] **16.2 Corkboard overscroll:** no more bounce or stretch past the
  ends (clamping physics, no overscroll indicator), so the prints never
  drift off the cork.
- [x] **16.3 Cork texture:** rebuilt after Gabe's sample: small, irregular
  pressed granules of varied size and tone (pale tan to orange-brown, the
  odd dark one), domed and lit from the top left, with dark crevices that
  are tight in places and open in others; rendered at 2x. Kept the wear:
  coffee rings (wobbly rims, the odd double ring and drip), water marks,
  pin holes, sun-faded patches.
- [x] **16.4 Corkboard slide-in:** slower (860 ms), no overshoot: it eases
  in and comes to rest against the edge, with a soft wooden thud and a light
  haptic as it lands (`cork_thud.wav`; the swoosh no longer has a knock).
  → 1.3.25 · 2026-10-07 · 27dcc29

## 17. Corkboard swipe, edge to edge, Super 8 fixes (2026-10-07)

- [x] **17.1 Super 8 sprocket hole:** during the swing (16.1) the hole
  floated on its own: a Flutter transform round an ImageFilter.shader only
  turns the shader's input. The swing is now done inside film.frag
  (`uSpin`, floats 29-30), so strip, hole and picture turn as one
  (`super8_strip_shader_test`: half a turn = the same image upside down).
- [x] **17.2 Polaroid note after saving:** a note added after Save isn't in
  the gallery copy. Gabe picked option 2 (see 18.1).
- [x] **17.3 Corkboard thud:** re-synthesised as a struck wooden body (a
  short noise knock ringing a few low, damped modes, plus a dull thump), no
  pitched tones.
- [x] **17.4 Edge to edge:** the corkboard's content scrolls right up to the
  frame, under the status and home bars (no SafeArea strip where only cork
  showed); it still starts and ends clear of them.
- [x] **17.5 Swipe for the corkboard:** in film mode, a clear swipe right on
  the camera brings the corkboard in (triggered, not dragged); a swipe left
  on the board puts it away. Touches from the side strips are left to the
  phone's back gesture.
- [x] **17.6 Re-grab during spring-back:** a half-hearted swap no longer
  locks the body while it springs back: touch it again and the drag carries
  on from where it is.
- [x] **17.7 Bigger film shutter:** release dome 22 (was 16.5), collar 31
  (was 25), longer lever.
- [x] **17.8 Quieter:** every sound 30% down (`Sfx.master = 0.7`).
- [x] **17.9 More settings:** Gabe picked haptics + sound effects (18.3).
- [x] **17.10 Super 8 grain:** 0.75x on every strength (0.085 -> 0.064).
- [x] **17.11 Super 8 / camcorder audio:** both, no whir/whine (18.4).
  → 17.1, 17.3-17.8, 17.10: 1.3.26 · 2026-10-07 · 3bf7683

## 18. Darkroom close-up, quieter, settings, tape audio (2026-10-07)

- [x] **18.1 Polaroid note after saving:** changing the note on a print
  that's already in the photo library asks "Save a copy with the note?"
  (the old copy can't be changed; it stays).
- [x] **18.2 Sounds still too loud / volume not changing:** the 30% cut was
  only -3 dB and the player's volume may not apply on the phone, so the
  levels are now baked into the .wav files (`make_sfx.py` LEVELS, another
  0.35x on top of the old levels, about -9 dB) and played at full scale.
- [x] **18.3 Settings:** Sound effects and Haptics switches (camera settings
  sheet and Win98 Options). `Sfx.enabled`, `Haptics` wraps HapticFeedback.
- [x] **18.4 Tape audio:** Super 8 = sound stripe (mono, thin band, gentle
  compression, wow + flutter, faint hiss); camcorder = tape (muffled, hiss
  pumped by the AGC, slight wow, head click at the start). LGPL filters
  only, run through desktop ffmpeg in `video_audio_ffmpeg_test`.
- [x] **18.5 High-resolution film setting:** came with the original code,
  never requested. Gabe: drop it. Film always uses the 1080p-class stream.
  → 1.3.29 · 2026-10-07 · e809741
- [-] **18.6 Logo eyes:** blue X on the left, red X on the right (opposite
  their fringe colours). Sample sent; Gabe: keep the old logo for now.
- [x] **18.7 Darkroom close-up:** tap a print / Polaroid / reel in the
  darkroom strip for a big view of it developing live; board greyed
  behind; tap anywhere to go back.
- [x] **18.8 Print viewer over the board:** the viewer is a see-through
  route; the corkboard stays behind, dimmed.
- [x] **18.9 Corkboard thud too quiet:** its modes were below what a phone
  speaker plays; moved up to ~175-1300 Hz and made louder.
  → 18.1-18.4, 18.7-18.9: 1.3.27 · 2026-10-07 · 466b3f3

## 19. Corkboard swipe wiggle (2026-10-07)

- [x] **19.1** Swiping right in film mode (the corkboard gesture) no longer
  nudges the camera body before the board comes in.
  → 1.3.28 · 2026-10-07 · e8f614b

## 20. Big batch: Win98 swipe, crash reports, close-up, volume (2026-10-07)

Answers: 3D buttons pre-rendered; crash reports on the phone only; Win98
comes in with a CRT power-on; start screen also asks for a name; Win98
swipe is LEFT in digital mode (right still swaps to film).

- [x] **20.1 Swipe jiggle:** the body no longer reacts at all to a swipe
  the way with no camera (no visual switch, no haptic until it moves).
- [x] **20.2 Tap off a photo** (on the dimmed board) puts it down.
- [x] **20.3 Crash reports:** kept on the phone (`CrashLog`): uncaught
  Dart/Flutter errors plus Android's own record of crashes / freezes
  (ApplicationExitInfo, channel `darkroom/crash`). Win98 Help > Crash
  Reports, with Copy and Clear.
- [x] **20.4 Super 8 "Input contains NaN" at the AAC encoder:** every audio
  chain now starts and ends with a NaN/clip guard (`_clean`); desktop
  ffmpeg test feeds it NaN.
- [x] **20.5 Ruined shots:** a darkroom excuse (light got in, the cat...)
  with Copy error report (`errorReport`); Win98 keeps its error box and
  gets a Copy button.
- [x] **20.6 Close-up:** stage in full words (Developing, Stop bath...) on
  an 80% black pill, a roomier tray, water washing over the paper.
- [x] **20.7 Volume:** a Sound effects slider (0 = off, half by default;
  player volume = level²) in settings and Win98 Options, with a sample
  sound. (The baked files peak around -30 dBFS.)
- [x] **20.8 3D shutter buttons:** path-traced layers (`tool/render/items/shutter.js`:
  base, cap up/down, film lever) in `assets/shutters/`, stacked by
  `_SpriteShutter`; the cap and lever slide against the base as the body
  tips (`BodyYaw`, `Raised`), and the gallery / stock buttons get the same
  depth. During a toss only the viewfinder is frozen
  (`CameraViewport.freeze`), so the controls stay live.
- [x] **20.9 Win98 swipe:** swipe left in digital mode; the explorer
  switches on like a CRT (dot, line, opens, degauss wobble).
- [x] **20.10 Slow Polaroid share:** the framed export is cached per
  picture + note and capped at 2048 px (pure-Dart JPEG encode).
- [x] **20.11 Start screen:** six pages (hello, film, digital, gestures,
  your name, permissions with reasons and one Allow all), friendly and a
  bit cheeky; shown once (`PrefKeys.onboarded`), replay from Win98 Help >
  Welcome Tour. The name goes on the lab stamp and in Tip of the Day.
- [x] **20.12 Carousel:** closing is a trigger (no finger tracking, leaves
  at speed); held sideways it rises from the user's bottom edge and the
  hero flight is skipped (it flew sideways then snapped).
- [x] **20.13 Sprocket hole during a toss:** the moving body shows its
  at-rest snapshot; since 1.3.31 only the viewfinder is frozen
  (`CameraViewport.freeze`) and the controls stay live.
- [x] **20.14 AppInfo.version** was stuck at 1.3.24; a test now ties it to
  pubspec.
  → 20.1-20.7, 20.9, 20.10, 20.12-20.14: 1.3.30 · 2026-10-07 · 401a16c
  → 20.8, 20.11: 1.3.31 · 2026-10-07 · bab2c93

## 21. Real 3D shutters, monitor slide, profile, battery (2026-10-08)

Answers: turntable renders, no 2D/3D switch.

- [x] **21.1 3D shutters:** the sliding-layer depth trick read as wrong (the
  parts lost their places relative to each other). Now each shutter is
  path-traced as a whole from 9 angles (-48..48 degrees,
  `shutter_<kind>-all-a<deg>`) plus pressed; the app shows the frame for
  the body's yaw (neighbours cross-fade) and stretches it back by
  1/cos(yaw). Film's lever stroke uses the separate layers (body still).
  The gallery / stock buttons are flat again.
- [x] **21.2 Win98 monitor:** the explorer slides in from the right inside
  an off-white plastic monitor (`ExplorerMonitor`: bezel, recessed screen,
  power lamp, badge) with the corkboard's whoosh and knock, and slides back
  out however it's closed (replaces the CRT power-on).
- [x] **21.3 Change your name:** Start > User Profile.
- [x] **21.4 LCD panel + battery:** one fixed size for every digital body
  (fits the longest name / status); the battery gauge is the phone's own
  charge (`darkroom/battery` channel: Android BatteryManager, iOS
  UIDevice), and the camcorder OSD burns in the gauge as it was when the
  take was shot (`VideoJob.batteryBars`).

## 22. Version 1.4, tidier history, faster sharing (2026-10-08)

- [x] **22.1 Version 1.4.0:** the batch since 1.3.25 counts as a new
  version.
- [x] **22.2 Revision history:** Help > About shows each version as a few
  short bullets. Play's "What's new" now comes from `AppInfo.latest`.
- [x] **22.3 Slow share on the corkboard:** Polaroids were framed and
  JPEG-encoded at full size on the first share (Win98 files are shared as
  they are). Now the board makes each Polaroid's share file in the
  background when it opens (`warmShareExport`, one at a time, single
  flight), and the export decodes straight at 2048 px.
- [x] **22.4 Ship while rendering:** 1.4.0 goes out with flat (layered)
  shutters (`_SpriteShutter.turntable = false`); the 3D frames follow.
  → 21.2-21.4, 22.1-22.4: 1.4.0 · 2026-10-08 · 59bddc5

## 23. CRT switch-off, steady LCD, SD Empty, 3D shutters on (2026-10-08)

- [x] **23.1 CRT shutdown:** it squashed the live screen (and repainted its
  blurred clouds) every frame, so it stuttered and the squeeze looked
  cheap. Now one snapshot drawn by a painter: the picture snaps to a
  white-hot line in ~0.1 s, pulls in to a dot in ~0.1 s, and the phosphor
  glow lingers about a second (gradients, no blur pass).
- [x] **23.2 Digital LCD:** no more fade / slide when switching camera; the
  panel stays mounted and only its readout changes.
- [x] **23.3 Gallery button** on an empty card says SD EMPTY.
- [x] **23.4 Turntable frames on** (21.1): 40 frames, ~870 KB.
- Monetization: parked until the app is further along (Gabe).
  → 21.1, 23.1-23.4: 1.4.1 · 2026-10-08 · 562cea4

## 24. Polish toward a public release (2026-10-08)

- [x] **24.1 W / T flicker** on switching camera: the labels dimmed while
  the camera reopened (zoom briefly unavailable); now dimmed only at the
  end of travel.
- [x] **24.2 LCD readout** switches with a quick out-then-in fade (~0.2 s).
- [ ] **24.3 3D buttons** "pretty bogus": answered (cost of full 3D);
  decision pending, tracked in docs/RELEASE.md.
- [x] **24.4 Accidental panel swipe:** once a touch has moved the camera
  (a swap began), letting go can't open the corkboard / explorer.
- [x] **24.5 Viewfinder held** while the corkboard / explorer / picker is up:
  the last frame stays until the camera is streaming again.
- [x] **24.6 Empty floppy** says "There are no files on the floppy disk."
- [x] **24.7 Release roadmap:** docs/RELEASE.md (Play + App Store
  checklists, incl. a trademark pass on stock / Windows names).
  → 24.1, 24.2, 24.4-24.7: 1.4.2 · 2026-10-08 · 3f13749

## 25. Our own names (2026-10-08)

- [x] **25.1 Trademark pass:** films renamed after their box art: Ektar 100
  → Vivid 100, Portra 400 → Portrait 400, HP5 Plus 400 → Classic 400,
  Polaroid 600 → Instant 600 (ids unchanged, so saved shots keep working).
  Super 8 stays (it's the format's name). Minesweeper → Minefield (Run
  MINES; the old commands still work). No "Windows" in the app's own text,
  About history or the store listing ("Darkroom 98", "late-90s desktop").
  Solitaire, Notepad, My Computer kept (generic words).
  → 25.1: 1.4.3 · 2026-10-08 · f04cacc

## 26. 3D controls, debug window, steady still (2026-10-08)

- [~] **26.1 3D controls** (24.3 decided: worth it; the live preview read as
  "budget", so a path-traced film body is being tried:
  `tool/render/items/filmback.js`, first test render lost its textures;
  parked for 27): every control (shutter,
  flash, zoom, flip, gallery) a 3D object turning with the body; body stays
  2D. First a live three.js preview page to tune the look
  (`tool/preview3d/index.html`, published as an artifact), then renders.
- [x] **26.2 3D / flat setting**: Settings + Win98 Options, asked on a new
  tour page ("How fancy?"). Today it switches the shutter's turn.
- [x] **26.3 Debug window** (Help > Debug...): scrolling tool list with
  room for more: Camera Log, Crash Reports, Welcome Tour, Tour On Next
  Start, Develop Everything Now, Frame Timing Graphs, Slow Motion, System
  Info, Test Crash.
- [x] **26.4 Frozen viewfinder squash**: the box fell back to 16:9 while the
  camera was closed and the still was stretched to it; it now keeps the
  last stream's shape and the still is never stretched.
  → 26.2-26.4: 1.4.4 · 2026-10-08 · 94fd5b0

## 27. Older phones (Galaxy S10+) (2026-10-08)

- [x] **27.1 Performance Recorder** (Help > Debug): times every frame,
  labelled by activity (slides, swaps, picker, Win98 menus / windows,
  corkboard scroll, shutter), split into UI thread vs GPU; Performance
  Report with Copy. No Android emulator here (no KVM) and an emulator
  wouldn't behave like the S10+'s Mali GPU anyway, so the phone measures.
- [x] **27.2 Camera restart moved off the slide**: it reopened as the panel
  began sliding away; now after the exit animation (picker: after it closes).
- [x] **27.3 No live viewfinder under a held still** (swap, panels, picker):
  its look shader was still running every camera frame underneath.
- [x] **27.4 Cork wall painted ahead**: tiles cached between visits and the
  first two drawn 2 s after the camera opens (the shader ran in the
  board's first frame).
- [x] **27.5 S10+ report** (WQHD+ 1440x2872 @3.5x, 60 Hz): GPU-bound
  everywhere (UI thread fine). Worst: Win98 slide-in / menus / windows
  (GPU 40-54 ms: full-screen blurs in the monitor bezel and the slide's
  30 px shadow, redrawn every frame on Impeller), the swap (desk shadow
  + strap blurs under a 3D transform), and idle camera ~19 ms (viewfinder
  shader). Fixed: bezel recess and lamp glow as gradients, slide shadow
  a gradient strip, desk shadow a baked low-res image (`SoftShadow`),
  strap/cord shadows as layered strokes (`softStroke`).
- [x] **27.6 Performance mode** (Settings + Win98 Options, off by default):
  viewfinder without halation (6 of 10 texture reads per pixel; photos
  unchanged) and the body swapped as one picture (`_dragFace`).
- [x] **27.7 Recorder**: unlabelled frames now say which screen was up
  ("idle camera / corkboard / win98"); the report shows Performance mode.
  → 27.1-27.4: 1.4.5 · 2026-10-08 · e7b33ff; 27.5-27.7: 1.4.6 · 2026-10-08 · 02ab546

## 28. Super 8 grain, closed testing, v1.5 full 3D (2026-10-08)

- [x] **28.1 Super 8 grain** still too strong: old Weak (0.4x amount,
  1.35x finer) is the new Normal (0.0256, res 513); Weak / Strong scale
  from it.
- [x] **28.2 Promote 1.4.7 to closed testing.** → build 63 promoted · 2026-10-08
- [x] **28.3 v1.5: full 3D bodies** → 1.5.0 · 2026-10-08 · f36b317: the whole camera body and every
  control path-traced; premium, cost no object; must stay smooth on the
  S10+ and fit every screen shape. Rendered in Blender Cycles
  (`tool/render/blender/`), drawn from sprites (`photo_body.dart`);
  3D controls off = the classic bodies; Performance mode = face-on sprites.
- [x] **28.4 3D by default** → 1.5.0 · 2026-10-08 · f36b317: no "How fancy?" page in the tour; 3D on,
  switch it off in Settings.
- [x] **28.5 Landscape** → 1.5.0 · 2026-10-08 · f36b317 for the corkboard, print viewer, projector and
  Darkroom 98 (`UprightApp`: the whole UI turns on screens that opt in).

## 29. 1.5 on-device fixes (2026-10-08)

- [x] **29.1 Film shutter** → 1.5.1 · 2026-10-08 · 89fb6be: the advance lever draws over the release
  while it's pressed (the release sinks under it).
- [x] **29.2 Shadows pop** → 1.5.1 · 2026-10-08 · 89fb6be in and out while the body turns.
- [x] **29.3 Black bar** → 1.5.1 · 2026-10-08 · 89fb6be at the body's edge mid-swap (panel doesn't
  reach the side wall).
- [x] **29.4 One switch** → 1.5.1 · 2026-10-08 · 89fb6be: 3D off = performance mode on (merge the two
  settings).
- [x] **29.5 Live viewfinder** → 1.5.1 · 2026-10-08 · 89fb6be while the body flips (when 3D is on).
- [x] **29.6 Selfie flip button** → 1.5.1 · 2026-10-08 · 89fb6be does nothing (both bodies).
- [x] **29.7 Landscape for real** → 1.5.1 · 2026-10-08 · 89fb6be: corkboard, projector, Darkroom 98
  really rotate the phone (system bars and gestures on the right edges);
  panels slide in the way they were swiped, no jump (the jump: heroes made
  the route read "arrived" the moment it was pushed).
- [x] **29.8 Viewfinder frame** → 1.5.1 · 2026-10-08 · 89fb6be sometimes in the wrong place / size for a
  moment (turned frames were 9-sliced as if face-on; now cropped per turn).
- [ ] **29.9 More 3D depth**: options shown (taller parts, stronger tilt,
  deeper shadows); parked for now.

## 30. Landscape Win98 space, button animations (2026-10-08)

- [x] **30.1 Landscape Darkroom 98** → 1.5.2 · 2026-10-08 · 5534fe3 wastes space round the edges: status
  bar, cutout margin, bezel; give the file list the room.
- [x] **30.2 Film aspect dial** → 1.5.2 · 2026-10-08 · 5534fe3 is lackluster: animate it.
- [x] **30.3 Click animation** → 1.5.2 · 2026-10-08 · 5534fe3 on the camera's keys (flash, ratio, settings
  on digital, and any others that need it).

## 31. Closed testing (2026-10-08)

- [x] **31.1 Promote 1.5.2 to closed testing.** → build 73 promoted · 2026-10-08

## 32. Film print viewer gestures (2026-10-09)

- [x] **32.1 Pinch vs swipe** → 1.5.3 · 2026-10-09 · 788320c: zooming tends to start a swipe to the next
  print; make paging less eager, zoom win.
- [x] **32.2 Double tap** → 1.5.3 · 2026-10-09 · 788320c zooms in, again zooms back out; double tap and
  slide zooms gradually.
- [x] **32.3 Swipe up or down** → 1.5.3 · 2026-10-09 · 788320c puts the print back (closes the viewer).

## 34. Landscape polish (2026-10-09)

- [x] **34.1 No pop**: panels started portrait and popped into landscape.
  Now laid out landscape from the start of the slide (`UprightPage`),
  Android cuts to the real rotation (JUMPCUT). → 1.5.4 · 2026-10-09
- [x] **34.2 Respect auto-rotate**: off = nothing turns (Android reads the
  setting, `darkroom/rotation`; iOS keeps to its own lock). → 1.5.4 · 2026-10-09
- [x] **34.3 Win98 borders**: maximized window, thin bezel, cutout margin
  capped, scaled for short phones; checked on four phone sizes. → 1.5.4 · 2026-10-09

## 35. Win98 size, loading (2026-10-09)

- [x] **35.1 Win98 window size**: portrait gap under the status bar, a
  strip down the side in landscape. The monitor's bezel now takes the
  status bar / gesture strip / cutout; the window fills its screen.
- [x] **35.2 Close button in the corner**: landscape keeps 24 dp of bezel
  at the sides, clear of the phone's rounded corners.
- [x] **35.3 Slow textures**: the launch screen stays up until the camera
  art is decoded; the art stays in memory (`ArtCache`), so swapping bodies
  never reloads it.
