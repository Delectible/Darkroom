import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

/// The live 3D camera bodies (assets/body3d/*.glb, made by
/// tool/render/blender/export_glb.py) become Flutter Scene packages at build
/// time, their textures stored as GPU block compression (transcoded to the
/// phone's format on load: a quarter of the memory of plain RGBA).
void main(List<String> args) async {
  await build(args, (input, output) async {
    buildScenes(buildInput: input, buildOutput: output, discoveryRoot: 'assets/body3d/', compressTextures: true);
  });
}
