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
- Every user-visible change: bump `version` in `pubspec.yaml` (raise the
  `+build` number too) and add a line to `AppInfo.revisions` in
  `lib/core/app_info.dart` (shown in the Win98 Help > About).
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
- iOS: deployment target 15.0 (set in `ios/Podfile` and patched into the
  generated Xcode project by CI). `ios/` holds only Info.plist,
  AppDelegate.swift, Podfile and the AppIcon set; CI generates the rest.
  Background developing (WorkManager) is Android-only.
- `android/` and `ios/` only contain the files we customised. CI runs
  `flutter create --org com.darkroom --project-name darkroom --platforms android .`
  to fill in the rest (it never overwrites existing files). Don't delete
  `AndroidManifest.xml` or `android/app/build.gradle.kts`.
- `applicationId` / `namespace` = `com.darkroom.darkroom`; must match the
  MainActivity package that `flutter create` generates.
- Release builds are signed with a **fixed test key**
  (`android/app/darkroom-test.jks`, passwords in `build.gradle.kts`) so each
  build installs over the last without wiping photos. Don't change it.
  Replace with a private key before any store release.
- Manifest already has `tools:replace="android:maxSdkVersion"` on
  `WRITE_EXTERNAL_STORAGE` (merger conflict with camera_android_camerax).
- Checks: `flutter analyze` and `flutter test`. If the session has no Flutter
  SDK, just push and read the GitHub Actions result.
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
- The activity is **locked to portrait**. Landscape is detected with the
  accelerometer (`lib/core/device/physical_orientation.dart`); icons rotate in
  place (`Upright` / `UprightBox`) and photos are saved upright.

## Film engine (`lib/core/processing/film/`)

Each stock is a film model baked into a 33³ 3D LUT (log shaper, per-channel
curves, hue tweaks, split toning). The same LUT drives the live GPU preview
(`shaders/film.frag`), the CPU renderer for stills, and FFmpeg `lut3d` (.cube)
for video. Plus a tileable grain texture, halation and exposure drift.

- Stock ids: `ektar100`, `portra400`, `hp5plus400`, `polaroid600`, `super8`.
- Grain strength: weak 0.55 / normal 1 / strong 1.65. Set **per film stock,
  only in the settings menu**. When not "normal", the carousel shows a small
  tag. Digital cameras have no grain setting.

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
- **Super 8** develops like the prints. Preview is a spool of film on a reel;
  playback is a film-styled projector screen.
- Corkboard pins must sit **on** the photo, not in the cork above it.
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
- Zoom: W|T rocker on every digital body (none in film). Held = fixed-rate
  motor zoom up to the body's `ZoomSpec.max` (floppy/CCD 3x, flip phone 4x,
  camcorder 10x, capped by the phone). No pinch. Camcorder shows a sliding
  W-T bar on its OSD, stills cameras a "2.4X" readout.
- Camcorder (`storage: DigitalStorage.floppy`) clips appear on **3½ Floppy
  (A:)**, not the SD card; copying them to C: is a multi-disk copy ("insert
  disk 2 of N", N = size / 1.44MB; after 3 swaps it offers to do the rest).
  With the OSD on, the tape OSD is burned into the video: blinking REC, SP +
  battery, the clock, and the zoom bar exactly as it moved
  (`CamcorderOsd` in `video_plan.dart`; the take's zoom track rides on the
  VideoJob).
- Win98 screens and dialogs render through `Win98Scale` (1.3x, uniform). The
  viewer has no swipe: ◀ ▶, a zoom trackbar + Reset Zoom (pinch still
  works); clips play in `Win98MediaPlayer` (|◀ ◀◀ ▶/❚❚ ■ ▶▶ ▶|, hold ◀◀/▶▶ to
  scan with VHS noise bars). The status bar shows the camera from EXIF
  (photos get Make/Model on export).
- Toolbar button says **Transfer** (not Eject). Drive is named **SD Card**.
  Viewer has ◀ ▶ arrows. File/Edit/View/Help menus have settings, app info
  and easter eggs.

UI
- Swipe up on the camera opens the film/camera carousel (not from the bottom
  ~56dp: that's the system home gesture); swipe down closes it.
  Carousel works in landscape. In the carousel, sideways swipes work anywhere
  on screen; closing needs a clearly downward swipe (deadzone).
- On the camera screen, swiping sideways on the stock name or the film box
  steps to the next/previous stock without opening the carousel.
- Zoomed-in photos pan; swiping to the next photo only works at normal zoom.

## Art

- App icon: an RGB-split rabbit with X'd-out eyes on near-black. Generated by
  `tool/icon/make_icons.py` (Pillow + numpy): Android adaptive + monochrome
  (themed icons), legacy round, notification glyph, iOS 1024
  default/dark/tinted. Gabe wants the logo worked into the app UI later.
- Film boxes / camera pictures (`assets/artwork/*.webp`) are 3D renders made
  with `tool/render/` (three.js r185 + three-gpu-pathtracer in headless
  Chromium). They're 512 px previews and still say **RETROCAM**.

## Backlog

1. Re-render the artwork at full resolution with Darkroom branding
   (also: darker film leader, tidier camcorder viewfinder).
2. Bring the rabbit logo into the app's own design.
3. First iOS run: get the CI .ipa building and working on Gabe's iPhone.
4. Proper signing key before publishing anywhere.
