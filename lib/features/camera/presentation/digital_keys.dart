import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/device/haptics.dart';
import '../../../core/theme/retro_theme.dart';
import '../../../core/theme/surfaces.dart';
import '../../cameras/domain/camera_spec.dart';
import '../application/capture_controller.dart';
import '../application/lens_controller.dart';
import 'camera_specials.dart';
import 'film_dials.dart' show LensCap;
import 'viewfinder_shut.dart';
import 'viewport.dart' show CameraNote;

/// The digital viewfinder's two keys, drawn like the rest of its OSD: the
/// conversion lens (under the flash readout, top left; it opens the same
/// tray of lens caps as film) and the special (FX colour modes on the
/// stills cameras, FADE on the camcorders; top right, out of the way of
/// the REC timer while recording).
class DigitalKeys extends ConsumerStatefulWidget {
  const DigitalKeys({super.key, required this.spec});

  final CameraSpec spec;

  @override
  ConsumerState<DigitalKeys> createState() => _DigitalKeysState();
}

class _DigitalKeysState extends ConsumerState<DigitalKeys> {
  bool _tray = false;

  @override
  Widget build(BuildContext context) {
    final palette = RetroPalette.of(context);
    final lens = ref.watch(filmLensProvider);
    final lenses = lensesFor(widget.spec, ref.watch(ultraWideProvider));
    final chip = CameraSpecials.chip(ref, widget.spec);
    final recording = ref.watch(captureControllerProvider.select((s) => s.isRecording));
    return AnimatedBuilder(
      // (gone while the screen sleeps)
      animation: ViewfinderShutter.shut,
      builder: (context, child) =>
          Opacity(opacity: (1 - ViewfinderShutter.shut.value).clamp(0.0, 1.0), child: child),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.spec.lenses.length > 1)
            Positioned(
              left: 6,
              top: 26,
              child: _Key(
                text: lens.mark,
                on: lens != LensKind.standard || _tray,
                ink: palette.screenInk,
                label: '${lens.label} lens',
                onTap: () {
                  unawaited(Haptics.selectionClick());
                  setState(() => _tray = !_tray);
                },
              ),
            ),
          if (widget.spec.special != null && !recording)
            Positioned(
              right: 6,
              top: 4,
              child: _Key(
                text: chip.text,
                on: chip.on,
                ink: palette.screenInk,
                label: widget.spec.special!.label,
                onTap: () => CameraSpecials.press(ref, widget.spec),
              ),
            ),
          if (lenses.length > 1)
            Positioned(
              left: 0,
              right: 0,
              top: 58,
              height: 74,
              child: IgnorePointer(
                ignoring: !_tray,
                child: AnimatedSlide(
                  offset: _tray ? Offset.zero : const Offset(0, -0.12),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: _tray ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          for (final l in lenses)
                            LensCap(
                              lens: l,
                              on: l == lens,
                              onTap: () {
                                unawaited(Haptics.lightImpact());
                                if (l != lens) LensChange.request(ref, l);
                                CameraNote.show(l.label);
                                Future<void>.delayed(const Duration(milliseconds: 180), () {
                                  if (mounted) setState(() => _tray = false);
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One OSD key: its word in the pixel font in a thin box, filled when on.
class _Key extends StatelessWidget {
  const _Key({
    required this.text,
    required this.on,
    required this.ink,
    required this.label,
    required this.onTap,
  });

  final String text;
  final bool on;
  final Color ink;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: on,
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // (a finger-sized target round a small key)
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: on ? ink : ink.withValues(alpha: 0),
            border: Border.all(color: ink.withValues(alpha: on ? 1 : 0.7), width: 1.2),
          ),
          child: PixelText(text, dot: 1.6, color: on ? const Color(0xFF0A0A0A) : ink),
        ),
      ),
    ),
  );
}
