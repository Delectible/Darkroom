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
    return _for(ref.read(activeSpecProvider));
  }

  LensKind _for(CameraSpec spec) {
    final l = _byCamera[spec.id];
    return l != null && spec.lenses.contains(l) ? l : spec.lenses.first;
  }

  void set(LensKind lens) {
    final spec = ref.read(activeSpecProvider);
    if (!spec.lenses.contains(lens)) return;
    _byCamera[spec.id] = lens;
    state = lens;
  }
}
