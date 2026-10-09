import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/retro_theme.dart';
import '../../cameras/domain/camera_spec.dart';
import '../application/camera_session_controller.dart';
import '../application/camera_ui_state.dart';
import '../application/capture_controller.dart';
import '../../settings/application/settings_controllers.dart';
import 'photo_body.dart';
import 'viewport.dart';
import 'whole_body.dart';
import 'widgets/camera_controls.dart';

/// The camera's face drawn from the whole-body renders: the resting body
/// fitted to the screen (scaled to its width, a band taken out of the middle
/// of the viewfinder on less tall phones), the live viewfinder in its frame,
/// and every control at the place it was rendered. The controls are the
/// usual widgets; their moving parts draw the body's layers (see
/// [BodyArt.fromWhole]). Laid out in design dp, scaled to the screen.
class WholeFace extends ConsumerWidget {
  const WholeFace({
    super.key,
    required this.art,
    required this.body,
    required this.mode,
    required this.onSettings,
    required this.onOpenSelector,
    required this.onOpenGallery,
    this.processing,
  });

  final WholeArt art;
  final WholeBody body;
  final AppMode mode;
  final VoidCallback onSettings;
  final VoidCallback onOpenSelector;
  final VoidCallback onOpenGallery;

  /// The spinner shown while shots are processing (see [ProcessingSpinner]).
  final Widget? processing;

  /// The shutter widget's hub (where the render's release sits) relative to
  /// its centre, per kind (see ShutterButton: 104 x 86, face box and hub).
  static Offset shutterHub(CameraSpec spec) {
    if (spec.mode == AppMode.film && !spec.recordsVideo) return const Offset(10.8, 1.7);
    return Offset.zero;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = ref.watch(activeSpecProvider);
    final session = ref.watch(cameraSessionProvider);
    final recording = ref.watch(captureControllerProvider).isRecording;
    final lay = body.layout;
    final film = mode == AppMode.film;
    return LayoutBuilder(
      builder: (context, c) {
        final s = c.maxWidth / art.design.width;
        final design = Size(art.design.width, c.maxHeight / s);
        final fit = DesignFit(art, design);
        Widget at(Offset centre, Size size, Widget child) => Positioned(
          left: centre.dx - size.width / 2,
          top: fit.y(centre.dy) - size.height / 2,
          width: size.width,
          height: size.height,
          child: child,
        );
        Offset part(String name) => lay.parts[name]!;
        final screen = fit.rect(lay.screen);
        // the memo holder's opening / the LCD's window
        final label = fit.rect(lay.label).deflate(film ? 0 : 8);
        final card = film
            ? Rect.fromLTRB(label.left + 8, label.top + 7, label.right - 8, label.bottom - 7)
            : label;
        final shutterAt = part('shutter') - shutterHub(spec);
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: design.width,
            maxWidth: design.width,
            minHeight: design.height,
            maxHeight: design.height,
            child: Transform.scale(
              scale: s,
              alignment: Alignment.topLeft,
              child: WholeScale(
                scale: s,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: _Rest(art: art, body: body, fit: fit, scale: s),
                    ),
                    // The live picture in the rendered frame's screen.
                    Positioned.fromRect(
                      rect: screen,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(film ? 6 : 3),
                        child: const CameraViewport(),
                      ),
                    ),
                    at(
                      Offset(art.design.width / 2, (lay.frame.bottom + lay.label.top) / 2),
                      const Size(80, 16),
                      FittedBox(child: PickerCaret(onOpen: onOpenSelector)),
                    ),
                    // Top controls.
                    at(part(film ? 'flash' : 'pill'), const Size(76, 36), const FlashButton()),
                    at(
                      part(film ? 'aspect' : 'pillwide'),
                      const Size(64, 36),
                      AspectButton(
                        onCycle: () =>
                            unawaited(ref.read(cameraSettingsProvider.notifier).cycleAspect(spec.id)),
                      ),
                    ),
                    if (session.hasFrontCamera)
                      at(part('lens'), const Size(40, 40), LensFlipButton(enabled: !recording)),
                    at(
                      part(film ? 'menu' : 'pillsmall'),
                      const Size(44, 36),
                      _Settings(mode: mode, onTap: onSettings),
                    ),
                    if (processing != null)
                      at(Offset(part('lens').dx - 40, part('lens').dy), const Size(24, 24), processing!),
                    // Under the viewfinder: the box end in the memo holder /
                    // the LCD, and the zoom rocker.
                    Positioned.fromRect(
                      rect: card,
                      child: StockLabel(onOpen: onOpenSelector),
                    ),
                    // (the widget is the rocker with its ZOOM caption under it)
                    if (!film)
                      at(part('rocker') + const Offset(0, 10), const Size(100, 60), const ZoomRocker()),
                    // Bottom row.
                    at(
                      part(film ? 'print' : 'review'),
                      const Size(64, 64),
                      GalleryButton(onOpen: onOpenGallery),
                    ),
                    at(shutterAt, const Size(104, 86), const ShutterButton()),
                    at(part('tray'), const Size(64, 64), StockButton(onOpen: onOpenSelector)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Rest extends StatelessWidget {
  const _Rest({required this.art, required this.body, required this.fit, required this.scale});

  final WholeArt art;
  final WholeBody body;
  final DesignFit fit;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ArtImages(
      providers: [body.rest.image(scale * dpr)],
      painter: (imgs) => RestPainter(imgs[0], body.rest.rect, fit),
    );
  }
}

/// Film: the menu button; digital: the small rubber key with the tune icon.
class _Settings extends ConsumerWidget {
  const _Settings({required this.mode, required this.onTap});

  final AppMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final art = ref.watch(photoBodyProvider(mode));
    if (art == null) return const SizedBox.shrink();
    return mode == AppMode.film
        ? PhotoKey(part: art.part(AppMode.film, 'menu')!, onTap: onTap)
        : PhotoKey(
            part: art.part(AppMode.digital, 'pillsmall')!,
            onTap: onTap,
            child: const Icon(Icons.tune, size: 17, color: Color(0xFFE4E6E9)),
          );
  }
}

/// A small spinner while shots are being processed.
class ProcessingSpinner extends ConsumerWidget {
  const ProcessingSpinner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final processing = ref.watch(captureProcessorProvider).pending;
    return ValueListenableBuilder<int>(
      valueListenable: processing,
      builder: (context, n, _) => n == 0
          ? const SizedBox.shrink()
          : Center(
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.6, color: RetroPalette.of(context).accent),
              ),
            ),
    );
  }
}
