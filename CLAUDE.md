# Darkroom — notes for Claude

Read this first. It's the hand-off from the earlier development sessions
(the app was called **RetroCam** until v1.2). Deeper technical docs:
`docs/DEVELOPMENT.md`.

## The person and how we work

- Owner: Gabe. Tests on a **Pixel 9 Pro** (Android) and is starting to test on
  an iPhone (sideloaded, no paid Apple developer account yet).
- Usually works from his phone. Keep replies short and plain.
- For big revisions, ask clarifying questions first, then implement.
- He's often low on usage: keep changes focused, don't gold-plate.
- After every push that builds, wait for the run; once its `play` job has
  uploaded, wait ~2 more minutes, then send Gabe a push notification
  (PushNotification) that the build is on Google Play: version, build
  number, one-line what's new. If the build or the upload fails, notify
  that instead.
- Every user-visible change: bump `version` in `pubspec.yaml` (raise the
  `+build` number too) and `AppInfo.version` to match (a test checks), set
  `AppInfo.latest` in `lib/core/app_info.dart` to this build's change in
  plain words (it's Play's "What's new"), and when a main idea lands add a
  few-word bullet to the newest `AppInfo.revisions` entry (Help > About
  shows them as bullets; keep them short).
- **Release roadmap:** `docs/RELEASE.md` is the checklist to the public
  Play / App Store release; tick items as they land.
- **Change log:** `docs/CHANGELOG.md` tracks every requested change by item
  number. Mark items `[~]` when starting and `[x] → version · date · commit`
  when they land; add new requests there. New stocks/cameras arrive on the
  form in `docs/NEW_CAMERA_FORM.md`.

## Build & release pipeline

- Unless Gabe says otherwise, **commit and push finished changes straight to
  `main`** so a new APK gets built. Don't push half-done work.
- Push → `.github/workflows/build-apk.yml` builds `Darkroom-N.apk` and, when
  enabled, an unsigned `Darkroom-N.ipa`, and publishes them under **Releases**
  (`build-N`; non-`main` branches are marked pre-release).
- iOS build runs on a macOS runner. On a private repo it only runs if the
  commit message contains `[ios]` or the workflow is started by hand (Mac
  minutes cost 10x). The .ipa is unsigned; Gabe signs and installs it with
  Sideloadly + a free Apple ID (expires every 7 days).
- iOS: deployment target 15.0 (patched into the generated Xcode project by
  CI). Every plugin is a Swift Package, so there is **no Podfile**: adding
  one makes Flutter run CocoaPods and the build dies with "sandbox is not in
  sync with the Podfile.lock". `ios/` holds only Info.plist,
  AppDelegate.swift and the AppIcon set; CI generates the rest.
  Developing never needs the app running: prints store an absolute
  `ready_at`. Android re-arms notifications with WorkManager; iOS schedules
  them ahead (`scheduleIosBatches`) and holds a ~30 s background task while
  shots are still processing (`BackgroundTime`, channel `darkroom/background`
  in AppDelegate.swift). No battery-optimisation prompts on either.
- `android/` and `ios/` only contain the files we customised. CI runs
  `flutter create --org com.dingo --project-name darkroom --platforms android .`
  to fill in the rest (it never overwrites existing files). Don't delete
  `AndroidManifest.xml` or `android/app/build.gradle.kts`.
- `applicationId` / `namespace` = `com.dingo.darkroom` (the id registered on
  Google Play; was `com.darkroom.darkroom` until 1.3.16); must match the
  package of `MainActivity.kt` (ours, in the repo: gesture channel).
- **Google Play** is the main way Gabe installs now (internal testing
  track). The `play` job in the workflow uploads every `main` build's .aab
  (secret `PLAY_SERVICE_ACCOUNT_JSON`, repo variable `PLAY_RELEASE_STATUS`,
  default `completed`). Play's "What's new" = version + **`AppInfo.latest`**
  (`tool/play/whats_new.py`).
  **Closed testing** (for other testers) is the slow path: the
  `promote-closed.yml` workflow (Actions tab, run by hand) promotes a build
  already on internal testing to the closed track (`alpha`), which Play
  reviews. Internal testing stays the instant path for Gabe.
  The store listing (title, descriptions, icon, feature graphic) lives in
  `fastlane/metadata/android/en-AU/`; `play-listing.yml` publishes it when
  it changes (fastlane supply, same service account). Screenshots aren't in
  the repo yet. Privacy policy for the listing: `docs/PRIVACY.md`.
- Release builds are signed with Gabe's **private upload key** (alias
  `upload`), which CI decodes from the repo secrets `ANDROID_KEYSTORE_BASE64`
  and `ANDROID_KEYSTORE_PASSWORD`. Never commit it. Without the secrets
  (local builds) they fall back to the public test key
  (`android/app/darkroom-test.jks`), which won't install over a
  private-key build. versionCode = CI run number. CI also builds
  `Darkroom-N.aab` for the Play Console internal testing track (Play App
  Signing; once installed from Play, the phone only takes updates from Play).
- Manifest already has `tools:replace="android:maxSdkVersion"` on
  `WRITE_EXTERNAL_STORAGE` (merger conflict with camera_android_camerax).
- Checks: `flutter analyze` and `flutter test` (CI runs both and won't
  publish a release unless they pass). If the session has no Flutter SDK,
  just push and read the GitHub Actions result. `pubspec.lock` is committed.
- UI checks without a phone: `test/*_screens_test.dart` pump screens at
  Pixel 9 Pro size (fail on overflow); `SHOTS=dir FLUTTER_ROOT=<sdk>` also
  saves PNGs with real fonts. `camcorder_osd_ffmpeg_test` runs the camcorder
  filtergraph through a desktop ffmpeg when one is installed.

## Stack

Flutter stable (≥ 3.47, Dart ≥ 3.12), Riverpod 3, `camera` (CameraX),
`ffmpeg_kit_flutter_new_min`, `sensors_plus`, `gal`, `workmanager`,
`flutter_local_notifications`, sqflite (schema v2, migrates itself).

## Things that bite

- **FFmpegKit "min" is the LGPL build.** GPL filters (`boxblur`, `eq`,
  `hqdn3d`, `drawtext`, …) don't exist and make the whole filtergraph fail
  with "Error initializing complex filters". `test/look_and_shader_contract_test.dart`
  has a deny-list; keep it passing (`avgblur` instead of `boxblur`, etc.).
- **Shader uniform layouts** in Dart must match the `.frag` files exactly
  (float order/count, sampler count). The same test checks it.
  `shaders/film.frag` takes 3 samplers: camera, LUT, grain.
- **No GLES y-flip in the shaders.** Since Flutter 3.45 the engine already
  hands `ImageFilter.shader` its input upright on GLES; the old
  `#ifdef IMPELLER_TARGET_OPENGLES uv.y = 1 - uv.y` (still in the dart:ui
  docs) flipped the viewfinder on GLES phones (Galaxy S10+; Pixels use
  Vulkan). The contract test forbids it.
- **Landscape screens (1.5.1)**: routes with `settings:
  UprightApp.landscape` (corkboard, print viewer, projector with the deck
  beside the screen, Darkroom 98 and its viewer) really rotate the app
  once they've slid in and the phone is sideways (`UprightApp` in
  `core/device/upright.dart` calls `setPreferredOrientations` with the
  accelerometer's orientation, so it works with auto-rotate off); back to
  portrait as they slide out, so they slide in/out in portrait, following
  the swipe. The camera (home) is wrapped in `PortraitLock` so it keeps
  its portrait layout underneath. On push, heroes make the route offstage
  for a frame and its animation reads "completed": ignore that (test
  `upright_app_test`). No pop: each landscape page is wrapped in
  `UprightPage`, which lays it out turned (RotatedBox) while the app is
  still portrait and the phone is sideways, so it slides in already
  landscape; MainActivity sets ROTATION_ANIMATION_JUMPCUT so the real
  rotation is invisible. Turning the phone while such a page is up fades
  it out (`UprightApp.veil`; it keeps its layout via `UprightApp.held`),
  turns the app, and fades it back in once the size settles
  (`didChangeMetrics`). Only with auto-rotate on (`AutoRotate`, channel
  `darkroom/rotation`, Android setting + changes); iOS (null) asks for
  portrait + landscape and lets the system turn within its lock. iOS
  Info.plist allows landscape. Turned, the system bars hide
  (immersiveSticky; edgeToEdge back in portrait). Win98: the window
  sits on a strip of desktop; the monitor bezel (`ExplorerMonitor.bezelOf`) takes the system
  insets (status bar, gesture strip; landscape 24 dp sides for the cutout
  and the rounded corners, 4 dp top/bottom; `Win98Safe` the same for
  screens without the monitor), `Win98Scale.factorFor` keeps 420 dp of height (short phones
  scale down); the big Transfer bar is dropped. `explorer_screens_test`
  runs portrait + four landscape phones.
- The app is **portrait** everywhere else. Landscape is detected with the
  accelerometer (`lib/core/device/physical_orientation.dart`); icons rotate in
  place (`Upright` / `UprightBox`) and photos are saved upright. UI reads
  `uprightOrientationProvider` (always portrait while Android's auto-rotate
  is off, so nothing turns); only capture and the Super 8 framing read
  `physicalOrientationProvider`. The print viewer puts its buttons in a
  column on the right in landscape.

## Film engine (`lib/core/processing/film/`)

Each stock is a film model baked into a 33³ 3D LUT (log shaper, per-channel
curves, hue tweaks, split toning). The same LUT drives the live GPU preview
(`shaders/film.frag`), the CPU renderer for stills, and FFmpeg `lut3d` (.cube)
for video. Plus a tileable grain texture, halation and exposure drift.

- Stock ids: `ektar100`, `portra400`, `hp5plus400`, `polaroid600`, `super8`
  (ids name the emulsion each look is modelled on; code only). On screen
  they're **Vivid 100, Portrait 400, Classic 400, Instant 600, Super 8**:
  never show real brand names (Kodak, Ilford, Polaroid, Windows,
  Minesweeper...) in the app or the store listing (1.4.3 trademark pass).
- Film stills capture at the sensor's full resolution (`CaptureQuality.high`
  = `ResolutionPreset.max`; CameraX keeps the preview preview-sized),
  output capped at 8192 (35mm) / 3072 (instant); ~4x the processing of the
  old 1080p stream (runs in the isolate while the print develops).
- Grain (`grain_field.dart`) is a Boolean model: thousands of tiny
  overlapping grains + sparse clumps, crisp (not blurred noise), dye layers
  mostly shared. Drawn at >= 1 px; finer grain is drawn fainter
  (`FilmSpatial.grainTexel`), so preview and small exports read like the
  photo seen at that size.
- Grain strength scales amount and size: weak 0.4x / 1.35x finer, normal,
  strong 2.4x / 0.55x (coarser). Set **per film stock, only in the settings
  menu**. When not "normal", the carousel shows a small tag. Digital cameras
  have no grain setting.
- Ektar 100 (clean, punchy), Portra 400 (the obviously-film stock: soft,
  green-teal shadows, cream highlights, visible grain) and HP5 (neutral,
  deep blacks, heavy grain strongest in the highlights via
  `FilmProfile.grainHighlights`, uniform `uGrainHi`) are tuned against
  Gabe's reference scans; `grain_calibration_test` pins their Normal grain
  to the scans (Ektar ~0.0076, Portra ~0.034, HP5 ~0.025 mid / ~0.055
  bright).
- Defects (`film_defects.dart`): developed stills only (never the
  viewfinder), rolled per frame from the shot's seed: a few dust specks
  (white on negative, dark on instant), sometimes a hair, a faint scratch
  along the film's long side, rarely a warm light leak from a long edge.
  `FilmProfile.defects` sets how often (Portra/HP5/Polaroid 1, Ektar 0.6,
  Super 8 0). Instant film (`negative: false`) gets chemistry flaws instead:
  pinprick sparkles, a little dark dust, milky streaks up from the rollers,
  a ragged undeveloped band along an edge, a fogged corner.
- Polaroid 600 is tuned against Gabe's scans: cream highlights capped well
  below white, navy-teal shadows, very muted colour. The frame is off-white
  (`InstantFrame.paper`) with an embossed pebble texture (`PaperTexture`,
  a seamless tile drawn by `InstantPrint` on screen and baked into exports). Look
  iteration: `dart run tool/film_preview.dart out.jpg photos...` (env STOCKS,
  GRAIN, RES, CROP=1 for 1:1 crops).

## Adding a stock / camera

Everything a body needs lives on its `CameraSpec` in `camera_catalog.dart`:
look (`FilmProfile` in `film_profile.dart` for film, `LookSpec` for digital),
artwork, aspects, `developTime`, `printStyle` (print / instant), `roll`
(file prefix, frames, counter), `zoom` (digital only), `pickerTag`. No other
file should switch on a camera id. `test/catalog_contract_test.dart` fails if
an entry is incomplete. Gabe sends requests on `docs/NEW_CAMERA_FORM.md`.

## Product rules agreed with Gabe

Film Mode
- Shots develop in the **darkroom** (~5 min), then get pinned to the
  **corkboard**. Notifications are quiet (channel `darkroom_quiet`, no vibration).
- Photos are deliberately "physical": **nothing reaches the phone gallery until
  he taps Save on a print, or Save all.** Album: "Darkroom Film".
  Copies deleted from the phone's photos are noticed (`GalleryCheck`,
  channel `darkroom/gallery`: the album's file names; Android lists the
  app's own MediaStore entries with no permission, iOS needs full/limited
  library access, asked once with the reason, `PrefKeys.galleryAsked`).
  The board marks such prints unsaved (`markUnsaved`) and offers "Save
  again"; Win98 offers to copy missing C: files back (File > Copy to
  Photos). Matching is by the saved name (`galleryNameFor`, numbered
  duplicates allowed).
- **Super 8** develops like the prints. Preview is a spool of film on a reel;
  playback is a projector (`projector_screen.dart`): beam + screen, and a
  `ProjectorDeck` with the reel and a masking-tape label (tap: rename reel
  and file, `renameReel`), an amber dial + needle to seek, a drum counter
  for time left (no feet counter), and piano keys (start, prev, rew,
  play/pause, ffwd, next; each clicks: `Sfx.keyDown` / `keyUp`). FF/REW run **while held** (stepped seeks that
  spin up: smear, rolling frame line, sound off; resume playing on release
  if it was playing) and stop at the ends; START is one press. Seeks are
  coalesced (`_seek`). A reel that has ended re-threads a fresh player on
  PLAY (`_ended`; Android's player sticks), plus a one-shot stall watchdog.
  No swiping or tapping on the screen; only the keys. No REC badge in the Super 8 viewfinder. Always landscape
  (`CameraSpec.landscapeOnly`: held upright it records a landscape slice,
  `CropMath` `acrossShortSide`). Reels are full-gate scans (`CineStrip`,
  `core/processing/cine_strip.dart`): black film edge with the sprocket hole
  (glowing rim) on the viewer's left, slivers of the neighbouring frames
  across frame lines. The viewfinder shader draws the same strip (uniforms
  `uCanvas`, `uTurns`: it rotates with the phone so the hole stays on the
  viewer's left; `_StripTurn` swings it round when the phone turns, in the shader via
  `uSpin` so the hole turns with the strip); FFmpeg composites it from `gate.png`. Faded look tuned to
  Gabe's scans, strong flicker, dust (dark + light), hairs, long scratches
  and the odd warm flare (`_renderDustFrames`).
- Corkboard pins must sit **on** the photo, not in the cork above it.
  Pins are renders of a traditional push pin, one per colour
  (`assets/corkboard/pin_N.webp`, `tool/render/blender/pin.py`, `PinImage`).
- The corkboard slides in from the left in a wooden frame
  (`CorkboardScreen.slideIn`, `_WoodFrame`): slow, no overshoot, woody
  swoosh, soft thud as it lands (`Sfx.corkThud`). No bounce or stretch when
  scrolling past the ends; content scrolls to the frame, under the system
  bars. Film mode: a clear swipe right on the camera opens it (triggered,
  not dragged), a swipe left on the board closes it. Digital mode: a swipe
  left opens the Win98 explorer, which slides in from the right on a beige
  monitor (`ExplorerScreen.slideIn`, `ExplorerMonitor`) and slides back
  out however it's closed. The body never moves the way with no camera.
- The cork wall scrolls with the prints (shader tiles keyed to the scroll
  offset): granulated cork after Gabe's sample, with wear: pin holes,
  coffee rings, water marks, faded patches. Easter eggs: tap a
  pin -> "Would you like to discard this image?" -> pin pops, print falls
  (same as Throw away); tap a print's folded corner to see the back (lab
  stamp; instant prints show their black backing). Shake the phone on the
  board (`core/device/shake.dart`, 3 jolts) to clear it: asks, then every
  unsaved print unpins and falls, the board judders, the rest re-pin; a
  paper note in the corner says "shake to clear". The prints on screen
  drop once, together; the rest just go; all are deleted in one batch.
  The board never jumps: the drawn prints (`_shown`) change only through
  `_reflow`, which fades the grid out, swaps in the new order and fades it
  back (the whole board, cork too, after a shake or when near the end; it
  jumps to the top if the old spot is now past the end). While the phone
  is shaken the orientation holds (`PhysicalOrientationNotifier` ignores
  readings until |g| has been calm for 0.7 s).
- Super 8 reels on the board: a photoreal spool (`assets/corkboard/reel.webp`,
  rendered by `tool/render/blender/reel.py`) resting on two pins under its
  rim, with an instant photo of the first frame (file name in Caveat)
  taped on its front (`PinnedReel`, `_ReelCard`).
- Darkroom strip: prints go DEV -> STOP -> FIX -> WASH trays under the
  safelight (image comes up in DEV); reels turn in a developing tank; instant
  prints develop in the open. Tap one for a close-up of it developing
  (`showDarkroomCloseUp`). The print viewer is see-through: the board stays
  behind it, dimmed.
- Video audio: Super 8 = sound-stripe chain, camcorder = tape chain
  (`VideoProfile.super8Audio` / `camcorderAudio`).
- **Polaroid 600** (`printStyle: instant`): square only, 8-shot packs,
  develops in 20 s (watch it fade in on the corkboard's darkroom strip).
  Notes are typed in the print viewer (Write / tap the border), drawn in the
  bundled Caveat font, and baked into saved/shared files with the border
  (`core/processing/instant_frame.dart`). Note is stored in `note` (DB v3).

Digital Mode (1999 Floppy Cam, 2003 CCD Compact, Y2K Flip Phone, 90s Camcorder)
- Shots go to a virtual **SD card** in a Windows 98-style explorer.
- Files on the SD card are **locked** until moved to C: (prompt with
  Move / Move All). Moving removes them from the SD card and copies them to
  the gallery (album "Darkroom"); they stay viewable under C:.
- Zoom: W|T rocker on every digital body (none in film), 100x40; slide
  across to switch W/T (`_ClaimingPan` wins the touch on contact, so it
  never tosses the body). Held = fixed-rate
  motor zoom up to the body's `ZoomSpec.max` (floppy/CCD 3x, flip phone 4x,
  camcorder 10x, capped by the phone). No pinch. A quiet motor whir (`Sfx.zoomMotor`,
  looped) runs while the zoom moves. Camcorder shows a sliding
  W-T bar on its OSD, stills cameras a "2.4X" readout.
- Camcorder (`storage: DigitalStorage.floppy`) clips appear on **3½ Floppy
  (A:)**, not the SD card; copying them to C: is a multi-disk copy ("insert
  disk 2 of N", N = size / 1.44MB; after 3 swaps it offers to do the rest).
  With the OSD on, the tape OSD is burned into the video: blinking REC, SP +
  battery, the clock, and the zoom bar exactly as it moved
  (`CamcorderOsd` in `video_plan.dart`; the take's zoom track rides on the
  VideoJob).
- Win98 colours come from the current `Win98Scheme` (`W98.scheme`; `W98.*`
  are getters, so they can't go in `const` expressions). View > Options >
  Themes picks one (`win98ThemeProvider`, `PrefKeys.win98Theme`; the
  explorer applies the saved one in initState); `W98.apply` restyles the
  whole tree at once. Use `W98.window` / `W98.windowInk` for list and field
  backgrounds/text, `W98.navy` / `W98.selectInk` for selection, never
  `Colors.white` / `Colors.black`. `win98_themes_test` renders every scheme.
  The window sits on a strip of desktop (6 dp portrait, 4-5 landscape).
- Win98 screens and dialogs render through `Win98Scale` (1.3x, uniform), in
  the pixel font family `W98` (DotGothic16; it lacks □ ▲ ▶ ✓, so use
  `Win98Glyph` for those). The
  viewer has no swipe: ◀ ▶, a zoom trackbar + Reset Zoom (pinch still
  works); clips play in `Win98MediaPlayer` (|◀ ◀◀ ▶/❚❚ ■ ▶▶ ▶|, hold ◀◀/▶▶ to
  scan with VHS noise bars). The status bar shows the camera from EXIF
  (photos get Make/Model on export).
- Win98 sounds (`Sfx.w98*`, made by `tool/sfx/make_sfx.py`, all original,
  never Microsoft's): click on Win98Button / menu / Start items, error bong
  / warning ding from `showWin98MessageBox`, exit chime when the explorer
  closes, login chime when it opens. All sounds are kept quiet: levels are
  baked into the .wav files (`LEVELS` in make_sfx.py). Settings: Sound
  effects slider (`Sfx.level`, player volume = level², half by default)
  and Haptics (`Haptics`, use it instead of HapticFeedback). Start > Shut Down (no prompt) runs `showShutDownSequence` (sky +
  pixel rabbit + tune, then the CRT collapse). Start > Run knows RABBIT,
  DEVELOP, PING, README (`win98_programs.dart`), the games SOL / BRICKS /
  PINBALL (Space Rabbit: missions, ranks) / MINES (Minefield, `win98/games/`, rules
  and physics tested in `win98_games_test`), each with its own sounds,
  plus DEFRAG, WINVER, drive letters; Tip of the Day hints at them.
  Tools menu: Defragment Local Disk (C:), Format SD Card, Format 3½ Floppy (A:).
- Win98 touch targets: menu titles open on touch-down and touching another
  title while a menu is open switches to it (`showWin98Menu` siblings);
  caption buttons and toolbar buttons have padded hit areas.
- Toolbar button says **Transfer** (not Eject). Drive is named **SD Card**.
  Viewer has ◀ ▶ arrows. File/Edit/View/Help menus have settings, app info
  and easter eggs.

UI
- Film <-> Digital: two physical cameras on a desk (`body_swap.dart`,
  driven by `_swap` in camera_screen.dart). Drag the body sideways: it
  follows the thumb and tips away in perspective; a flick or a long drag
  tosses it and the other body comes in on the same motion (spring settle),
  else it springs back (and can be grabbed again mid-spring). While it
  moves, its viewfinder is a still (`CameraViewport.freeze`): shader
  filters under the 3D transform only move their input. Each body continues past the screen: rounded end,
  side wall with strap lug, neck strap (film) / wrist cord (digital): a
  verlet rope (`_HangingStrap`): heavy drag and a pull back to its resting
  hang at rest (a gentle sway from the smoothed tilt), light drag and extra
  lag while the body is flung (`_excite`), so a toss whips it. Until
  the toss commits the arriving body is a picture of it from last time
  (`_lastLook`, or `BodyStandIn`); on commit the leaving body becomes a
  picture and the live UI switches mode. Flutter flattens nested 3D
  transforms, so the side wall gets its own full matrix. The other camera
  also peeks in at the edge (digital on the right in film mode, film on the
  left); tap it to toss. Sound `assets/sfx/camera_swap.wav` (cloth swish,
  played via video_player at volume 0.15) and haptics.
- Shutter (`widgets/shutters.dart`, `_SpriteShutter.turntable` switches the
  3D frames on once they're in assets/shutters): digital = compact shutter key
  (camcorder: red dot), film = chrome release in an advance-lever hub (lever
  swings each frame), Super 8 = red RUN button that latches while filming.
  Drawn from path-traced turntable frames (`assets/shutters/`, made by
  `tool/render/items/shutter.js`: each whole button from -48..48 degrees
  in 12 degree steps, plus pressed; film also has base / lever / cap layers
  for the lever stroke). The frame follows the body's yaw while it tips
  (`BodyYaw` in body_swap.dart), cross-faded, stretched by 1/cos(yaw).
  Quiet sounds `Sfx.shutter*`. Fire via `pressShutter(ref)` so the button
  animates for volume keys too.
- The other camera's FILM/DIGITAL tag floats over the desk (outside the
  body's RepaintBoundary), tucks away during a swap and springs back.
- Gallery button: film = the latest print as a little photo on another
  print (`_PrintThumb`), digital = a review LCD (`_LcdThumb`).
- Under the viewfinder: film bodies show the box end in a memo holder
  (`CameraSpec.boxColor/boxInk`), digital bodies a segment-LCD panel (one
  fixed size for every body) with the phone's real battery
  (`core/device/battery.dart`, channel `darkroom/battery`) and card/tape
  remaining. The camcorder OSD burns in the same battery gauge.
- Volume buttons (Android; taken in MainActivity via `darkroom/volume` /
  `VolumeKeys` while the camera screen holds the edges; Flutter's own key
  events for them never arrived) are the shutter
  while the camera itself is on screen; setting "Volume buttons zoom" makes
  them the zoom on digital bodies. Elsewhere they change the volume.
- Crash reports stay on the phone (`core/diagnostics/crash_log.dart`):
  Dart errors + Android ApplicationExitInfo; Win98 Help > Debug... >
  Crash Reports. The Debug window (`win98/debug_menu.dart`, list `_tools`;
  add new tools there) also has Camera Log, the tour, develop-now, frame
  graphs (`perfOverlayProvider`), slow motion, system info, a test crash,
  and the Performance Recorder (`core/diagnostics/perf_recorder.dart`:
  `PerfRecorder.mark('label')` tags the next frames; the report splits UI
  vs GPU time per label). Mark new heavy moments with it.
- Slower phones: the camera reopens only after a panel's exit animation
  (`_settled`), the live viewfinder isn't built under a held still, and
  the cork wall's shader tiles are cached (`CorkTiles`, warmed at start).
  Impeller redraws everything every frame (no raster cache): avoid live
  blurs on big areas or under 3D transforms; use `SoftShadow` (baked) /
  `softStroke` (core/theme/soft_shadow.dart) or gradients. Setting
  **Performance mode** (`GlobalSettings.performance`, `FilmUniforms.lite`):
  viewfinder halation off, the body swaps as one picture (`_dragFace`).
- Setting **Fancy graphics** (was "3D cameras"; `GlobalSettings.controls3d`, on by default; the
  tour no longer asks): on = the photoreal bodies (below), controls turn
  with the body, the viewfinder stays live mid-swap (`_startMoving`: the
  live picture runs under a still of itself retaken flat each frame, as
  the look shader can't run under the 3D turn). Off = **performance mode**
  (`GlobalSettings.performance` is just `!controls3d` since 1.5.1): the
  classic drawn bodies, one frozen viewfinder still, the body swapped as
  one picture, no halation.
- **Live 3D bodies (1.6.2, Flutter Scene)**: each camera is a real 3D model
  drawn live (`flutter_scene` on Flutter GPU; enabled in the Android
  manifest meta-data `EnableFlutterGPU` and iOS Info.plist
  `FLTEnableFlutterGPU`). Made in Blender by
  `tool/render/blender/export_glb.py` from the same build as the renders
  (`whole_body.py` LAYOUT, `parts.py`, `kit.py`): the procedural Cycles
  materials baked into two atlases (static body / moving pieces: base
  colour x AO, metal-rough, normal), every moving piece its own node
  (`parts.py` `moving()`: `mv.<part>.<press|turn|slide|rock|lever>`), each
  placed part `part.<name>` (Super 8 RUN / camcorder REC = `part.shutteralt`),
  the static body cut into `body.top` / `body.mid` / `body.bot` (the middle
  piece, inside the viewfinder, squeezes or stretches to the phone's
  height). `--env` writes the studio (`studio.hdr`, the renders' soft boxes,
  plus a separate diffuse SH like the renders' dark world).
  `bundle_live.py OUT assets/body3d` copies them in with `manifest.json`.
  `hook/build.dart` turns the .glb files into Flutter Scene packages at
  build time (`flutter_scene_generated/`, not committed; textures GPU-
  compressed; ~25 MB in the app for both bodies, adds ~4 min to a
  build). App: `whole_body.dart` (`WholeArt.load`: manifest, studio,
  models (`scenes: false` = layout only, for tests); `LiveBody`: one scene
  per body, `fit` (middle piece), `pose` (a screen-space Matrix4, the same
  one the face's widgets are drawn under with `DesignFit.camera`),
  `setPart`; `LiveBodyView`: an unticked SceneView, repaints only on change).
  The build-time importer turns glTF's z round: the face looks down -z,
  the camera sits at -dist. `whole_face.dart` lays the usual control widgets
  on the face (design dp); their parts are `LivePart`s (photo_body.dart
  `BodySprite`), which draw nothing and report their transform (slides,
  turns, presses read off the control's own animation) to the model.
  `SwapBody` (body_swap.dart) always draws the model under the face (same
  tree at rest and mid-swap, so nothing remounts); mid-swap the face is
  drawn under `camera x pose`, the strap from the projected lug. Snapshots
  for the other camera (`_lastLook`) are of the face's widgets only
  (`WholeFace.overlayKey`). Loaded (and shaders warmed) behind the launch
  screen (main.dart `_warmBodies`). No Flutter GPU (old phones, tests): the
  classic drawn bodies. Desktop check without a phone:
  `tool/live3d/preview.dart` (see its header; Linux + software Vulkan/GL
  under Xvfb). Tests: `whole_face_test` (layout on phone sizes),
  `photo_body_test` (bundled, 3D off = classic, taps).
  Each moving node moves only its own way (`setPart`: slide / turn / lever
  / press (in + 0.93 scale) / rock). Labels on a key's top ride up with
  `OnTop(BodyArt.topOf(part))` (a z-lift under the pose) so they stay on
  the cap at an angle. Never put an opacity (or any compositing) layer
  inside an `OnTop` (Flutter flattens the lift) or round one below 1.0
  (its bounds are flat and crop the lifted label): fade a label's ink
  colour instead (`_AspectDial` / `inked`). The face overlay isn't
  clipped (a flat clip cut off lifted labels near the top edge). The video/photo shutter swap sinks one and raises
  the other (`showShutter`, 420 ms). Digital finishes (silver, grip,
  gunmetal, champagne, two-tone) are baked as `finish.<key>.*` nodes
  (`export_glb.py` FINISHES), picked by `bodyFinishProvider`
  (`PrefKeys.bodyFinish`); Debug > Camera Finish is a list to pick from
  (later: unlocked by mini games). The film format dial's label turns
  with its top: the old one away, the new one in (`_AspectDial`). Key
  labels stay well inside the cap (turned, its near edge shows). The
  memo card's text keeps its size in the holder (shrinks evenly only if
  it can't fit).
  Ruined shots show a darkroom excuse + Copy error report (`errorReport`).
- `AppInfo.version` must match pubspec (test/app_info_test.dart).
- Camera session: "inactive" does NOT close the camera (Android sends it on
  any focus blip; closing made the Pixel's viewfinder flap). Only hidden /
  paused do. `CameraLog` keeps recent session events: Win98 Help > Debug.
  While the camera is closed the viewport keeps the last stream's aspect
  (`_lastPreviewAspect`), so the frozen still never squashes.
- Swipe up on the camera opens the film/camera carousel; swipe down closes it.
- Phone gestures win at the edges (`core/device/system_gestures.dart`): our
  drags (the camera toss too) ignore touches that start in the home strip (bottom ~56dp), the
  notification strip (top) and the back strips (sides), except level with
  the peeking camera, where `MainActivity.kt` (kept in the repo; channel
  `darkroom/gestures`) asks Android 10+ to keep its back gesture off both
  edges. The camera screen releases those strips while another screen is
  on top.
  Carousel works in landscape. In the carousel, sideways swipes work anywhere
  on screen; closing needs a clearly downward swipe (deadzone).
- On the camera screen, swiping sideways on the stock name or the film box
  steps to the next/previous stock without opening the carousel.
- Zoomed-in photos pan; swiping to the next photo only works at normal zoom.
  The film print viewer uses `PhotoPager` (`viewer/presentation/zoomable.dart`,
  raw pointer handling, PageView physics off): a swipe needs 24 dp clearly
  sideways, a second finger always turns it into a pinch, double tap zooms
  2.5x / back out, double tap + slide zooms gradually (down = in), a swipe
  up or down puts the print away, a single tap (after 300 ms) off the print
  closes it. Tested in `photo_pager_test`.

## First run

- `OnboardingScreen` (features, gestures, name, permissions with reasons,
  one Allow all) shows once (`PrefKeys.onboarded`); Win98 Help > Welcome
  Tour replays it. Camera + mic are asked by opening a CameraController
  once (the camera plugin has no request call). The name
  (`userNameProvider`) goes on the print backs' lab stamp and in Tip of the
  Day; change it in Win98 Start > User Profile.

## Art

- App icon: an RGB-split rabbit with X'd-out eyes on near-black. Generated by
  `tool/icon/make_icons.py` (Pillow + numpy): Android adaptive + monochrome
  (themed icons), legacy round, notification glyph, iOS 1024
  default/dark/tinted, and the GitHub social preview `docs/social_preview.png`
  (Gabe sets it by hand: repo Settings > General > Social preview).
- The rabbit in the app, used sparingly: `DarkroomMark`
  (`core/theme/darkroom_mark.dart`) pressed into the camera
  bodies' lens-flip cap and on the lab stamp on the back of prints; the
  shutdown screen's `PixelRabbit`; the 16x16
  `PixelIcon.rabbit` on the Win98 Start button, Start menu banner and About box.
- Film boxes / camera pictures (`assets/artwork/*.webp`, 1024 px) are 3D
  renders made with `tool/render/` (three.js r185 + three-gpu-pathtracer in
  headless Chromium; see its README). They say **DARKROOM**, with the rabbit
  (`lib/logo.js`) on the film boxes, Super 8 cartridge and instant camera.

## Backlog

1. Tidier camcorder viewfinder in its artwork.
2. Digital camera looks: tune against reference photos when Gabe sends them
   (1999 Floppy Cam done in 1.6.8; `CAMERA=id dart run tool/look_preview.dart
   outdir photos...` renders photos through a digital body's still pipeline).
3. First iOS run: the CI .ipa builds (build 19); still to try it on Gabe's iPhone.
4. (Done 2026-10-07, build 35: CI uploads to Play internal testing.) If
   Gabe drops the Cloud project, delete the secret and he uploads by hand.
