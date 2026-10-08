import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/device/physical_orientation.dart';
import '../../../core/device/upright.dart';
import '../../../core/processing/cine_strip.dart';
import '../../../core/processing/crop_math.dart';
import '../../../core/processing/photo_pipeline.dart';
import '../../../core/providers.dart';
import '../../../core/shaders/live_look_preview.dart';
import '../../../core/theme/retro_theme.dart';
import '../../../core/theme/surfaces.dart';
import '../../../core/utils/pixel_font.dart';
import '../../cameras/domain/camera_spec.dart';
import '../application/camera_session_controller.dart';
import '../application/camera_ui_state.dart';
import '../application/capture_controller.dart';
import '../application/zoom_controller.dart';

/// The viewfinder: shader-filtered live preview, aspect-ratio mask, burned-in
/// timestamp preview, tap-to-focus and the shutter blink.
///
/// Geometry contract (see CropMath): the preview box always has the preview
/// stream's portrait aspect ratio (never cover-cropped), and the unmasked
/// rect is CropMath.previewMask(...). The export uses CropMath.stillCrop(...)
/// with the same inputs, so the saved frame == what's inside the mask.
class CameraViewport extends ConsumerWidget {
  const CameraViewport({super.key});

  /// The live viewfinder's own layer, for taking a still of it.
  static final snapKey = GlobalKey(debugLabel: 'viewfinder');

  /// A still shown over the viewfinder while the body is tossed: the look
  /// shaders are ImageFilter.shader filters, and under the toss's 3D
  /// transform only their input moves (the Super 8 strip's sprocket hole
  /// slid about on its own). The rest of the body stays live.
  static final freeze = ValueNotifier<ui.Image?>(null);

  /// The live picture keeps running under [freeze] (which is then a fresh
  /// still of it every frame, taken flat: the viewfinder stays live while
  /// the body turns).
  static final liveUnder = ValueNotifier<bool>(false);

  /// The stream's aspect ratio last time a camera was open: while it's
  /// closed (behind a panel, mid-swap) the box keeps its shape, so the still
  /// over it isn't squashed.
  static double _lastPreviewAspect = 16 / 9;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(cameraSessionProvider);
    final spec = ref.watch(activeSpecProvider);
    final local = ref.watch(activeCameraSettingsProvider);
    final palette = RetroPalette.of(context);
    final aspect = spec.aspectLocked ? spec.defaultAspect : local.aspect;
    final controller = session.controller;
    final previewAspect = (controller != null && controller.value.previewSize != null)
        ? _lastPreviewAspect = controller.value.aspectRatio
        : _lastPreviewAspect;
    // Super 8 frames landscape however the phone is held, inside a full-gate
    // film strip that stays upright for the viewer.
    final turns = spec.landscapeOnly ? uprightQuarterTurns(ref.watch(physicalOrientationProvider)) : 0;
    final mask = CropMath.previewMask(
      previewAspect: previewAspect,
      ratio: aspect,
      acrossShortSide: spec.landscapeOnly && turns.isEven,
    );
    final strip = (spec.film?.gate ?? 0) > 0
        ? CineStrip.previewCanvas(boxAspect: previewAspect, turns: turns, pictureAspect: aspect.ratio)
        : null;
    // What the viewer sees unmasked: the strip, or just the frame.
    final shown = strip ?? mask;

    return LayoutBuilder(
      builder: (context, box) {
        final portrait = 1 / previewAspect; // width / height of the preview box
        var w = box.maxWidth, h = w / portrait;
        if (h > box.maxHeight) {
          h = box.maxHeight;
          w = h * portrait;
        }
        final maskRect = Rect.fromLTWH(shown.left * w, shown.top * h, shown.width * w, shown.height * h);

        final radius = BorderRadius.circular(spec.mode == AppMode.film ? 6 : 3);
        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  key: snapKey,
                  child: ClipRRect(
                    borderRadius: radius,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: palette.screen),
                        // Super 8: when the phone turns, the strip swings round into
                        // its new place instead of jumping.
                        _StripTurn(
                          turns: turns,
                          cameraId: spec.id,
                          strip: maskRect.size,
                          builder: (spin, spinScale) {
                            // The live picture turns inside the shader (strip, hole
                            // and image together); the mask with a matching matrix.
                            final Widget maskLayer = IgnorePointer(
                              child: CustomPaint(
                                painter: _AspectMaskPainter(
                                  hole: maskRect,
                                  shade: palette.screen.withValues(
                                    alpha: spec.mode == AppMode.film ? 0.93 : 0.86,
                                  ),
                                  frame: spec.mode == AppMode.film
                                      ? palette.screenInk.withValues(alpha: 0.55)
                                      : palette.screenInk.withValues(alpha: 0.8),
                                  brackets: spec.mode == AppMode.digital,
                                ),
                              ),
                            );
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                // Under a held still (swap, panel, picker) the live
                                // picture isn't drawn at all: its look shader is the
                                // most expensive thing on screen.
                                ListenableBuilder(
                                  listenable: Listenable.merge([freeze, liveUnder]),
                                  builder: (context, _) => freeze.value != null && !liveUnder.value
                                      ? const SizedBox.expand()
                                      : session.isReady
                                      ? _FocusablePreview(
                                          controller: controller!,
                                          child: LiveLookPreview(
                                            spec: spec,
                                            grain: local.grain,
                                            crop: mask,
                                            canvas: strip,
                                            turns: turns,
                                            spin: spin,
                                            spinScale: spinScale,
                                            child: _RotationCorrectedPreview(controller: controller),
                                          ),
                                        )
                                      : _Standby(session: session),
                                ),
                                if (spin == 0 && spinScale == 1)
                                  maskLayer
                                else
                                  Transform(
                                    alignment: Alignment.center,
                                    transform: Matrix4.rotationZ(spin)
                                      ..scaleByDouble(spinScale, spinScale, 1, 1),
                                    child: maskLayer,
                                  ),
                              ],
                            );
                          },
                        ),
                        Positioned.fromRect(
                          rect: maskRect,
                          // In the user's frame: held sideways, the readouts (and the
                          // date, which is burned into the upright photo) follow.
                          child: IgnorePointer(
                            child: UprightBox(
                              child: _HudOverlay(spec: spec, timestamp: local.timestamp),
                            ),
                          ),
                        ),
                        const IgnorePointer(child: _ShutterBlink()),
                      ],
                    ),
                  ),
                ),
                // While the body is tossed, a still of the viewfinder stands in
                // for it (see [freeze]).
                ValueListenableBuilder<ui.Image?>(
                  valueListenable: freeze,
                  builder: (context, still, _) => still == null
                      ? const SizedBox.shrink()
                      : ClipRRect(
                          borderRadius: radius,
                          child: RawImage(image: still, fit: BoxFit.cover),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Swings the Super 8 viewfinder round when the phone is turned: the new
/// layout starts rotated back to where the old one was (and scaled to its
/// size), then turns and grows into place, so the strip follows the phone
/// instead of snapping. The turn is drawn by film.frag (`uSpin`): a Flutter
/// transform round an ImageFilter.shader only turns its input, which left
/// the shader-drawn sprocket hole behind.
class _StripTurn extends StatefulWidget {
  const _StripTurn({required this.turns, required this.cameraId, required this.strip, required this.builder});

  final int turns;
  final String cameraId;

  /// The strip's size on screen in this layout.
  final Size strip;

  /// Builds the viewfinder turned by (radians clockwise, scale).
  final Widget Function(double spin, double scale) builder;

  @override
  State<_StripTurn> createState() => _StripTurnState();
}

class _StripTurnState extends State<_StripTurn> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1,
  );
  double _fromAngle = 0, _fromScale = 1;

  @override
  void didUpdateWidget(_StripTurn old) {
    super.didUpdateWidget(old);
    if (old.turns == widget.turns || old.cameraId != widget.cameraId) return;
    final delta = (widget.turns - old.turns) % 4; // clockwise quarter turns
    _fromAngle = -(delta == 3 ? -1 : delta) * math.pi / 2;
    final o = old.strip, n = widget.strip;
    _fromScale = delta.isOdd && n.width > 0 && n.height > 0
        ? math.min(o.width / n.height, o.height / n.width).clamp(0.3, 3.0)
        : 1.0;
    _a.forward(from: 0);
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _a,
    builder: (context, _) {
      if (_a.value >= 1) return widget.builder(0, 1);
      final t = Curves.easeInOutCubic.transform(_a.value);
      return widget.builder(_fromAngle * (1 - t), _fromScale + (1 - _fromScale) * t);
    },
  );
}

/// Rotation contract with camera_android_camerax for a portrait-locked UI.
///
/// The plugin's buildPreview() *subtracts* the quarter turns it assumes the
/// stock CameraPreview widget pre-applied, computed from the **live** device
/// orientation stream (even when capture orientation is locked). We apply
/// exactly that pre-rotation from the same live value so the two cancel out
/// (net rotation == display rotation == 0), but unlike CameraPreview we never
/// flip the box to landscape, which would squash the image in a UI that does
/// not rotate. iOS needs nothing: capture orientation is locked to portrait,
/// so its preview buffer stays portrait.
class _RotationCorrectedPreview extends StatelessWidget {
  const _RotationCorrectedPreview({required this.controller});

  final CameraController controller;

  static int _turns(DeviceOrientation o) => switch (o) {
    DeviceOrientation.portraitUp => 0,
    DeviceOrientation.landscapeRight => 1,
    DeviceOrientation.portraitDown => 2,
    DeviceOrientation.landscapeLeft => 3,
  };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CameraValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (!value.isInitialized) return const SizedBox.shrink();
        final preview = controller.buildPreview();
        if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return preview;
        return RotatedBox(quarterTurns: _turns(value.deviceOrientation), child: preview);
      },
    );
  }
}

class _FocusablePreview extends StatefulWidget {
  const _FocusablePreview({required this.controller, required this.child});

  final CameraController controller;
  final Widget child;

  @override
  State<_FocusablePreview> createState() => _FocusablePreviewState();
}

class _FocusablePreviewState extends State<_FocusablePreview> {
  Offset? _point;
  Timer? _hide;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  Future<void> _onTap(TapUpDetails d, BoxConstraints box) async {
    final c = widget.controller;
    if (!c.value.isInitialized) return;
    final n = Offset(
      (d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0),
      (d.localPosition.dy / box.maxHeight).clamp(0.0, 1.0),
    );
    setState(() => _point = d.localPosition);
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _point = null);
    });
    try {
      if (c.value.focusPointSupported) await c.setFocusPoint(n);
      if (c.value.exposurePointSupported) await c.setExposurePoint(n);
    } on CameraException {
      // Not supported on this lens.
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = RetroPalette.of(context).screenInk;
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => _onTap(d, box),
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (_point != null)
              Positioned(
                left: _point!.dx - 34,
                top: _point!.dy - 34,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 1.4, end: 1),
                  duration: const Duration(milliseconds: 220),
                  builder: (context, s, _) => Transform.scale(
                    scale: s,
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(border: Border.all(color: ink, width: 1.4)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Standby extends ConsumerWidget {
  const _Standby({required this.session});

  final CameraSessionState session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = RetroPalette.of(context);
    final (label, action) = switch (session.status) {
      SessionStatus.permissionDenied => (session.message ?? 'Camera access needed', 'Grant access'),
      SessionStatus.error => (session.message ?? 'Camera error', 'Retry'),
      SessionStatus.noCamera => ('No camera on this device', null),
      _ => ('', null),
    };
    if (action == null && label.isEmpty) {
      return Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: palette.screenInk.withValues(alpha: 0.6)),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.screenInk),
            ),
            if (action != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.read(cameraSessionProvider.notifier).retry(),
                style: OutlinedButton.styleFrom(foregroundColor: palette.screenInk),
                child: Text(action),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AspectMaskPainter extends CustomPainter {
  _AspectMaskPainter({required this.hole, required this.shade, required this.frame, required this.brackets});

  final Rect hole;
  final Color shade;
  final Color frame;
  final bool brackets;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(hole);
    canvas.drawPath(path, Paint()..color = shade);
    final line = Paint()
      ..color = frame
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    if (!brackets) {
      // Rangefinder-style bright-line frame.
      canvas.drawRect(hole.deflate(6), line);
      final c = hole.center;
      canvas.drawCircle(c, 10, line..strokeWidth = 1);
      return;
    }
    final l = math.min(hole.width, hole.height) * 0.08;
    final r = hole.deflate(8);
    for (final (corner, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(corner, corner + Offset(l * dx, 0), line);
      canvas.drawLine(corner, corner + Offset(0, l * dy), line);
    }
  }

  @override
  bool shouldRepaint(_AspectMaskPainter old) =>
      old.hole != hole || old.shade != shade || old.frame != frame || old.brackets != brackets;
}

/// Frames already exposed on the current roll / pack of [FilmRoll].
final _filmFrameProvider = FutureProvider.family<int, FilmRoll>((ref, roll) async {
  ref.watch(filmItemsProvider); // re-read after every capture
  final v = await ref.read(appDatabaseProvider).getValue('counter.${roll.counter}');
  return (int.tryParse(v ?? '') ?? 0) % roll.frames;
});

/// Film-body counters: the next frame on the roll, or the footage left in a
/// Super 8 cartridge (it counts down while recording).
class _FilmCounter extends ConsumerWidget {
  const _FilmCounter({required this.spec, required this.color});

  final CameraSpec spec;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capture = ref.watch(captureControllerProvider);
    String text;
    if (spec.recordsVideo) {
      final elapsed = capture.isRecording ? DateTime.now().difference(capture.recordingSince!).inSeconds : 0;
      if (capture.isRecording) ref.watch(secondTickerProvider);
      // 50 ft cartridge, 4 seconds per foot at 18 fps.
      final feet = ((spec.videoMaxSeconds - elapsed) / 4).ceil().clamp(0, 50);
      text = '$feet FT';
    } else {
      final roll = spec.roll;
      final shots = ref.watch(_filmFrameProvider(roll)).value ?? 0;
      text = roll.countsDown ? '${roll.frames - shots} LEFT' : 'FRAME ${shots + 1}';
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (c, a) => ClipRect(
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.9), end: Offset.zero).animate(a),
          child: FadeTransition(opacity: a, child: c),
        ),
      ),
      child: Text(
        text,
        key: ValueKey(text),
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2),
      ),
    );
  }
}

/// In-frame readouts: REC timer, LCD status line, frame counter, timestamp
/// preview.
class _HudOverlay extends ConsumerWidget {
  const _HudOverlay({required this.spec, required this.timestamp});

  final CameraSpec spec;
  final bool timestamp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = RetroPalette.of(context);
    final capture = ref.watch(captureControllerProvider);
    final flash = ref.watch(activeFlashProvider);
    final digital = spec.mode == AppMode.digital;

    return LayoutBuilder(
      builder: (context, box) {
        final short = math.min(box.maxWidth, box.maxHeight);
        return Stack(
          children: [
            if (digital)
              Positioned(
                left: 12,
                top: 10,
                child: PixelText(
                  '${switch (flash) {
                    FlashSetting.auto => 'FLASH A',
                    FlashSetting.on => 'FLASH *',
                    FlashSetting.off => 'FLASH -',
                  }}  ${spec.badge}',
                  dot: 1.6,
                  color: palette.screenInk,
                ),
              ),
            if (!digital)
              Positioned(
                left: 12,
                bottom: 10,
                child: _FilmCounter(spec: spec, color: palette.screenInk.withValues(alpha: 0.85)),
              ),
            // Film (Super 8) just runs its footage counter down: no REC badge.
            if (capture.isRecording && digital)
              Positioned(
                right: 12,
                top: 10,
                child: _RecTimer(since: capture.recordingSince!, color: palette.danger),
              ),
            if (digital && spec.zoom != null)
              Positioned(
                left: 0,
                right: 0,
                top: box.maxHeight * 0.12,
                child: Center(
                  child: _ZoomIndicator(bar: spec.recordsVideo, short: short),
                ),
              ),
            if (timestamp && spec.supportsTimestamp)
              Positioned(
                right: spec.timestampStyle == TimestampStyle.phone ? 4 : box.maxWidth * 0.05,
                bottom: spec.timestampStyle == TimestampStyle.phone ? 4 : box.maxHeight * 0.05,
                child: _TimestampPreview(style: spec.timestampStyle, short: short),
              ),
          ],
        );
      },
    );
  }
}

/// Shows while the zoom motor runs and briefly after: a sliding W-T bar on
/// the camcorder's OSD, a plain "2.4X" readout on the stills cameras.
class _ZoomIndicator extends ConsumerStatefulWidget {
  const _ZoomIndicator({required this.bar, required this.short});

  final bool bar;
  final double short;

  @override
  ConsumerState<_ZoomIndicator> createState() => _ZoomIndicatorState();
}

class _ZoomIndicatorState extends ConsumerState<_ZoomIndicator> {
  Timer? _hide;
  bool _visible = false;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ZoomState>(zoomProvider, (prev, next) {
      if (next.changedAt == prev?.changedAt) return;
      _hide?.cancel();
      if (!_visible) setState(() => _visible = true);
      if (next.direction == 0) {
        _hide = Timer(const Duration(milliseconds: 1500), () {
          if (mounted) setState(() => _visible = false);
        });
      }
    });
    final zoom = ref.watch(zoomProvider);
    final dot = math.max(1.2, widget.short / 170);
    return AnimatedOpacity(
      opacity: _visible && zoom.canZoom ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: widget.bar
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PixelText('W', dot: dot, color: Colors.white, shadow: Colors.black),
                SizedBox(width: dot * 3),
                CustomPaint(
                  size: Size(widget.short * 0.42, dot * 7),
                  painter: _ZoomBarPainter(fraction: zoom.fraction, dot: dot),
                ),
                SizedBox(width: dot * 3),
                PixelText('T', dot: dot, color: Colors.white, shadow: Colors.black),
              ],
            )
          : PixelText(
              '${zoom.level.toStringAsFixed(1)}X',
              dot: dot,
              color: Colors.white,
              shadow: Colors.black,
            ),
    );
  }
}

/// Camcorder OSD zoom track: tick marks and a solid slider block.
class _ZoomBarPainter extends CustomPainter {
  _ZoomBarPainter({required this.fraction, required this.dot});

  final double fraction;
  final double dot;

  @override
  void paint(Canvas canvas, Size size) {
    void draw(Offset o, Color c) {
      final p = Paint()..color = c;
      final midY = size.height / 2;
      canvas.drawRect(Rect.fromLTWH(o.dx, midY - dot / 2 + o.dy, size.width, dot), p);
      const ticks = 10;
      for (var i = 0; i <= ticks; i++) {
        final x = (size.width - dot) * i / ticks;
        final h = i == 0 || i == ticks ? size.height : size.height * 0.55;
        canvas.drawRect(Rect.fromLTWH(x + o.dx, midY - h / 2 + o.dy, dot, h), p);
      }
      final bx = (size.width - dot * 3) * fraction.clamp(0.0, 1.0);
      canvas.drawRect(Rect.fromLTWH(bx + o.dx, o.dy, dot * 3, size.height), p);
    }

    draw(Offset(dot * 0.7, dot * 0.7), Colors.black);
    draw(Offset.zero, Colors.white);
  }

  @override
  bool shouldRepaint(_ZoomBarPainter old) => old.fraction != fraction || old.dot != dot;
}

class _TimestampPreview extends ConsumerWidget {
  const _TimestampPreview({required this.style, required this.short});

  final TimestampStyle style;
  final double short;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ticks once a second so the camcorder OSD clock runs live.
    final now = ref.watch(secondTickerProvider).value ?? DateTime.now();
    return switch (style) {
      TimestampStyle.ledDate => PixelText(
        TimestampFormat.ledDate(now),
        dot: math.max(1, short / 170),
        color: const Color(0xFFFF9C30),
        glow: const Color(0xFFFF5000),
      ),
      TimestampStyle.phone => PixelText(
        TimestampFormat.phone(now),
        dot: math.max(1, short / 220),
        color: Colors.white,
        shadow: Colors.black87,
      ),
      TimestampStyle.camcorderOsd => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final line in TimestampFormat.camcorder(now)) ...[
            PixelText(line, dot: math.max(1, short / 150), color: Colors.white, shadow: Colors.black),
            SizedBox(height: math.max(1, short / 150) * 3),
          ],
        ],
      ),
      TimestampStyle.none => const SizedBox.shrink(),
    };
  }
}

class _RecTimer extends StatefulWidget {
  const _RecTimer({required this.since, required this.color});

  final DateTime since;
  final Color color;

  @override
  State<_RecTimer> createState() => _RecTimerState();
}

class _RecTimerState extends State<_RecTimer> {
  late final Timer _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 500), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = DateTime.now().difference(widget.since);
    final blink = DateTime.now().millisecond < 500;
    final mm = d.inMinutes.toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: blink ? 1 : 0.2,
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 6),
        PixelText('REC $mm:$ss', dot: 1.8, color: Colors.white, shadow: Colors.black),
      ],
    );
  }
}

/// Instant shutter feedback: a white pop when the flash fires, otherwise a
/// fast blackout like a leaf shutter. Triggered by the shutter counter, i.e.
/// on the tap itself, not when the capture returns.
class _ShutterBlink extends ConsumerStatefulWidget {
  const _ShutterBlink();

  @override
  ConsumerState<_ShutterBlink> createState() => _ShutterBlinkState();
}

class _ShutterBlinkState extends ConsumerState<_ShutterBlink> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );
  bool _white = false;

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<CaptureState>(captureControllerProvider, (prev, next) {
      if (prev != null && next.shutterCount != prev.shutterCount) {
        _white = next.flashFired;
        _a.forward(from: 0);
      }
    });
    return AnimatedBuilder(
      animation: _a,
      builder: (context, _) {
        final v = _a.isAnimating ? (1 - (2 * _a.value - 1).abs()) : 0.0;
        if (v <= 0) return const SizedBox.shrink();
        return ColoredBox(color: (_white ? Colors.white : Colors.black).withValues(alpha: v * 0.9));
      },
    );
  }
}
