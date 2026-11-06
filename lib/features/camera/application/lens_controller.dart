import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cameras/domain/camera_spec.dart';
import 'camera_ui_state.dart';

/// The lens on the camera in hand (film: the lens ring's tray). Kept per
/// camera while the app runs; a camera without that lens falls back to its
/// own (standard).
final filmLensProvider = NotifierProvider<FilmLensController, LensKind>(FilmLensController.new);

class FilmLensController extends Notifier<LensKind> {
  final Map<String, LensKind> _byCamera = {};

  @override
  LensKind build() {
    ref.listen(activeSpecProvider, (_, spec) => state = _for(spec));
    // (no ultra-wide after all: the wide adapter comes off)
    ref.listen<bool?>(ultraWideProvider, (_, has) {
      if (has != true && state == LensKind.wide) state = LensKind.standard;
    });
    return _for(ref.read(activeSpecProvider));
  }

  LensKind _for(CameraSpec spec) {
    final l = _byCamera[spec.id];
    return l != null && lensesFor(spec, ref.read(ultraWideProvider)).contains(l) ? l : spec.lenses.first;
  }

  void set(LensKind lens) {
    final spec = ref.read(activeSpecProvider);
    if (!lensesFor(spec, ref.read(ultraWideProvider)).contains(lens)) return;
    _byCamera[spec.id] = lens;
    state = lens;
  }
}

/// The lenses [spec] offers on this phone: the wide adapter only where it
/// has an ultra-wide camera to open (it's the one way to reach it); the
/// fish-eye everywhere (with the main camera where there's no ultra-wide).
List<LensKind> lensesFor(CameraSpec spec, bool? ultraWide) => ultraWide == true
    ? spec.lenses
    : [
        for (final l in spec.lenses)
          if (l != LensKind.wide) l,
      ];

/// Whether the phone's back has an ultra-wide camera (null: not known yet;
/// Android: the back camera zooms below 1x; iPhone: one is listed).
final ultraWideProvider = NotifierProvider<UltraWide, bool?>(UltraWide.new);

class UltraWide extends Notifier<bool?> {
  @override
  bool? build() => null;

  void set(bool has) {
    if (state != has) state = has;
  }
}

/// A lens chosen from the tray goes on with the viewfinder shut over the
/// change (and the camera switching to its ultra-wide and back), set by the
/// camera screen; without one, straight away.
class LensChange {
  LensChange._();

  static void Function(LensKind lens)? handler;

  static void request(WidgetRef ref, LensKind lens) {
    final h = handler;
    if (h != null) {
      h(lens);
    } else {
      ref.read(filmLensProvider.notifier).set(lens);
    }
  }
}
