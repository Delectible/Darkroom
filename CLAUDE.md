# Darkroom: notes for Claude

A retro film + digital camera app (Flutter; was "RetroCam" until 1.2).
This page is the rules. The details live in **`docs/NOTES.md`** (read the
section for the area you're touching before changing it) and
`docs/DEVELOPMENT.md` (setup, structure, shader contract).

## The owner and how we work

- Tests on a **Pixel 9 Pro** and an **iPhone**, usually from his phone.
  Keep replies short and plain. He's often low on usage: stay focused,
  don't gold-plate, batch related tweaks, don't re-run the full test suite
  more than needed.
- Big revisions: ask clarifying questions first. Visual changes: if the
  look is open, show 2–3 options as screenshots before building.
- Draft on the session's work branch (doesn't build); commit there freely.
  **Only when he says "push"**: fast-forward the work branch onto `main`
  (`git fetch origin main && git merge-base --is-ancestor origin/main HEAD
  && git push origin HEAD:main`). Never push half-done work to `main`.
- After a push to `main`: wait for the run (send_later ~20 min); once its
  `play` job has uploaded + ~2 min, PushNotification: version, build
  number, one line of what's new. On failure, notify that instead.
- Every user-visible change: bump `version` in `pubspec.yaml` (+build too)
  and `AppInfo.version` to match (a test checks); set `AppInfo.latest`
  (`lib/core/app_info.dart`, = Play's "What's new") to this build's change
  in plain words; for a main idea add a few-word bullet to the newest
  `AppInfo.revisions` entry. Changes before a push fold into the same
  unpushed version.
- **Commit messages:** plain, no session links, no Co-Authored-By.
- **`docs/CHANGELOG.md`**: every request by item number (`[~]` started,
  `[x] → version · …` landed); new feature ideas go there too.
- **"The checklist"** = artifact **Darkroom Release Sweep**,
  https://claude.ai/artifact/KrvhMZrV3RUNie7YHxYewQ (read, edit, republish
  to the same URL; finished items are removed, not ticked; he pastes his
  ticks back). New stocks/cameras arrive on `docs/NEW_CAMERA_FORM.md`.
- Remind him every ~3 main builds if the iPhone App Store is behind.

## Stores (details: NOTES.md "Build & release pipeline")

- `main` → CI builds Android + iOS, uploads to **Play internal testing**
  and **TestFlight** (external groups). Closed testing: `promote-closed.yml`
  by hand when he calls a build stable.
- **App Store**: `appstore-release.yml` only when he says "release to
  iPhone", and only after checking App Store Connect: never cancel a
  submission in review (`replace_pending` stays off).
- **Never run `play-listing.yml`** unless he asks: he edits the listing in
  the Play Console (the real copy; same wording on the App Store).

## Never

- Put anything in the (public) repo that unlocks Pro; write the Debug
  password (`DEBUG_PASSWORD` secret) anywhere; commit the upload key.
- Show real brand names (Kodak, Ilford, Polaroid, Windows, Minesweeper…)
  in the app or listings. Stocks are Vivid 100, Portrait 400, Classic 400,
  Instant 600, Super 8, etc.; ids (`ektar100`…) are code-only.
- Add a Podfile (every iOS plugin is a Swift Package), delete
  `AndroidManifest.xml` / `android/app/build.gradle.kts`, or change
  `applicationId` `com.dingo.darkroom`.
- Use GPL FFmpeg filters (`boxblur`, `eq`, `drawtext`…: the "min" build is
  LGPL), mismatch shader uniforms with the `.frag` files, or add a GLES
  y-flip to shaders (`look_and_shader_contract_test` checks all three).
- Switch on a camera id outside `camera_catalog.dart` (`catalog_contract_test`).
- Put an opacity/compositing layer inside an `OnTop` on the 3D face.
- Use `Colors.white/black` in Win98 UI (use `W98.*`), or `HapticFeedback`
  (use `Haptics`).

## Checks

- `flutter analyze lib test` and `flutter test` (CI won't publish unless
  both pass). In the cloud the SDK may be at `/tmp/flutter/bin`; run tests
  with `FLUTTER_ROOT` set. No SDK: push to the work branch and say so.
- `dart format -l 110 <the files you changed>` only, never whole folders.
- UI without a phone: `test/*_screens_test.dart` at Pixel 9 Pro size,
  `SHOTS=dir` saves PNGs. Tests pump (How it works never settles).
  3D bodies: `tool/live3d/preview.dart` (Linux, Xvfb; the digital model
  may not draw there). Real-phone numbers: ask him for Debug > Launch
  Timing / Performance Report / Crash Reports (Copy buttons).

## Where things are (read the NOTES.md section before touching it)

- **Launch**: `main.dart` (nothing heavy before `runApp`), `LaunchCurtain`
  waits for camera + look + 3D, `LaunchTimer` marks steps.
- **Film engine / grain / defects / instant**: `lib/core/processing/film/`.
- **Free vs Pro**: `Allowance`, `proProvider` (NOTES "Free and Pro").
- **Camera UI, 3D bodies, skins, swap**: NOTES "UI" + "Live 3D bodies".
- **Corkboard, darkroom, projector (Super 8)**: NOTES "Film Mode".
- **Darkroom 98 (Win98 explorer, CRT, games)**: NOTES "Digital Mode".
- **Landscape screens**: NOTES "Things that bite".
- **First run, How it works, permissions**: NOTES "First run".
- **Art and renders**: NOTES "Art"; backlog at the end of NOTES.
