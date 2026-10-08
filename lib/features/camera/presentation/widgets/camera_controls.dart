import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/media_repository.dart';
import '../../../../core/device/physical_orientation.dart';
import '../../../../core/device/upright.dart';
import '../../../../core/processing/photo_pipeline.dart';
import '../../../../core/providers.dart';
import '../../../../core/theme/darkroom_mark.dart';
import '../../../../core/theme/retro_theme.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/utils/pixel_font.dart';
import '../../../cameras/domain/camera_catalog.dart';
import '../../../cameras/domain/camera_spec.dart';
import '../../application/camera_ui_state.dart';
import '../../../cameras/presentation/artwork/camera_artwork.dart';
import '../../application/capture_controller.dart';
import '../../application/zoom_controller.dart';
import '../../../../core/device/battery.dart';
import '../../../../core/device/haptics.dart';

export 'shutters.dart' show ShutterButton, pressShutter;

/// Big skeuomorphic shutter. Stills cameras take a photo; movie cameras
/// (camcorder, Super 8) start / stop recording.
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
            // A recessed tray: light catches its lower lip, shade under the top.
            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 5, offset: Offset(1.5, 2.5))],
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0B0B0B), Color(0xFF1C1C1C)],
            ),
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
        // The digital bodies' LCD is one screen that stays put: only what's
        // on it changes. Film swaps the box end in the memo holder.
        child: KeyedSubtree(
          key: ValueKey(spec.isFilm ? spec.id : 'lcd'),
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

  static const _nameDot = 1.6, _statusDot = 1.2;

  /// One size for every body (fits the longest name and status), so the
  /// panel stays put and only what's on it changes.
  static final Size _screen = () {
    var name = 0.0;
    for (final s in CameraCatalog.forMode(AppMode.digital)) {
      name = math.max(name, PixelFont.measureDots(s.name.toUpperCase()) * _nameDot + _nameDot);
    }
    final status = [
      'SP  TAPE 60MIN',
      'SD 128MB  9999 LEFT',
    ].map((t) => PixelFont.measureDots(t) * _statusDot + _statusDot).reduce(math.max);
    return Size(math.max(name + 6 + 16, status), (PixelFont.glyphHeight + 1) * (_nameDot + _statusDot) + 3);
  }();

  /// A typical file from this body, for the "shots left" estimate.
  static int _photoBytes(CameraSpec spec) {
    final e = spec.output.maxLongEdge;
    return math.max(20000, (e * e * 0.75 * 0.25).round());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RetroPalette.of(context);
    final items = ref.watch(sdCardItemsProvider).value ?? const <MediaItem>[];
    final bars = Battery.bars(ref.watch(batteryLevelProvider).value);
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
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox.fromSize(
            size: _screen,
            // Switching body: the old readout goes out, then the new one comes
            // up, like an LCD changing mode (the panel itself stays put).
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: const Interval(0.5, 1),
              switchOutCurve: const Interval(0.5, 1),
              layoutBuilder: (current, previous) =>
                  Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
              child: Column(
                key: ValueKey(spec.id),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: PixelText(spec.name.toUpperCase(), dot: _nameDot, color: _ink),
                        ),
                      ),
                      CustomPaint(size: const Size(16, 8), painter: _LcdBattery(bars)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  PixelText(status, dot: _statusDot, color: _ink.withValues(alpha: 0.8)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The panel's battery: the phone's own charge, in three segments.
class _LcdBattery extends CustomPainter {
  const _LcdBattery(this.bars);

  final int bars;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()..color = _LcdPanel._ink;
    final w = size.width - 2, h = size.height;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, 1), ink);
    canvas.drawRect(Rect.fromLTWH(0, h - 1, w, 1), ink);
    canvas.drawRect(Rect.fromLTWH(0, 0, 1, h), ink);
    canvas.drawRect(Rect.fromLTWH(w - 1, 0, 1, h), ink);
    canvas.drawRect(Rect.fromLTWH(w, h * 0.3, 2, h * 0.4), ink);
    for (var i = 0; i < bars; i++) {
      canvas.drawRect(Rect.fromLTWH(2 + i * (w - 3) / 3, 2, (w - 3) / 3 - 1, h - 4), ink);
    }
  }

  @override
  bool shouldRepaint(_LcdBattery old) => old.bars != bars;
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
    unawaited(Haptics.selectionClick());
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
                child: film ? _PrintThumb(thumb: thumb) : _LcdThumb(thumb: thumb),
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

Widget _thumbImage(String? thumb, Widget empty) => AnimatedSwitcher(
  duration: const Duration(milliseconds: 300),
  child: thumb != null
      ? Image.file(
          File(thumb),
          key: ValueKey(thumb),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          cacheWidth: 160,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => empty,
        )
      : empty,
);

/// Film: the latest print as a little photograph lying on the body, tipped
/// slightly, with another print peeking out underneath.
class _PrintThumb extends StatelessWidget {
  const _PrintThumb({required this.thumb});

  final String? thumb;

  static const _paper = Color(0xFFF3EFE6);

  @override
  Widget build(BuildContext context) {
    Widget print(Widget picture) => Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(1.5),
        border: Border.all(color: const Color(0x22000000), width: 0.6),
        boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 4, offset: Offset(1, 2))],
      ),
      child: ClipRect(child: picture),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        // The one underneath.
        Transform.rotate(
          angle: 0.10,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: print(const ColoredBox(color: Color(0xFF6E6658))),
          ),
        ),
        Transform.rotate(
          angle: -0.06,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: print(
              Upright(
                child: _thumbImage(
                  thumb,
                  const ColoredBox(
                    color: Color(0xFFD9D2C3),
                    child: Center(child: Icon(Icons.push_pin, size: 18, color: Color(0xFF9B8F7A))),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Digital: the camera's own little review screen: a bezel, an LCD with a
/// faint pixel grid and glass sheen, and a play mark in the corner.
class _LcdThumb extends StatelessWidget {
  const _LcdThumb({required this.thumb});

  final String? thumb;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A3D42), Color(0xFF16171A)],
        ),
        border: Border.all(color: Colors.black87),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 3, offset: Offset(0, 1.5))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Upright(
              child: _thumbImage(
                thumb,
                const ColoredBox(
                  color: Color(0xFF14306E),
                  child: Center(
                    child: Text(
                      'SD\nEMPTY',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFBFD3FF),
                        fontSize: 8,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const CustomPaint(painter: _LcdGrid()),
            // Glass sheen across the top.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment(0.2, 0.3),
                  colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)],
                ),
              ),
            ),
            const Positioned(
              left: 3,
              top: 2,
              child: Text('▶', style: TextStyle(color: Color(0xE6FFFFFF), fontSize: 7)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LcdGrid extends CustomPainter {
  const _LcdGrid();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0x22000000);
    for (var y = 0.0; y < size.height; y += 2) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 0.7), p);
    }
  }

  @override
  bool shouldRepaint(_LcdGrid old) => false;
}

/// W | T zoom rocker on every digital body: hold to drive the zoom motor,
/// and slide across to the other half to reverse it. The rocker claims the
/// touch the moment it lands, so a slide never tosses the camera body.
class ZoomRocker extends ConsumerStatefulWidget {
  const ZoomRocker({super.key});

  static const _width = 100.0, _height = 40.0;

  @override
  ConsumerState<ZoomRocker> createState() => _ZoomRockerState();
}

class _ZoomRockerState extends ConsumerState<ZoomRocker> {
  static const _width = ZoomRocker._width, _height = ZoomRocker._height;

  /// The half the finger is on (-1 W, 1 T), for the whole touch: the rocker
  /// rebuilds on every zoom step, so this can't live in build().
  int? _finger;

  @override
  Widget build(BuildContext context) {
    final palette = RetroPalette.of(context);
    final zoom = ref.watch(zoomProvider);
    final enabled = zoom.canZoom;
    final notifier = ref.read(zoomProvider.notifier);

    // Acts only when the finger lands or crosses to the other half; holding
    // still at the end of travel does nothing more.
    void drive(Offset local) {
      if (!enabled) return;
      final dir = local.dx < _width / 2 ? -1 : 1;
      if (_finger == dir) return;
      _finger = dir;
      final z = ref.read(zoomProvider);
      final atEnd = dir > 0 ? z.level >= z.max : z.level <= z.min;
      if (!atEnd) unawaited(Haptics.selectionClick());
      notifier.start(dir);
    }

    Widget half(String label, int dir, BorderRadius radius) {
      final pressed = zoom.direction == dir;
      final atLimit = dir < 0 ? zoom.level <= zoom.min : zoom.level >= zoom.max;
      return Expanded(
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
                fontSize: 16,
                fontWeight: FontWeight.w900,
                // Dimmed only at the end of travel: while the camera reopens
                // after a body switch zoom reads as unavailable for a moment,
                // and dimming then made the W / T flicker.
                color: palette.text.withValues(alpha: enabled && atLimit ? 0.35 : 1),
              ),
            ),
          ),
        ),
      );
    }

    final rocker = RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        _ClaimingPan: GestureRecognizerFactoryWithHandlers<_ClaimingPan>(_ClaimingPan.new, (r) {
          r.onDown = (d) => drive(d.localPosition);
          r.onUpdate = (d) => drive(d.localPosition);
          r.onEnd = (_) {
            _finger = null;
            notifier.stop();
          };
          r.onCancel = () {
            _finger = null;
            notifier.stop();
          };
        }),
      },
      child: Container(
        width: _width,
        height: _height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_height / 2),
          border: Border.all(color: Colors.black.withValues(alpha: 0.4)),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 2, offset: Offset(0, 1))],
        ),
        child: Row(
          children: [
            half('W', -1, const BorderRadius.horizontal(left: Radius.circular(_height / 2))),
            Container(width: 1, color: Colors.black.withValues(alpha: 0.35)),
            half('T', 1, const BorderRadius.horizontal(right: Radius.circular(_height / 2))),
          ],
        ),
      ),
    );

    return Semantics(
      label: 'Zoom',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          rocker,
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
    unawaited(Haptics.mediumImpact());
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
    // The cap: a domed metal button with the maker's rabbit pressed into it;
    // a tiny lamp shows when the front camera is on.
    final lr = r * 0.4;
    canvas.drawCircle(c, lr + 1.2, Paint()..color = Colors.black.withValues(alpha: 0.35));
    canvas.drawCircle(
      c,
      lr,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          colors: [Color.lerp(ring, Colors.white, 0.35)!, ringDark],
        ).createShader(Rect.fromCircle(center: c, radius: lr)),
    );
    final gh = lr * 1.25;
    final gw = gh * DarkroomMark.aspect;
    for (final (o, color) in [
      (const Offset(0.6, 0.7), Colors.white.withValues(alpha: 0.45)),
      (Offset.zero, Colors.black.withValues(alpha: 0.42)),
    ]) {
      canvas.save();
      canvas.translate(c.dx - gw / 2 + o.dx, c.dy - gh / 2 + o.dy);
      DarkroomMarkPainter(color: color).paint(canvas, Size(gw, gh));
      canvas.restore();
    }
    if (front) canvas.drawCircle(c + Offset(r * 0.62, -r * 0.62), 2.6, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_LensFlipPainter old) =>
      old.front != front || old.ring != ring || old.ringDark != ringDark || old.accent != accent;
}

/// A pan recognizer that wins the gesture arena as soon as the finger lands,
/// so the camera body's sideways toss never sees a rocker slide.
class _ClaimingPan extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}
