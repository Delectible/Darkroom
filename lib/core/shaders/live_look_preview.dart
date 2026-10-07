import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_shaders/flutter_shaders.dart';

import '../../features/cameras/domain/camera_spec.dart';
import '../processing/crop_math.dart';
import '../processing/film/film_profile.dart';
import '../processing/look_spec.dart';
import 'shader_library.dart';

/// Applies a camera's look shader to [child] (the live camera texture).
///
/// * Impeller: `ImageFilter.shader` — the engine feeds the child's texture
///   straight into the fragment shader on the raster thread. No readbacks,
///   no per-frame `ui.Image` allocations; the UI thread only bumps uniforms.
/// * Skia fallback: `AnimatedSampler` snapshots the child each frame and
///   draws it through the same shader (slower, identical maths).
///
/// Frame budget: grain / noise re-roll at the look's own cadence (24 fps for
/// film, 18 for Super 8, 15 for the VGA phone, 30 for CCD/tape) on a plain
/// Timer rather than a vsync Ticker, which would re-render the whole scene
/// at 90-120 Hz on modern phones for no visible gain.
class LiveLookPreview extends ConsumerStatefulWidget {
  const LiveLookPreview({
    super.key,
    required this.spec,
    required this.crop,
    required this.child,
    this.grain = GrainStrength.normal,
    this.canvas,
    this.turns = 0,
    this.spin = 0,
    this.spinScale = 1,
  });

  final CameraSpec spec;
  final GrainStrength grain;

  /// Unmasked area of the preview (normalised) — keeps vignette, gate and
  /// grain relative to the frame that will actually be exported.
  final UnitRect crop;

  /// Super 8: the full-gate film strip's area of the preview (CineStrip),
  /// and the viewer's quarter turns so the strip stays upright for them.
  final UnitRect? canvas;
  final int turns;

  /// Super 8: the strip swinging round to a new [turns] (radians clockwise
  /// about the box centre, and its scale). Done in the shader so the strip,
  /// its sprocket hole and the picture turn as one.
  final double spin;
  final double spinScale;
  final Widget child;

  @override
  ConsumerState<LiveLookPreview> createState() => _LiveLookPreviewState();
}

class _LiveLookPreviewState extends ConsumerState<LiveLookPreview> {
  Timer? _timer;
  int _frame = 0;
  int _fps = 0;
  final ValueNotifier<double> _time = ValueNotifier<double>(0);

  /// One shader instance per kind, kept until unmount (at most four).
  final Map<ShaderKind, ui.FragmentShader> _shaders = {};

  ShaderKind get _kind => widget.spec.film != null ? ShaderKind.film : widget.spec.look!.kind;

  int get _targetFps {
    final film = widget.spec.film;
    if (film != null) return film.isCine ? 18 : 24;
    return switch (widget.spec.look!.kind) {
      ShaderKind.jpegPixel => 15,
      _ => 30,
    };
  }

  void _syncTimer() {
    final fps = _targetFps;
    if (fps == _fps && _timer != null) return;
    _fps = fps;
    _timer?.cancel();
    _timer = Timer.periodic(Duration(microseconds: 1000000 ~/ fps), (_) {
      _frame++;
      _time.value = _frame / _fps;
    });
  }

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(LiveLookPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _time.dispose();
    for (final s in _shaders.values) {
      s.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final programs = ref.watch(shaderProgramsProvider).value;
    final child = RepaintBoundary(child: widget.child);
    if (programs == null) return child;
    final kind = _kind;
    final shader = _shaders.putIfAbsent(kind, () => programs.looks[kind]!.fragmentShader());

    // Film needs its LUT + the grain tile; show the plain feed for the few
    // milliseconds they take to build.
    final film = widget.spec.film;
    ui.Image? lut, grain;
    if (film != null) {
      lut = ref.watch(filmLutImageProvider(widget.spec.id)).value;
      grain = ref.watch(grainImageProvider).value;
      if (lut == null || grain == null) return child;
    }

    void setUniforms(double t, ui.Size? size) {
      if (film != null) {
        FilmUniforms.apply(
          shader,
          film,
          time: t,
          crop: widget.crop,
          grain: widget.grain,
          fps: _fps.toDouble(),
          lut: lut!,
          grainImage: grain!,
          size: size,
          canvas: widget.canvas,
          turns: widget.turns,
          spin: widget.spin,
          spinScale: widget.spinScale,
        );
      } else {
        LookUniforms.apply(shader, widget.spec.look!, time: t, crop: widget.crop, size: size);
      }
    }

    if (ui.ImageFilter.isShaderFilterSupported) {
      return ValueListenableBuilder<double>(
        valueListenable: _time,
        child: child,
        builder: (context, t, child) {
          setUniforms(t, null);
          // A fresh filter object per frame: the native filter snapshots the
          // uniforms, so equality changes and the layer re-renders.
          return ImageFiltered(imageFilter: ui.ImageFilter.shader(shader), child: child);
        },
      );
    }

    // Skia: the camera texture updating does not repaint Flutter widgets, so
    // rebuild every tick (a new builder closure makes AnimatedSampler
    // re-snapshot the child).
    return ValueListenableBuilder<double>(
      valueListenable: _time,
      child: child,
      builder: (context, t, child) => AnimatedSampler((image, size, canvas) {
        setUniforms(t, size);
        shader.setImageSampler(0, image);
        canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
      }, child: child!),
    );
  }
}
