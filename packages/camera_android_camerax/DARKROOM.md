# Darkroom's copy of camera_android_camerax 0.7.5+1

A copy of [camera_android_camerax](https://pub.dev/packages/camera_android_camerax)
0.7.5+1 (BSD, see LICENSE), the camera plugin's Android side, used through
`dependency_overrides` in the root `pubspec.yaml`. Its example, tests,
pigeons and skills are left out, and its dev_dependencies removed. The root
`analysis_options.yaml` excludes `packages/**`.

## The one change: the digital cameras' fast flash

The phone's own flash meters first (a pre-flash, exposure and focus
settling): about 2 s from press to capture on a Pixel 9 Pro. A 2000s
digicam just fired. Marked `DARKROOM PATCH`:

- `DarkroomFastFlash.java`: a method channel `darkroom/fast_flash`
  (`arm`: bool), set up in `CameraAndroidCameraxPlugin.onAttachedToEngine`.
- `ImageCaptureProxyApi.pigeon_defaultConstructor`: an ImageCapture built
  while armed has CameraX's flash off (no pre-flash), the lowest-latency
  capture mode, and through Camera2Interop AE mode `ON_ALWAYS_FLASH`: the
  camera fires the flash for still captures only, at the exposure the
  preview already had. (Interop options on the ImageCapture reach the
  preview's repeating requests too: `FLASH_MODE_SINGLE` there fired the
  flash on a preview frame just after arming, and never on the photo.) Its session capture callback reports
  each still's (not the preview's) flash mode, FLASH_STATE and AE state back over the channel
  (`log`), into the app's Camera Log.

The app (`FastFlash` in lib/features/camera/application/) arms it for a
digital camera's back flash set to On, recreates the ImageCapture through
`setJpegImageQuality` and sets the plugin's flash mode off; disarmed, the
same in reverse.

## Updating / undoing

- Undo: remove the `camera_android_camerax` override from the root
  `pubspec.yaml`, delete this folder, and `FastFlash` falls back to the
  phone's flash (its channel is missing: it never arms).
- Newer version: copy it in the same way and move the patch over (search
  `DARKROOM PATCH`).
