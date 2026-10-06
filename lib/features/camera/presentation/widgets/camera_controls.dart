import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/media_repository.dart';
import '../../../../core/device/upright.dart';
import '../../../../core/processing/photo_pipeline.dart';
import '../../../../core/providers.dart';
import '../../../../core/theme/retro_theme.dart';
import '../../../cameras/domain/camera_spec.dart';
import '../../application/camera_ui_state.dart';
import '../../../cameras/presentation/artwork/camera_artwork.dart';
import '../../application/capture_controller.dart';

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

/// The FILM | DIGITAL slide switch that re-skins the whole app.
class ModeSwitch extends ConsumerWidget {
  const ModeSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = RetroPalette.of(context);
    final mode = ref.watch(appModeProvider);
    final recording = ref.watch(captureControllerProvider).isRecording;
    final digital = mode == AppMode.digital;
    return Semantics(
      toggled: digital,
      label: 'Film or digital mode',
      child: GestureDetector(
        onTap: recording
            ? null
            : () {
                unawaited(HapticFeedback.mediumImpact());
                unawaited(ref.read(appModeProvider.notifier).toggle());
              },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 30,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [palette.bodyShadow, palette.bodyHighlight],
                ),
                border: Border.all(color: Colors.black.withValues(alpha: 0.4)),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                alignment: digital ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 30,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: LinearGradient(colors: [palette.metal, palette.metalDark]),
                    boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 3, offset: Offset(0, 1))],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(
                      4,
                      (_) => Container(width: 1.5, height: 14, color: Colors.black.withValues(alpha: 0.25)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'FILM',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: digital ? palette.textMuted : palette.accent,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'DIGI',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: digital ? palette.accent : palette.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
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
    return BodyButton(
      tooltip: 'Flash',
      onTap: () => unawaited(ref.read(flashProvider.notifier).cycle(mode)),
      child: Upright(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: Icon(key: ValueKey(flash), switch (flash) {
                FlashSetting.auto => Icons.flash_auto,
                FlashSetting.on => Icons.flash_on,
                FlashSetting.off => Icons.flash_off,
              }),
            ),
            const SizedBox(width: 2),
            Text(flash.name.toUpperCase()),
          ],
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
    return BodyButton(
      tooltip: 'Aspect ratio',
      enabled: !spec.aspectLocked,
      onTap: onCycle,
      child: Upright(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [if (spec.aspectLocked) const Icon(Icons.lock, size: 13), Text(aspect.label)],
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
    final palette = RetroPalette.of(context);
    final spec = ref.watch(activeSpecProvider);
    return SwipeToCycle(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            spec.name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.text,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              fontSize: 13,
            ),
          ),
          Text(
            spec.recordsVideo ? '${spec.subtitle} · VIDEO' : spec.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
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
