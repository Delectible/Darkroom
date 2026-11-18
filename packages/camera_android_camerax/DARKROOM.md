# Darkroom's copy of camera_android_camerax

A copy of [camera_android_camerax](https://pub.dev/packages/camera_android_camerax)
0.7.6+1 (BSD, see LICENSE): `lib`, `android` (its tests left out), used through
`dependency_overrides` in the root `pubspec.yaml`. Its dev dependencies are
dropped from its pubspec.

## The change

`DarkroomLens.java` (new) and `CameraSelectorProxyApi.java`
(`pigeon_defaultConstructor`, marked `DARKROOM PATCH`): when the app has set
`DarkroomLens.physicalId` (MainActivity, channel `darkroom/display`, method
`pinLens`), the back camera's selector gets CameraX's
`CameraSelector.Builder.setPhysicalCameraId`: every stream (viewfinder,
photo, video, analysis) comes from that one physical lens, and the phone
never changes lens by itself. Null: as upstream.

## Updating / undoing

- Undo: delete the `camera_android_camerax` override in the root
  `pubspec.yaml` and this folder (the app falls back to zoom limits).
- New version: copy it here the same way and reapply the patch, if the
  plugin still has no way to choose a physical camera.
