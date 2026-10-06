# Darkroom — developer guide (Flutter)

Git repository: **Darkroom**. Formerly named RetroCam.

Two modes, one deliberate camera. **Film Mode** develops every shot (and every
Super 8 reel) in a 5‑minute darkroom and pins it to a corkboard; nothing reaches
your photo library until you press Save. **Digital Mode** writes to a virtual SD
card browsed in a 9x‑style Explorer; files on the card are locked until you move
them to "Local Disk (C:)", which also copies them to your photo library.

Verified against **Flutter 3.47 stable / Dart 3.13** (`dart analyze`: 0 issues;
pure‑Dart tests pass; every shader compiles for Impeller, Impeller‑GLES and
SkSL; every video look was rendered end‑to‑end through an **LGPL‑only FFmpeg
build**, i.e. the same filter set as the app's FFmpegKit "min"). Device runs:
Pixel 9 Pro (Impeller / Vulkan).

**How to use it.**

* The camera decides the medium. Film: Ektar 100, Portra 400, HP5 Plus (stills)
  and Super 8 (movies). Digital: 1999 Floppy Cam, 2003 CCD compact, Y2K flip
  phone (stills) and the 90s camcorder (video). Tap the shutter; movie cameras
  start/stop recording.
* Swipe up anywhere on the camera body (or tap the stock button) to open the
  picker; swipe down or tap the chevron to close it. Grain strength per stock
  (Weak / Normal / Strong) lives in Settings; the picker shows a tag when it is
  not Normal.
* Hold the phone sideways: icons and the viewfinder readouts turn upright,
  photos are saved the right way up, and the picker lays out in landscape.

---

## 1. Setup

```bash
# 1. Generate the missing platform boilerplate. Existing files (AndroidManifest,
#    build.gradle.kts, Info.plist, AppDelegate.swift) are kept as-is.
flutter create . --org com.dingo --platforms=android,ios

# 2. Packages
flutter pub get

# 3. iOS: set the Runner deployment target to 15.0
#    (Xcode > Runner > General > Minimum Deployments). Plugins come in as
#    Swift Packages; there is no Podfile and no `pod install`.

# 4. Run (release/profile shows the real shader performance)
flutter run --release
```

Android is preconfigured in `android/app/build.gradle.kts`: minSdk 24
(FFmpegKit), compileSdk ≥ 36 and core‑library desugaring
(flutter_local_notifications). If you pick a different `--org`, update
`namespace`/`applicationId` there to match the generated `MainActivity` package.

### Dependencies (pubspec.yaml)

| Package | Version | Why |
|---|---|---|
| flutter_riverpod | ^3.4.3 | state (Notifier / Provider / StreamProvider only — no codegen) |
| camera | ^0.12.1 | preview, stills, video |
| sqflite / shared_preferences | ^2.4.4 / ^2.5.5 | queue + settings / UI prefs |
| flutter_local_notifications + timezone | ^22.3.1 / ^0.11.0 | darkroom notifications |
| workmanager | ^0.10.10 | Android darkroom wake‑ups that survive kills and reboots |
| image | ^4.10.1 | full‑res grading, grain, JPEG in an isolate |
| ffmpeg_kit_flutter_new_min | ^3.6.4 | video looks (see note below) |
| gal | ^2.3.3 | writing to the public photo library |
| share_plus | ^13.3.1 | native share sheet |
| sensors_plus | ^7.1.1 | physical orientation (the UI is portrait‑locked) |
| video_player, path_provider, path, flutter_shaders | | playback, paths, Skia fallback |

> **FFmpeg note:** the original `ffmpeg_kit_flutter` was retired in 2025 and
> its binaries were pulled. `ffmpeg_kit_flutter_new_min` is the maintained
> fork with the same API. The *min* build is LGPL: no libfreetype, no x264 and
> **no GPL filters** (boxblur, eq, hqdn3d, …). Timestamps are burned in from
> pre‑rendered PNG frames, clips are encoded with the built‑in MPEG‑4 Part 2
> encoder, and `test/look_and_shader_contract_test.dart` fails if a graph ever
> uses a filter the min build does not have (the cause of the camcorder's
> "Error initializing complex filters" in 1.1).
>
> **Gradle warnings you can ignore:** "restricted method / enable-native-access"
> comes from the JDK running Gradle, and "plugins that apply Kotlin Gradle Plugin
> (KGP): ffmpeg_kit_flutter_new_min, workmanager_android" is a heads‑up to those
> plugin authors. Neither affects the build; they go away when the plugins update.

---

## 2. Project structure (feature‑first)

```
lib/
  main.dart                     bootstrap: DB, prefs, notifications, WorkManager, recovery
  app.dart                      MaterialApp + AppLifecycleListener -> provider
  core/
    providers.dart              infrastructure providers + live media streams
    background/background_worker.dart   WorkManager dispatcher (Android darkroom)
    db/app_database.dart        schema (film_prints, sd_card, camera_settings, app_settings)
    db/media_repository.dart    queue/gallery rows, change feed, darkroom bookkeeping
    notifications/notification_service.dart   single consolidated notification
    paths/app_paths.dart        storage roots; DB stores *relative* paths
    processing/
      film/                     film model: profiles, 3D LUT, grain tile, still renderer
      look_spec.dart            digital look recipe shared by GLSL, CPU and FFmpeg
      crop_math.dart            preview-mask <-> sensor-pixel mapping
      look_renderer.dart        CPU port of the shaders (in-place, O(width) scratch)
      photo_pipeline.dart       decode -> crop -> rotate -> film/digital look -> encode (isolate)
      isolate_jobs.dart         the ONLY place Isolate.run is called (see roadblock 1)
      video_filters.dart        FFmpeg filtergraphs for each look
      video_plan.dart           pure-Dart FFmpeg plan + OSD frames
      video_pipeline.dart       FFmpegKit runner + encoder fallback ladder
      capture_processor.dart    capture queue, temp purge, crash recovery
    shaders/live_look_preview.dart   ImageFilter.shader (Impeller) / AnimatedSampler (Skia)
    shaders/shader_library.dart      programs, LUT + grain textures, uniform writers
    device/                          accelerometer orientation, Upright / UprightBox widgets
    theme/ utils/pixel_font.dart     skins, textures, 5x7 dot-matrix font
  features/
    cameras/       domain (CameraSpec, catalog) + full-screen picker + rendered artwork
    camera/        session controller (lifecycle), capture controller, viewport, controls
    darkroom/      DarkroomEngine (pure timekeeping) + in-app clock/banner
    corkboard/     cork gallery, prints & reels, print viewer, Super 8 projector, darkroom strip
    sd_card/       SD/C: state + move, 9x explorer, menus & dialogs, pixel icons, viewer
    settings/      global + per-stock settings
    viewer/        shared photo/video view, share/save/delete
shaders/           film, ccd_color, jpeg_pixel, vhs_scanline, cork_board (.frag)
assets/artwork/    product shots for the picker (rendered by tool/render/)
test/              crop math, Dart<->GLSL uniform contract, isolate hand-off, icons
tool/              dev smoke tests (CPU stills, FFmpeg plans) + icon/make_icons.py
```

---

## 3. Film emulation

Each stock is a `FilmProfile` (film/film_profile.dart) evaluated by `FilmModel`
into a 33³ **3D LUT**. One model feeds all three renderers, so the viewfinder,
the print and the Super 8 clip match:

1. **Colour.** Display‑linear input → panchromatic mix (B&W) → layer crosstalk
   and stock white balance → an *inverse display transform* that re‑opens the
   phone's compressed highlights → a per‑channel characteristic curve
   `y = W·xᵍ/(xᵍ+mᵍ)` anchored at mid‑grey. Different contrast per channel gives
   the real crossovers (Portra: cool shadows, warm highlights). Then hue‑selective
   tweaks in OKLCh: Portra's greens go olive and skies cyan, skin warms; Ektar's
   reds deepen and blues get dense; scanner black lift and highlight cap last.
2. **Highlights roll off** on the film shoulder instead of clipping, and exposure
   or flash push into it (two stops of LUT headroom via a log shaper).
3. **Grain** is a tileable 512² texture: fine noise plus a coarser octave of the
   same noise (clumps), three partially correlated layers for colour stocks,
   mid‑tone weighted, sized *relative to the frame* (Ektar fine → HP5 coarse →
   Super 8 very coarse) and re‑rolled every frame. Weak / Normal / Strong per stock.
4. **Halation**: blurred highlight energy adds a red‑orange glow (strong on Super 8).
5. **Per‑frame drift**: each still gets a tiny random exposure / colour shift.

GPU: shaders/film.frag (two texture lookups for the LUT, one for grain, six for
halation). CPU: film_renderer.dart (tetrahedral LUT, ~5 s for 8 MP on a phone,
in an isolate). Video: the LUT is written as a `.cube` for FFmpeg's `lut3d`;
Super 8 adds gate weave, flicker, dust / hair / scratch frames, coarse grain, a
soft rounded gate and 18 fps.

`tool/film_preview.dart` renders a contact sheet of any photos through every
stock, which is how the profiles were tuned.

## 4. How the four roadblocks are solved

**1. High‑res processing without OOM.** The GPU only renders the *preview*.
Captures go to `PhotoPipeline.run` in a fresh isolate, one job at a time
(`CaptureProcessor` is a serial queue). The isolate is started only from the
top‑level helpers in `isolate_jobs.dart`: a closure created inside a stateful
class can drag that object (and through Riverpod, the whole app) into the
isolate message, which fails with "Illegal argument in isolate message". That was
why early builds marked every shot ruined. `test/isolate_jobs_test.dart` guards it. Inside the isolate the frame is decoded
once, **cropped first**, downscaled to the stock's cap, EXIF‑rotated on the small
image (skipping `bakeOrientation`'s full‑size copy) and graded **in place** on the
RGB buffer. Grain uses two tiling noise tiles instead of a full‑frame noise
buffer. Peak is about 2× one decoded frame, briefly. On a desktop VM, an 8–12 MP
still renders in ~2–3 s, all of it off the UI thread.

**2. "Camera is already in use".** `CameraSessionController` is the only owner
of a `CameraController`. Callers set *desired* state (screen visible, app
visible, lens, preset). A single‑flight reconcile loop moves the hardware toward
it one awaited step at a time and collapses bursts of lifecycle events. Release
always (a) unmounts the preview, (b) finalises any recording so the clip is kept,
(c) awaits `dispose()` before anything reopens. An init that completes after the
target changed is disposed immediately. Transient open failures back off
exponentially; permission denials wait for the user to return from Settings.

**3. Preview crop == exported pixels.** The preview is never cover‑cropped. It is
drawn at the stream's own aspect and masked with
`CropMath.previewMask`. Exports use `CropMath.stillCrop`, which first finds the
preview's field of view inside the still (preview and still streams are centred
crops of the sensor with different aspects), then places the same mask in it.
Capture orientation is locked to portrait so the preview stays stable in the
portrait‑only UI. The physical orientation at the shutter (and front/back lens) is
re‑applied in processing, so sideways shots come out landscape. Tests cover the
parity.

**4. Temp file purge.** The plugin's capture file is *moved* into a private
`capture_cache`. A `processing` row stores the job. When the output is written,
one UPDATE flips the row to `ready` and nulls `raw_path`, then the raw file (and
any "original copy" once saved to the gallery) is deleted. If the app dies at any
point, startup `recover()` resumes jobs and `sweepOrphans()` deletes any cache file
no row references, plus stray `.part` files. Jobs get 3 attempts, then the raw is
purged and the print shows as ruined. Ruined prints and corrupt SD files stay
visible; tap one to see the actual error, then keep or discard it.

### Running well on old, low‑memory phones

* **Preview resolution is chosen per camera.** Film previews at 1080p by default
  (Settings → *High‑resolution film* switches to 4K‑class capture for phones that
  can take it); the flip phone and camcorder run the sensor at 480p.
* **Shaders run at the look's frame rate, not the screen's.** The live look is
  re‑rendered by a Timer at 24 fps (film), 15 fps (flip phone) or 30 fps (CCD,
  camcorder) instead of every vsync.
* **Backgrounds are pictures, not paintings.** Impeller has no raster cache, so
  anything drawn with thousands of vector strokes is redrawn every frame. The
  leatherette, metal, cork and 9x dither are each rendered once into a small
  bitmap and tiled.
* **Nothing animates when idle.** Progress spinners are only built while work is
  queued.
* **Video is cheap.** Camcorder clips are captured at 480p and encoded with
  MPEG‑4 Part 2 on a native thread with a hard timeout, so a stuck encode fails
  visibly instead of "processing" forever.

---

## 5. Darkroom timing & notifications

* Each print stores an absolute `ready_at` epoch. Nothing counts down in memory,
  so kills and reboots can't lose a timer.
* **In process:** one Timer for the next `ready_at`. In the foreground it shows
  an in‑app banner; in the background it posts the notification.
* **Android, app killed or rebooted:** a WorkManager one‑off task is armed for
  the next `ready_at` and chains itself. It also finishes stills interrupted
  mid‑processing. Doze can delay it by a few minutes.
* **iOS:** cumulative notifications are pre‑scheduled with `zonedSchedule` in
  ~60 s batches, grouped in one thread.
* **Consolidation:** one notification id, re‑posted with the cumulative unseen
  count ("3 photos have finished developing in the Darkroom.") with
  `onlyAlertOnce`, so it updates instead of stacking. Opening the corkboard marks
  everything seen and clears it.
* **Quiet:** low importance, no sound, no vibration (iOS: passive). Android
  channels can't be changed after creation, so 1.2 uses a new channel id and
  deletes the old one.
* Turning the darkroom off develops everything still in the tanks immediately.

## 6. Shader contract

The film shader has its own layout (`FilmUniformLayout`, 29 floats + camera,
LUT and grain samplers). The three digital shaders share a 29‑float uniform header (`uSize`, time, a 3×3
matrix as three `vec3` rows, offset, tone curve, vignette, grain, flash,
visible crop), followed by look‑specific floats. `LookSpec.commonUniforms` /
`extraUniforms` write them in the same order. `test/look_and_shader_contract_test.dart`
parses the `.frag` files and fails if Dart and GLSL drift apart. On Impeller the
filter path is `ImageFilter.shader` (zero readbacks). The engine owns `uSize`
and the input sampler, and the GLES Y‑flip is handled with
`IMPELLER_TARGET_OPENGLES`.

## 7. Dev tools

```bash
flutter test                              # unit tests
dart run tool/pipeline_smoke.dart          # renders every stock from a synthetic 12MP frame
dart run tool/film_preview.dart sheet.jpg a.jpg b.png  # film looks contact sheet
dart run tool/video_plan_smoke.dart clip.mp4 640 480   # Super 8 + camcorder; needs desktop ffmpeg
python3 tool/icon/make_icons.py            # every Android/iOS icon + GitHub social preview (Pillow + numpy)
```

**App icon.** A rabbit with X'd‑out eyes, split into red/green/blue copies like
a mis‑converged CRT, on near‑black. The generator writes the Android adaptive
icon (background colour, foreground, and a monochrome layer for Android 13+
themed icons), a round legacy icon for Android 7.x, the white notification glyph
`ic_stat_darkroom`, and a single‑size iOS `AppIcon.appiconset` with Default, Dark
and Tinted appearances (iOS 18+, Xcode 16+), plus `docs/social_preview.png`
for the repository. Tweak the constants at the top of the script and re‑run.
In the app the same drawing is `DarkroomMark` (`core/theme/darkroom_mark.dart`:
camera bodies, the back of prints) and `PixelIcon.rabbit` (Win98 Start button,
Start menu, About box); `tool/render/lib/logo.js` puts it on the box art.

## 8. Before you ship

* Stock names reference the emulsions the looks are modelled on. Those names are
  trademarks of their owners; the box and camera art is original and logo‑free.
  Consider generic names for a store release.
* The FFmpeg *min* build is LGPL; keep it dynamically linked (the default).

## 9. Builds and releases

`.github/workflows/build-apk.yml` runs on every push (Markdown and `docs/`
changes excepted): `flutter analyze` + `flutter test`, the Android APK and app
bundle, and an unsigned iOS `.ipa` on a macOS runner. When the checks and the
Android build pass, everything is published as a GitHub release `build-N`
(`N` = run number = Android versionCode; non‑`main` branches are pre‑releases).

* **Signing:** release builds use the private upload key from the repository
  secrets `ANDROID_KEYSTORE_BASE64` / `ANDROID_KEYSTORE_PASSWORD` (alias
  `upload`). Without them (forks, local builds) they fall back to the public
  test key `android/app/darkroom-test.jks`, which can't update a private‑key
  install. Never commit the private key.
* **Google Play:** app id `com.dingo.darkroom`, internal testing track, Play
  App Signing (Google signs what users install; we sign uploads with the
  upload key). The `play` job uploads each `main` build's `.aab` with
  `r0adkll/upload-google-play`, using the secret `PLAY_SERVICE_ACCOUNT_JSON`
  (a Google Cloud service account with the Play Android Developer API
  enabled, invited in Play Console > Users and permissions with release
  rights for the app). Release notes are the commit subject. While the app
  is still a draft in the console, set the repository variable
  `PLAY_RELEASE_STATUS=draft`. Privacy policy: `docs/PRIVACY.md`.
* **iOS:** the `.ipa` is unsigned; sideload it with Sideloadly and an Apple ID.
  On a private repository the macOS job only runs for commits with `[ios]` in
  the message or a manual run.
* **Packages:** `pubspec.lock` is committed, so CI builds what was tested.
  Update deliberately with `flutter pub upgrade` and commit the lock file.
