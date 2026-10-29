import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../camera/application/camera_ui_state.dart' show PrefKeys;

/// The Darkroom 98 monitor's settings (Tools > Options > Monitor / Screen
/// Saver): the kind of tube, the resolution the desktop runs at, the
/// knobs, the colour, large fonts and the screen saver.
///
/// [Win98Display.current] holds the live value for everything drawn on the
/// monitor, dialogs and [Win98Scale] included (they have no `ref`), the
/// way `W98.scheme` holds the colour scheme.

/// The desktop's resolution: chunkier or finer pixels on the same glass.
enum Win98Res {
  vga('640 x 480', portrait: 1.42, landscape: 1.12, scanline: 3.0),
  svga('800 x 600', portrait: 1.3, landscape: 1.0, scanline: 2.5),
  xga('1024 x 768', portrait: 1.12, landscape: 0.88, scanline: 2.0);

  const Win98Res(this.label, {required this.portrait, required this.landscape, required this.scanline});

  final String label;

  /// [Win98Scale]'s factor upright / its cap sideways.
  final double portrait, landscape;

  /// The CRT's scan line pitch (dp): fewer, fatter lines at low resolution.
  final double scanline;
}

/// The colour the tube shows: a temperature, or a mono phosphor.
enum Win98Tint {
  normal('Normal'),
  warm('Warm (6500K)'),
  cool('Cool (9300K)'),
  green('Green screen'),
  amber('Amber screen');

  const Win98Tint(this.label);

  final String label;

  bool get mono => this == green || this == amber;
}

enum Win98Saver {
  none('(None)'),
  pipes('3D Pipes'),
  stars('Starfield'),
  text('3D Text');

  const Win98Saver(this.label);

  final String label;
}

@immutable
class Win98Display {
  const Win98Display({
    this.crt = false,
    this.res = Win98Res.svga,
    this.brightness = 0.5,
    this.contrast = 0.5,
    this.tint = Win98Tint.normal,
    this.largeFonts = false,
    this.saver = Win98Saver.pipes,
    this.saverText = 'Darkroom 98',
    this.saverWait = 3,
  });

  /// A curved tube (scan lines, glow, degauss button) or a crisp flat panel.
  final bool crt;
  final Win98Res res;

  /// The knobs, 0..1 (0.5 = as made).
  final double brightness, contrast;
  final Win98Tint tint;
  final bool largeFonts;
  final Win98Saver saver;
  final String saverText;

  /// Minutes without a touch before the screen saver starts.
  final int saverWait;

  static const waits = [1, 3, 5, 10];
  static const fontScale = 1.15;

  /// The live settings (see the file comment).
  static final current = ValueNotifier(const Win98Display());

  Win98Display copyWith({
    bool? crt,
    Win98Res? res,
    double? brightness,
    double? contrast,
    Win98Tint? tint,
    bool? largeFonts,
    Win98Saver? saver,
    String? saverText,
    int? saverWait,
  }) => Win98Display(
    crt: crt ?? this.crt,
    res: res ?? this.res,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    tint: tint ?? this.tint,
    largeFonts: largeFonts ?? this.largeFonts,
    saver: saver ?? this.saver,
    saverText: saverText ?? this.saverText,
    saverWait: saverWait ?? this.saverWait,
  );

  Map<String, Object> toJson() => {
    'crt': crt,
    'res': res.name,
    'brightness': brightness,
    'contrast': contrast,
    'tint': tint.name,
    'largeFonts': largeFonts,
    'saver': saver.name,
    'saverText': saverText,
    'saverWait': saverWait,
  };

  static Win98Display fromJson(String? s) {
    if (s == null) return const Win98Display();
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      T pick<T extends Enum>(List<T> values, Object? name, T or) =>
          values.firstWhere((v) => v.name == name, orElse: () => or);
      const d = Win98Display();
      return Win98Display(
        crt: m['crt'] as bool? ?? d.crt,
        res: pick(Win98Res.values, m['res'], d.res),
        brightness: (m['brightness'] as num?)?.toDouble() ?? d.brightness,
        contrast: (m['contrast'] as num?)?.toDouble() ?? d.contrast,
        tint: pick(Win98Tint.values, m['tint'], d.tint),
        largeFonts: m['largeFonts'] as bool? ?? d.largeFonts,
        saver: pick(Win98Saver.values, m['saver'], d.saver),
        saverText: m['saverText'] as String? ?? d.saverText,
        saverWait: m['saverWait'] as int? ?? d.saverWait,
      );
    } catch (_) {
      return const Win98Display();
    }
  }

  /// [Win98Scale]'s factor on a [size] screen at this resolution.
  double scaleFor(Size size) =>
      size.width > size.height ? math.min(res.landscape, size.height / 420 * res.landscape) : res.portrait;

  /// The knobs and the colour as one colour matrix; null when the picture
  /// is as made (no filter layer at all).
  List<double>? get matrix {
    if (tint == Win98Tint.normal && (brightness - 0.5).abs() < 0.01 && (contrast - 0.5).abs() < 0.01) {
      return null;
    }
    // contrast 0.55x..1.45x round mid grey, brightness -60..+60 (of 255)
    final c = 0.55 + contrast * 0.9;
    final b = (brightness - 0.5) * 120 + 127.5 * (1 - c);
    var m = <double>[c, 0, 0, 0, b, 0, c, 0, 0, b, 0, 0, c, 0, b, 0, 0, 0, 1, 0];
    final List<double>? colour = switch (tint) {
      Win98Tint.normal => null,
      Win98Tint.warm => [1.04, 0, 0, 0, 4, 0, 0.98, 0, 0, 0, 0, 0, 0.84, 0, 0, 0, 0, 0, 1, 0],
      Win98Tint.cool => [0.9, 0, 0, 0, 0, 0, 0.98, 0, 0, 0, 0, 0, 1.06, 0, 8, 0, 0, 0, 1, 0],
      // luma through a phosphor's colour, with a faint glow in the blacks
      Win98Tint.green => _phosphor(0.33, 1.0, 0.42, const [4, 18, 6]),
      Win98Tint.amber => _phosphor(1.0, 0.66, 0.12, const [18, 10, 2]),
    };
    if (colour != null) m = _mul(colour, m);
    return m;
  }

  static List<double> _phosphor(double r, double g, double b, List<double> floor) {
    const y = [0.2126, 0.7152, 0.0722];
    final k = [r, g, b];
    return [
      for (var row = 0; row < 3; row++) ...[for (final w in y) w * k[row] * 0.92, 0, floor[row]],
      0,
      0,
      0,
      1,
      0,
    ];
  }

  /// a x b for 4x5 colour matrices (b applied first).
  static List<double> _mul(List<double> a, List<double> b) {
    final out = List<double>.filled(20, 0);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 5; c++) {
        var v = c == 4 ? a[r * 5 + 4] : 0.0;
        for (var k = 0; k < 4; k++) {
          v += a[r * 5 + k] * b[k * 5 + c];
        }
        out[r * 5 + c] = v;
      }
    }
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is Win98Display && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

class Win98DisplayNotifier extends Notifier<Win98Display> {
  @override
  Win98Display build() {
    try {
      return Win98Display.fromJson(ref.read(sharedPrefsProvider).getString(PrefKeys.win98Display));
    } catch (_) {
      return const Win98Display(); // tests without prefs
    }
  }

  /// Applies [d] everywhere now; [save] = false while a knob is turning.
  void set(Win98Display d, {bool save = true}) {
    state = d;
    Win98Display.current.value = d;
    if (!save) return;
    try {
      ref.read(sharedPrefsProvider).setString(PrefKeys.win98Display, jsonEncode(d.toJson()));
    } catch (_) {}
  }
}

final win98DisplayProvider = NotifierProvider<Win98DisplayNotifier, Win98Display>(Win98DisplayNotifier.new);

/// When the monitor was last touched (any finger, anywhere: dialogs and
/// games too), for the screen saver.
class Win98Idle {
  const Win98Idle._();

  static DateTime last = DateTime.now();
  static bool _listening = false;

  /// Something is happening on screen (a clip playing): not idle.
  static void poke() => last = DateTime.now();

  static void listen() {
    if (_listening) return;
    _listening = true;
    poke();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_seen);
  }

  static void stop() {
    if (!_listening) return;
    _listening = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_seen);
  }

  static void _seen(PointerEvent e) => poke();
}

/// The monitor's glass over [child]: the knobs and the colour (one colour
/// matrix), and on a CRT its scan lines. [screen]: the whole screen (the
/// glass's bulge, its glow and a glint too); dialogs and menus get just the
/// colour and the lines.
class Win98Glass extends StatefulWidget {
  const Win98Glass({super.key, required this.child, this.screen = false});

  final Widget child;
  final bool screen;

  @override
  State<Win98Glass> createState() => _Win98GlassState();
}

class _Win98GlassState extends State<Win98Glass> {
  // The layers round the child come and go with the settings; the key keeps
  // what's under them (a dialog's open tab, the explorer) as it was.
  final _content = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Win98Display>(
      valueListenable: Win98Display.current,
      builder: (context, d, _) {
        final m = d.matrix;
        final child = KeyedSubtree(key: _content, child: widget.child);
        Widget out = m == null ? child : ColorFiltered(colorFilter: ColorFilter.matrix(m), child: child);
        if (d.crt) {
          out = Stack(
            fit: StackFit.passthrough,
            children: [
              out,
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: CrtGlassPainter(
                        pitch: d.res.scanline,
                        screen: widget.screen,
                        ratio: MediaQuery.devicePixelRatioOf(context),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        return out;
      },
    );
  }
}

/// A CRT's face: scan lines, and on the whole [screen] the glass bulging
/// out at you: a soft dark falloff round its rounded edge, a broad sheen
/// across the middle, a glint top left, the tube's faint glow at the rim.
/// The glass (all soft shapes) is drawn once per size into a half-res
/// picture; only the lines are drawn live.
class CrtGlassPainter extends CustomPainter {
  const CrtGlassPainter({required this.pitch, this.screen = true, this.lines = true, this.ratio = 1});

  final double pitch;
  final bool screen;

  /// The scan lines (off for the glass laid over the bulged picture, which
  /// carries its own lines).
  final bool lines;
  final double ratio;

  /// The tube's corners: the monitor's opening has the same.
  static const radius = 26.0;
  static ui.Image? _glass;
  static Size? _glassSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (screen && !size.isEmpty) {
      final glass = _glassFor(size);
      canvas.drawImageRect(
        glass,
        Offset.zero & Size(glass.width.toDouble(), glass.height.toDouble()),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    if (!lines) return;
    // Scan lines: the gap between the beam's lines.
    final h = pitch * 0.38;
    final path = Path();
    for (var y = pitch - h; y < size.height; y += pitch) {
      path.addRect(Rect.fromLTWH(0, y, size.width, h));
    }
    canvas.drawPath(path, Paint()..color = const Color(0x1C000000));
  }

  ui.Image _glassFor(Size size) {
    final cached = _glass;
    if (cached != null && _glassSize == size) return cached;
    final k = math.max(1.0, ratio * 0.5);
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder)..scale(k);
    final all = Offset.zero & size;
    final short = size.shortestSide;
    final face = RRect.fromRectAndRadius(all, const Radius.circular(radius));
    c.clipRRect(face);
    // The bulge: the glass curving away into the dark round its edge.
    c.drawRRect(
      face,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = short * 0.05
        ..color = const Color(0x8C000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, short * 0.025),
    );
    // A whisper of vignette toward the corners.
    c.drawRect(
      all,
      Paint()
        ..shader =
            const RadialGradient(
              radius: 0.75,
              colors: [Color(0x00000000), Color(0x00000000), Color(0x1A000000)],
              stops: [0, 0.7, 1],
            ).createShader(
              Rect.fromCenter(center: all.center, width: size.width * 1.1, height: size.height * 1.1),
            ),
    );
    // A broad sheen on the dome, a little above and left of centre.
    final dome = Rect.fromCenter(
      center: all.center + Offset(-size.width * 0.06, -size.height * 0.08),
      width: size.width * 0.95,
      height: size.height * 0.8,
    );
    c.drawOval(
      dome,
      Paint()
        ..color = const Color(0x0DFFFFFF)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, short * 0.12),
    );
    // The glint where the room's light catches the curve.
    final glint = Rect.fromLTWH(size.width * 0.06, size.height * 0.04, size.width * 0.45, size.height * 0.12);
    c.drawOval(
      glint,
      Paint()
        ..color = const Color(0x14FFFFFF)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, short * 0.05),
    );
    // The tube's glow at the rim.
    c.drawRRect(
      face.deflate(1.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0x16B8DCFF),
    );
    final image = recorder.endRecording().toImageSync((size.width * k).ceil(), (size.height * k).ceil());
    _glass?.dispose();
    _glass = image;
    _glassSize = size;
    return image;
  }

  @override
  bool shouldRepaint(CrtGlassPainter old) =>
      old.pitch != pitch || old.screen != screen || old.lines != lines || old.ratio != ratio;
}

/// A CRT's picture bulging out of the curved glass (`shaders/crt_bulge.frag`
/// through ImageFilter.shader): the edges bow outward, the corners fall away
/// into black. Touches are mapped the same way, so a tap lands on what's
/// drawn under the finger. Only where the engine runs shader filters
/// (Impeller), and only while [still] (a shader filter under a moving
/// transition draws in the wrong place): it eases in once the screen has
/// arrived and drops out as it leaves.
class CrtWarp extends StatefulWidget {
  const CrtWarp({super.key, required this.on, required this.child});

  final bool on;
  final Widget child;

  /// How far it bulges (the middle of each edge stays put; the corners pull
  /// in a few percent).
  static const amount = 0.05;

  static Future<ui.FragmentProgram>? _program;

  /// The pixel of content drawn at [p] on a [size] screen bulging by [k]
  /// (the shader's mapping).
  static Offset sourceOf(Offset p, Size size, double k) {
    final a = size.width / size.height;
    final dx = p.dx / size.width - 0.5, dy = p.dy / size.height - 0.5;
    final r2 = (dx * dx * a * a + dy * dy) / (0.25 * (a * a + 1));
    final f = 1 + k * r2, e = 1 / (a * a + 1);
    return Offset(
      (0.5 + dx * f / (1 + k * a * a * e)) * size.width,
      (0.5 + dy * f / (1 + k * e)) * size.height,
    );
  }

  @override
  State<CrtWarp> createState() => _CrtWarpState();
}

class _CrtWarpState extends State<CrtWarp> with SingleTickerProviderStateMixin {
  final _content = GlobalKey();
  late final _ease = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  ui.FragmentShader? _shader;
  Animation<double>? _route;

  @override
  void initState() {
    super.initState();
    if (ui.ImageFilter.isShaderFilterSupported) {
      CrtWarp._program ??= ui.FragmentProgram.fromAsset('shaders/crt_bulge.frag');
      CrtWarp._program!.then((p) {
        if (mounted) setState(() => _shader = p.fragmentShader());
      }, onError: (Object _) {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final a = ModalRoute.of(context)?.animation;
    if (a != _route) {
      _route?.removeStatusListener(_settle);
      _route = a?..addStatusListener(_settle);
      _settle(a?.status ?? AnimationStatus.completed);
    }
  }

  void _settle(AnimationStatus s) {
    if (s == AnimationStatus.completed) {
      _ease.forward();
    } else {
      _ease.value = 0;
    }
  }

  @override
  void dispose() {
    _route?.removeStatusListener(_settle);
    _ease.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = KeyedSubtree(key: _content, child: widget.child);
    final shader = _shader;
    if (shader == null || !widget.on) return child;
    return AnimatedBuilder(
      animation: _ease,
      builder: (context, _) {
        final k = CrtWarp.amount * Curves.easeOut.transform(_ease.value);
        if (k <= 0) return child;
        shader.setFloat(2, k);
        return _WarpHits(
          k: k,
          // A fresh filter each time: the engine snapshots the uniforms.
          child: ImageFiltered(imageFilter: ui.ImageFilter.shader(shader), child: child),
        );
      },
    );
  }
}

/// Hit testing through the bulge: a touch at a point goes to the content
/// drawn there (each pointer keeps the offset it went down with).
class _WarpHits extends SingleChildRenderObjectWidget {
  const _WarpHits({required this.k, required super.child});

  final double k;

  @override
  _RenderWarpHits createRenderObject(BuildContext context) => _RenderWarpHits(k);

  @override
  void updateRenderObject(BuildContext context, _RenderWarpHits renderObject) => renderObject.k = k;
}

class _RenderWarpHits extends RenderProxyBox {
  _RenderWarpHits(this.k);

  double k;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final c = child;
    if (c == null) return false;
    final source = CrtWarp.sourceOf(position, size, k);
    final shift = source - position;
    return result.addWithRawTransform(
      transform: Matrix4.translationValues(shift.dx, shift.dy, 0),
      position: position,
      hitTest: (result, position) => c.hitTest(result, position: position),
    );
  }
}
