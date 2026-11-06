import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/processing/crop_math.dart';
import '../../cameras/domain/camera_spec.dart';
import '../application/lens_controller.dart';

/// The lens on the camera, over the live viewfinder (shaders/lens.frag as an
/// ImageFilter.shader). The standard lens: nothing, the picture as it is.
/// Where shader filters aren't supported (Skia) only the photo shows it.
class LensPreview extends ConsumerWidget {
  const LensPreview({super.key, required this.crop, required this.child});

  /// The frame that's seen (the photo) in the picture: the lens sits on it.
  final UnitRect crop;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      LensFilter(lens: ref.watch(filmLensProvider), crop: crop, child: child);
}

/// [child] through [lens] (shaders/lens.frag), the lens sitting on [crop]:
/// the viewfinder, and an instant print developing on the photo as taken.
class LensFilter extends StatefulWidget {
  const LensFilter({super.key, required this.lens, this.crop = full, required this.child});

  static const full = UnitRect(0, 0, 1, 1);

  final LensKind lens;
  final UnitRect crop;
  final Widget child;

  @override
  State<LensFilter> createState() => _LensFilterState();
}

class _LensFilterState extends State<LensFilter> {
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
    final lens = widget.lens;
    final shader = _shader;
    // (a still child either way: switching lens doesn't rebuild the picture)
    final child = KeyedSubtree(key: const ValueKey('picture'), child: widget.child);
    if (shader == null || lens == LensKind.standard) {
      return ImageFiltered(enabled: false, imageFilter: _none, child: child);
    }
    // uniforms: 0-1 the size (the engine's), 2 the lens, 3-6 the frame
    shader
      ..setFloat(2, lens.index.toDouble())
      ..setFloat(3, widget.crop.left)
      ..setFloat(4, widget.crop.top)
      ..setFloat(5, widget.crop.width)
      ..setFloat(6, widget.crop.height);
    return ImageFiltered(imageFilter: ui.ImageFilter.shader(shader), child: child);
  }

  static final _none = ui.ImageFilter.matrix(Matrix4.identity().storage);
}
