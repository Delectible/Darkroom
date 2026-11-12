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
  capture mode, and through Camera2Interop `FLASH_MODE_SINGLE` with AE on.
  Those options land on the still request, where they win (single capture
  options over session options, CameraX's CaptureConfigAdapter), and on the
  preview's repeating requests too, where SINGLE fired the flash on a
  preview frame (2.2.9).
- `ImageCaptureProxyApi.takePicture` / `DarkroomFastFlash.quietPreview`:
  before an armed capture's first photo, `FLASH_MODE_OFF` through the
  camera's Camera2CameraControl, which overrides the session's options for
  the repeating requests (merged last) but not the still's own. So the
  flash fires on the photo's frame only. `release` (the app, when off or a
  camera opens) clears it again, so CameraX's torch etc. work as before.
- AE `ON_ALWAYS_FLASH` without a pre-flash was tried (2.2.10): a Pixel
  never fired it.
- Each still's (not the preview's) flash mode, FLASH_STATE and AE state go
  back over the channel (`log`) into the app's Camera Log.

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
