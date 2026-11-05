# Darkroom's copy of flutter_scene 0.24.3

A copy of [flutter_scene](https://pub.dev/packages/flutter_scene) 0.24.3
(MIT, see LICENSE), used by the app through a path dependency in the root
`pubspec.yaml`. Its tests, build cache, screenshots, skills and example are
left out; `resolution: workspace` is removed from its pubspec.

## The one change

`lib/src/texture/compressed_texture.dart`, `_prepare`: on the uncompressed
(rgba8) fallback, a texture 1024 px or wider loads from its half-size mip
(a quarter of the memory). Marked `DARKROOM PATCH`. Only phones whose GPU
driver reports no compressed formats take that path (a Pixel 9 Pro: 192 MB
a 3D camera, ~48 after); iPhones and the tablet use ASTC and are untouched.

## Updating / undoing

- Undo: in the root `pubspec.yaml` set `flutter_scene: ^0.24.3` (or newer)
  instead of the path, and delete `packages/flutter_scene`.
- New version: check https://pub.dev/packages/flutter_scene/changelog. If
  it sizes uncompressed textures itself (or exposes a setting), drop the copy.
  Otherwise copy the new version here the same way and reapply the patch.
