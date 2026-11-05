import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cameras/domain/camera_spec.dart';
import '../application/lens_controller.dart';

/// The lens on the camera, over the live viewfinder (shaders/lens.frag as an
/// ImageFilter.shader). The standard lens: nothing, the picture as it is.
/// Where shader filters aren't supported (Skia) only the photo shows it.
class LensPreview extends ConsumerStatefulWidget {
  const LensPreview({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LensPreview> createState() => _LensPreviewState();
}

class _LensPreviewState extends ConsumerState<LensPreview> {
  static Future<ui.FragmentProgram>? _program;
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    (_program ??= ui.FragmentProgram.fromAsset('shaders/lens.frag')).then((p) {
      if (mounted) setState(() => _shader = p.fragmentShader());
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lens = ref.watch(filmLensProvider);
    final shader = _shader;
    // (a still child either way: switching lens doesn't rebuild the picture)
    final child = KeyedSubtree(key: const ValueKey('picture'), child: widget.child);
    if (shader == null || lens == LensKind.standard) {
      return ImageFiltered(enabled: false, imageFilter: _none, child: child);
    }
    // uniforms: 0-1 the size (the engine's), 2 the lens
    shader.setFloat(2, lens.index.toDouble());
    return ImageFiltered(imageFilter: ui.ImageFilter.shader(shader), child: child);
  }

  static final _none = ui.ImageFilter.matrix(Matrix4.identity().storage);
}
