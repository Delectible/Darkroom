# Darkroom: notes for Claude

Retro film + digital camera app (Flutter). This page is the rules; read the
matching section of **`docs/NOTES.md`** before changing an area
(`docs/DEVELOPMENT.md`: setup, structure, shader contract).

## How we work

- The owner tests on a Pixel 9 Pro and an iPhone, from his phone, often low
  on usage: short plain replies, stay focused, batch tweaks, run only the
  tests that matter (full suite once before committing a batch).
- Big changes: ask first. Open-ended visual changes: show 2–3 screenshot
  options before building.
- Work on the session branch; commit freely. **Only on "push"**:
  fast-forward onto `main` (`git fetch origin main && git merge-base
  --is-ancestor origin/main HEAD && git push origin HEAD:main`). Then
  send_later ~20 min, check the run, and once the `play` job has uploaded
  (+2 min) PushNotification: version, build, one line of what's new (or
  the failure).
- User-visible change: bump `pubspec.yaml` version+build and
  `AppInfo.version`; set `AppInfo.latest` (Play's "What's new", plain
  words). Unpushed changes share one version. Only ever bump the last
  number (2.3.x); a bigger jump only when he says so.
- Commit messages plain: no session links, no Co-Authored-By.
- Log requests in `docs/CHANGELOG.md` by number; new ideas go there and on
  "the checklist": artifact **Darkroom Release Sweep**,
  https://claude.ai/artifact/KrvhMZrV3RUNie7YHxYewQ (republish to the same
  URL; finished items are removed).
- Every ~3 main builds, remind him if the iPhone App Store is behind.

## Stores

- `main` → Play internal testing + TestFlight. Closed testing:
  `promote-closed.yml` when he says a build is stable.
- `appstore-release.yml` only on "release to iPhone", after checking App
  Store Connect; never cancel a submission in review.
- Never run `play-listing.yml` unless asked (the Play Console is the copy).

## Never

- Anything that unlocks Pro in this public repo; the Debug password; the
  upload key.
- Real brand names (Kodak, Polaroid, Windows, Minesweeper…) in the app or
  listings.
- A Podfile; deleting `AndroidManifest.xml` / `android/app/build.gradle.kts`;
  changing `com.dingo.darkroom`.
- GPL FFmpeg filters, shader uniforms out of step with the `.frag` files,
  a GLES y-flip (contract tests check), or switching on a camera id
  outside `camera_catalog.dart`.
- Opacity layers inside an `OnTop` on the 3D face; `Colors.white/black` in
  Win98 UI (use `W98.*`); `HapticFeedback` (use `Haptics`).

## Our copy of flutter_scene

`packages/flutter_scene` is flutter_scene 0.24.3 with one patch (half-size
textures where the GPU can't compress them; `packages/flutter_scene/
DARKROOM.md`). Now and then check pub.dev for a newer version: if it handles
this itself, go back to the hosted package; else move the patch over.

## Checks

`flutter analyze lib test`, `flutter test` (SDK may be at
`/tmp/flutter/bin`; set `FLUTTER_ROOT`). `dart format -l 110` on changed
files only. Screens: `test/*_screens_test.dart`, `SHOTS=dir` for PNGs.
Phone numbers: ask for Debug > Launch Timing / Performance Report.
