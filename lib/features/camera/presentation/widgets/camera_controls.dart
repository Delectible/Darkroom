import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/media_repository.dart';
import '../../../../core/device/physical_orientation.dart';
import '../../../../core/device/upright.dart';
import '../../../../core/processing/photo_pipeline.dart';
import '../../../../core/providers.dart';
import '../../../../core/theme/retro_theme.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../cameras/domain/camera_spec.dart';
import '../../application/camera_ui_state.dart';
import '../../../cameras/presentation/artwork/camera_artwork.dart';
import '../../application/capture_controller.dart';
import '../../application/zoom_controller.dart';

/// Big skeuomorphic shutter. Stills cameras take a photo; movie cameras
/// (camcorder, Super 8) start / stop recording.
class ShutterButton extends ConsumerStatefulWidget {
  const ShutterButton({super.key});

  @override
  ConsumerState<ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends ConsumerState<ShutterButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final palette = RetroPalette.of(context);
    final spec = ref.watch(activeSpecProvider);
    final capture = ref.watch(captureControllerProvider);
    final recording = capture.isRecording;
    final film = spec.mode == AppMode.film;
    final video = spec.recordsVideo;

    return Semantics(
      button: true,
      label: video ? (recording ? 'Stop recording' : 'Start recording') : 'Take photo',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) {
          setState(() => _down = false);
          unawaited(ref.read(captureControllerProvider.notifier).shutter());
        },
        child: AnimatedScale(
          scale: _down ? 0.92 : 1,
          duration: const Duration(milliseconds: 70),
          child: SizedBox(
            width: 82,
            height: 82,
            child: CustomPaint(
              painter: _ShutterPainter(
                film: film,
                ring: palette.metal,
                ringDark: palette.metalDark,
                cap: recording ? palette.danger : (video ? palette.danger.withValues(alpha: 0.85) : null),
                recording: recording,
                pressed: _down,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShutterPainter extends CustomPainter {
  _ShutterPainter({
    required this.film,
    required this.ring,
    required this.ringDark,
    required this.cap,
    required this.recording,
    required this.pressed,
  });

  final bool film;
  final Color ring;
  final Color ringDark;
  final Color? cap;
  final bool recording;
  final bool pressed;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(
      c.translate(0, 3),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    // Knurled metal collar.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = SweepGradient(
          colors: [ring, ringDark, ring, ringDark, ring],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    final knurl = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (var i = 0; i < 72; i++) {
      final a = i * 3.14159265 * 2 / 72;
      final d = Offset.fromDirection(a);
      canvas.drawLine(c + d * (r - 5), c + d * r, knurl);
    }
    // Button cap.
    final capR = r * 0.72;
    final base = cap ?? (film ? const Color(0xFF151210) : const Color(0xFFE8EBEE));
    canvas.drawCircle(
      c,
      capR,
      Paint()
        ..shader = RadialGradient(
          center: pressed ? Alignment.center : const Alignment(-0.35, -0.45),
          colors: [
            Color.lerp(base, Colors.white, film ? 0.25 : 0.6)!,
            base,
            Color.lerp(base, Colors.black, 0.35)!,
          ],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: c, radius: capR)),
    );
    if (recording) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: r * 0.55, height: r * 0.55),
          const Radius.circular(4),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
    }
  }

  @override
  bool shouldRepaint(_ShutterPainter old) =>
      old.film != film ||
      old.cap != cap ||
      old.recording != recording ||
      old.pressed != pressed ||
      old.ring != ring;
}

/// Round body button (flash, aspect, lens, settings).
class BodyButton extends StatelessWidget {
  const BodyButton({super.key, required this.onTap, required this.child, this.tooltip, this.enabled = true});

  final VoidCallback onTap;
  final Widget child;
  final String? tooltip;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = RetroPalette.of(context);
    final button = GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Container(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [palette.bodyHighlight, palette.body],
            ),
            border: Border.all(color: Colors.black.withValues(alpha: 0.35)),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 2, offset: Offset(0, 1))],
          ),
          child: IconTheme(
            data: IconThemeData(color: palette.text, size: 18),
            child: DefaultTextStyle(
              style: TextStyle(color: palette.text, fontSize: 12, fontWeight: FontWeight.w700),
              child: Center(widthFactor: 1, child: child),
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

class FlashButton extends ConsumerWidget {
  const FlashButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appModeProvider);
    final flash = ref.watch(activeFlashProvider);
    // Held sideways the content rotates in place: only the icon (it says
    // auto / on / off by itself) fits upright inside the fixed-size key.
    final sideways = uprightQuarterTurns(ref.watch(physicalOrientationProvider)).isOdd;
    final icon = AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
      child: Icon(key: ValueKey(flash), switch (flash) {
        FlashSetting.auto => Icons.flash_auto,
        FlashSetting.on => Icons.flash_on,
        FlashSetting.off => Icons.flash_off,
      }),
    );
    return SizedBox(
      width: 76,
      child: BodyButton(
        tooltip: 'Flash',
        onTap: () => unawaited(ref.read(flashProvider.notifier).cycle(mode)),
        child: Upright(
          child: sideways
              ? icon
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [icon, const SizedBox(width: 2), Text(flash.name.toUpperCase())],
                  ),
                ),
        ),
      ),
    );
  }
}

class AspectButton extends ConsumerWidget {
  const AspectButton({super.key, required this.onCycle});

  final VoidCallback onCycle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = ref.watch(activeSpecProvider);
    final local = ref.watch(activeCameraSettingsProvider);
    final aspect = spec.aspectLocked ? spec.defaultAspect : local.aspect;
    final sideways = uprightQuarterTurns(ref.watch(physicalOrientationProvider)).isOdd;
    return SizedBox(
      width: 64,
      child: BodyButton(
        tooltip: 'Aspect ratio',
        enabled: !spec.aspectLocked,
        onTap: onCycle,
        child: Upright(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The lock would make the rotated label too long for the key.
                if (spec.aspectLocked && !sideways) const Icon(Icons.lock, size: 13),
                Text(aspect.label),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the film / camera picker. Shows the loaded stock or body.
class StockButton extends ConsumerWidget {
  const StockButton({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = RetroPalette.of(context);
    final spec = ref.watch(activeSpecProvider);
    final film = spec.mode == AppMode.film;
    return Semantics(
      button: true,
      label: film ? 'Choose film' : 'Choose camera',
      child: SwipeToCycle(
        onTap: onOpen,
        child: Container(
          width: 64,
          height: 64,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: const Color(0xFF151515),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.metalDark),
          ),
          child: Upright(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(scale: Tween(begin: 0.8, end: 1.0).animate(a), child: c),
              ),
              // Flies into the picker's carousel (and back) on open/close.
              child: Hero(
                key: ValueKey(spec.id),
                tag: 'artwork-${spec.id}',
                child: CameraArtwork(spec: spec),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Name of the loaded stock/body under the viewfinder; tap to change it.
class StockLabel extends ConsumerWidget {
  const StockLabel({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = ref.watch(activeSpecProvider);
    return SwipeToCycle(
      onTap: onOpen,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        layoutBuilder: (current, previous) =>
            Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
            child: c,
          ),
        ),
        child: KeyedSubtree(
          key: ValueKey(spec.id),
          child: spec.isFilm ? _MemoHolder(spec: spec) : _LcdPanel(spec: spec),
        ),
      ),
    );
  }
}

/// Film bodies: the memo holder on the back door, with the end flap torn off
/// the film box slipped in so you remember what's loaded.
class _MemoHolder extends StatelessWidget {
  const _MemoHolder({required this.spec});

  final CameraSpec spec;

  @override
  Widget build(BuildContext context) {
    final p = RetroPalette.of(context);
    final paper = Color(spec.boxColor), ink = Color(spec.boxInk);
    final detail = spec.recordsVideo
        ? '${spec.badge} · 50 FT'
        : spec.isInstant
        ? '${spec.badge} · ${spec.roll.frames} SHOTS'
        : '${spec.badge} · ${spec.roll.frames} EXP';
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.metal, p.metalDark],
        ),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        decoration: BoxDecoration(
          color: paper,
          borderRadius: BorderRadius.circular(2),
          // The holder's lips overlap the card a little.
          border: Border.symmetric(
            horizontal: BorderSide(color: Colors.black.withValues(alpha: 0.25), width: 1.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              spec.name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ink,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                fontSize: 13,
                height: 1.1,
              ),
            ),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ink.withValues(alpha: 0.75),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Digital bodies: a little segment-LCD status panel, like the top plate of
/// a 2000s digicam: the model, battery, and how much card (or tape) is left.
class _LcdPanel extends ConsumerWidget {
  const _LcdPanel({required this.spec});

  final CameraSpec spec;

  static const _lcd = Color(0xFF9FAA8C);
  static const _ink = Color(0xFF1E2619);

  /// A typical file from this body, for the "shots left" estimate.
  static int _photoBytes(CameraSpec spec) {
    final e = spec.output.maxLongEdge;
    return math.max(20000, (e * e * 0.75 * 0.25).round());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RetroPalette.of(context);
    final items = ref.watch(sdCardItemsProvider).value ?? const <MediaItem>[];
    final String status;
    if (spec.storage == DigitalStorage.floppy) {
      // A 60-minute tape, minus what's been shot and not yet copied off.
      final usedS =
          items
              .where((m) => m.onSdCard && m.cameraId == spec.id)
              .fold<int>(0, (s, m) => s + (m.durationMs ?? 0)) ~/
          1000;
      final left = math.max(0, 60 * 60 - usedS);
      status = 'SP  TAPE ${left ~/ 60}MIN';
    } else {
      const capacity = 128 * 1024 * 1024;
      final used = items.where((m) => m.onSdCard).fold<int>(0, (s, m) => s + (m.bytes ?? 0));
      final left = math.max(0, capacity - used) ~/ _photoBytes(spec);
      status = 'SD 128MB  ${math.min(left, 9999)} LEFT';
    }
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        color: const Color(0xFF2A2D31),
        border: Border.all(color: p.metalDark),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFB0BA9C), _lcd, Color(0xFF8E997C)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: PixelText(spec.name.toUpperCase(), dot: 1.6, color: _ink),
                  ),
                ),
                const SizedBox(width: 6),
                const CustomPaint(size: Size(16, 8), painter: _LcdBattery()),
              ],
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: PixelText(status, dot: 1.2, color: _ink.withValues(alpha: 0.8)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LcdBattery extends CustomPainter {
  const _LcdBattery();

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()..color = _LcdPanel._ink;
    final w = size.width - 2, h = size.height;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, 1), ink);
    canvas.drawRect(Rect.fromLTWH(0, h - 1, w, 1), ink);
    canvas.drawRect(Rect.fromLTWH(0, 0, 1, h), ink);
    canvas.drawRect(Rect.fromLTWH(w - 1, 0, 1, h), ink);
    canvas.drawRect(Rect.fromLTWH(w, h * 0.3, 2, h * 0.4), ink);
    for (var i = 0; i < 3; i++) {
      canvas.drawRect(Rect.fromLTWH(2 + i * (w - 3) / 3, 2, (w - 3) / 3 - 1, h - 4), ink);
    }
  }

  @override
  bool shouldRepaint(_LcdBattery old) => false;
}

/// Small centred caret above the controls: tap (or swipe up anywhere) to
/// open the film / camera picker.
class PickerCaret extends StatelessWidget {
  const PickerCaret({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open picker',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Icon(Icons.keyboard_arrow_up, color: RetroPalette.of(context).textMuted, size: 22),
        ),
      ),
    );
  }
}

/// Tap opens the picker; a sideways swipe steps to the next / previous
/// stock or body without opening it.
class SwipeToCycle extends ConsumerStatefulWidget {
  const SwipeToCycle({super.key, required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  ConsumerState<SwipeToCycle> createState() => _SwipeToCycleState();
}

class _SwipeToCycleState extends ConsumerState<SwipeToCycle> {
  double _dx = 0;

  void _end(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final dx = _dx;
    _dx = 0;
    if (ref.read(captureControllerProvider).isRecording) return;
    if (dx.abs() < 24 && v.abs() < 300) return;
    final step = (v.abs() >= 300 ? v : dx) < 0 ? 1 : -1;
    unawaited(HapticFeedback.selectionClick());
    unawaited(ref.read(selectedCameraProvider.notifier).step(ref.read(appModeProvider), step));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onHorizontalDragStart: (_) => _dx = 0,
      onHorizontalDragUpdate: (d) => _dx += d.primaryDelta ?? 0,
      onHorizontalDragEnd: _end,
      child: widget.child,
    );
  }
}

/// Opens the Corkboard (film) or the Win98 explorer (digital). Shows how
/// many prints are in the developer / files are on the card.
class GalleryButton extends ConsumerWidget {
  const GalleryButton({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = RetroPalette.of(context);
    final mode = ref.watch(appModeProvider);
    final film = mode == AppMode.film;
    final all =
        (film ? ref.watch(filmItemsProvider) : ref.watch(sdCardItemsProvider)).value ?? const <MediaItem>[];
    final items = film ? all : all.where((m) => m.onSdCard).toList();
    final now = DateTime.now();
    final badge = film
        ? items.where((m) => m.status != MediaStatus.failed && !m.isDevelopedAt(now)).length
        : items.where((m) => m.status != MediaStatus.failed).length;
    final newPrints = film ? items.where((m) => m.isDevelopedAt(now) && !m.seen).length : 0;
    final latest = items.where((m) => m.isReady && m.thumbPath != null && (!film || m.isDevelopedAt(now)));
    final thumb = latest.isEmpty ? null : latest.first.thumbPath;

    return Semantics(
      button: true,
      label: film ? 'Open corkboard' : 'Open SD card',
      child: GestureDetector(
        onTap: onOpen,
        child: SizedBox(
          width: 64,
          height: 64,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: film ? const Color(0xFFB98A5A) : const Color(0xFF1F3C88),
                    borderRadius: BorderRadius.circular(film ? 4 : 2),
                    border: Border.all(color: Colors.black54),
                    boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2))],
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Upright(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: thumb != null
                          ? Image.file(
                              File(thumb),
                              key: ValueKey(thumb),
                              fit: BoxFit.cover,
                              cacheWidth: 160,
                              gaplessPlayback: true,
                              errorBuilder: (_, _, _) => const SizedBox.shrink(),
                            )
                          : Icon(film ? Icons.push_pin : Icons.sd_card, color: Colors.white70),
                    ),
                  ),
                ),
              ),
              if (badge > 0 || newPrints > 0)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: film && badge > 0 ? const Color(0xFF8B0000) : palette.accent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1.2),
                    ),
                    child: Text(
                      film && badge > 0 ? '$badge DEV' : (film ? '$newPrints NEW' : '$badge'),
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// W | T zoom rocker on every digital body: hold to drive the zoom motor.
class ZoomRocker extends ConsumerWidget {
  const ZoomRocker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = RetroPalette.of(context);
    final zoom = ref.watch(zoomProvider);
    final enabled = zoom.canZoom;
    Widget half(String label, int dir, BorderRadius radius) {
      final pressed = zoom.direction == dir;
      final atLimit = dir < 0 ? zoom.level <= zoom.min : zoom.level >= zoom.max;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) {
            if (!enabled) return;
            unawaited(HapticFeedback.selectionClick());
            ref.read(zoomProvider.notifier).start(dir);
          },
          onTapUp: (_) => ref.read(zoomProvider.notifier).stop(),
          onTapCancel: () => ref.read(zoomProvider.notifier).stop(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: pressed ? [palette.bodyShadow, palette.body] : [palette.bodyHighlight, palette.body],
              ),
            ),
            alignment: Alignment.center,
            child: Upright(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: palette.text.withValues(alpha: enabled && !atLimit ? 1 : 0.35),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: 'Zoom',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 30,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.black.withValues(alpha: 0.4)),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 2, offset: Offset(0, 1))],
            ),
            child: Row(
              children: [
                half('W', -1, const BorderRadius.horizontal(left: Radius.circular(15))),
                Container(width: 1, color: Colors.black.withValues(alpha: 0.35)),
                half('T', 1, const BorderRadius.horizontal(right: Radius.circular(15))),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'ZOOM',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Front / back camera: a small knurled dial with a lens in it. Tapping it
/// turns the dial half a turn, like flipping the lens around.
class LensFlipButton extends ConsumerStatefulWidget {
  const LensFlipButton({super.key, required this.enabled});

  final bool enabled;

  @override
  ConsumerState<LensFlipButton> createState() => _LensFlipButtonState();
}

class _LensFlipButtonState extends ConsumerState<LensFlipButton> {
  double _turns = 0;
  bool _down = false;

  void _flip() {
    unawaited(HapticFeedback.mediumImpact());
    setState(() => _turns += 0.5);
    ref.read(lensProvider.notifier).toggle();
  }

  @override
  Widget build(BuildContext context) {
    final palette = RetroPalette.of(context);
    final front = ref.watch(lensProvider) == CameraLensDirection.front;
    return Semantics(
      button: true,
      label: front ? 'Use back camera' : 'Use front camera',
      child: GestureDetector(
        onTapDown: widget.enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: widget.enabled
            ? (_) {
                setState(() => _down = false);
                _flip();
              }
            : null,
        child: Opacity(
          opacity: widget.enabled ? 1 : 0.45,
          child: AnimatedScale(
            scale: _down ? 0.92 : 1,
            duration: const Duration(milliseconds: 70),
            child: AnimatedRotation(
              turns: _turns,
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutBack,
              child: SizedBox(
                width: 40,
                height: 40,
                child: CustomPaint(
                  painter: _LensFlipPainter(
                    ring: palette.metal,
                    ringDark: palette.metalDark,
                    front: front,
                    accent: palette.accent,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LensFlipPainter extends CustomPainter {
  _LensFlipPainter({required this.ring, required this.ringDark, required this.front, required this.accent});

  final Color ring;
  final Color ringDark;
  final bool front;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(
      c.translate(0, 2),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // Knurled dial.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = SweepGradient(
          colors: [ring, ringDark, ring, ringDark, ring],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    final knurl = Paint()
      ..color = Colors.black.withValues(alpha: 0.22)
      ..strokeWidth = 1;
    for (var i = 0; i < 40; i++) {
      final d = Offset.fromDirection(i * math.pi * 2 / 40);
      canvas.drawLine(c + d * (r - 3.5), c + d * r, knurl);
    }
    // Two curved arrows chasing each other round the lens.
    final arrow = Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final ar = r * 0.66;
    for (final start in [-math.pi * 0.9, math.pi * 0.1]) {
      const sweep = math.pi * 0.62;
      canvas.drawArc(Rect.fromCircle(center: c, radius: ar), start, sweep, false, arrow);
      final tip = c + Offset.fromDirection(start + sweep) * ar;
      final dir = start + sweep + math.pi / 2;
      final head = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - math.cos(dir - 0.5) * 4, tip.dy - math.sin(dir - 0.5) * 4)
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - math.cos(dir + 0.5) * 4, tip.dy - math.sin(dir + 0.5) * 4);
      canvas.drawPath(head, arrow);
    }
    // The lens: dark coated glass with a highlight; a tiny lamp shows which
    // way it faces.
    final lr = r * 0.36;
    canvas.drawCircle(c, lr + 1.5, Paint()..color = const Color(0xFF1A1A1A));
    canvas.drawCircle(
      c,
      lr,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.4),
          colors: [Color(0xFF3B4A6B), Color(0xFF0B0F18)],
        ).createShader(Rect.fromCircle(center: c, radius: lr)),
    );
    canvas.drawCircle(c + Offset(-lr * 0.35, -lr * 0.35), lr * 0.22, Paint()..color = Colors.white70);
    if (front) canvas.drawCircle(c + Offset(r * 0.62, -r * 0.62), 2.6, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_LensFlipPainter old) =>
      old.front != front || old.ring != ring || old.ringDark != ringDark || old.accent != accent;
}
