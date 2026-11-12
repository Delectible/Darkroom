import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../settings/application/settings_controllers.dart';

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
    unawaited(_restore());
    return _for(ref.read(activeSpecProvider));
  }

  /// Settings > keep lens and special: the lenses from last time.
  Future<void> _restore() async {
    final kept = await Remembered.read(ref, Remembered.lensKey);
    if (kept.isEmpty || !ref.mounted) return;
    for (final MapEntry(:key, :value) in kept.entries) {
      final l = LensKind.values.asNameMap()[value];
      if (l != null) _byCamera[key] = l;
    }
    state = _for(ref.read(activeSpecProvider));
  }

  /// The lens [spec] goes on with (its own last one, else its first).
  LensKind lensFor(CameraSpec spec) => _for(spec);

  LensKind _for(CameraSpec spec) {
    final l = _byCamera[spec.id];
    return l != null && lensesFor(spec, ref.read(ultraWideProvider)).contains(l) ? l : spec.lenses.first;
  }

  void set(LensKind lens) {
    final spec = ref.read(activeSpecProvider);
    if (!lensesFor(spec, ref.read(ultraWideProvider)).contains(lens)) return;
    _byCamera[spec.id] = lens;
    state = lens;
    Remembered.write(ref, Remembered.lensKey, {for (final e in _byCamera.entries) e.key: e.value.name});
  }
}

/// The lenses that take the phone's widest camera (its ultra-wide, where
/// it has one): changing to or from one is a camera change.
bool takesWidest(LensKind lens) => lens == LensKind.wide || lens == LensKind.fisheye;

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

/// Each camera's lens and special, kept between launches when Settings asks
/// (GlobalSettings.rememberLens): small JSON maps in the app's key store.
class Remembered {
  Remembered._();

  static const lensKey = 'remember.lenses';
  static const specialKey = 'remember.specials';

  static Future<Map<String, Object?>> read(Ref ref, String key) async {
    try {
      if (!ref.read(globalSettingsProvider).rememberLens) return const {};
      final v = await ref.read(appDatabaseProvider).getValue(key);
      return v == null ? const {} : (jsonDecode(v) as Map<String, Object?>);
    } catch (_) {
      return const {}; // (no store: tests; or unreadable)
    }
  }

  static void write(Ref ref, String key, Map<String, Object?> value) {
    try {
      if (!ref.read(globalSettingsProvider).rememberLens) return;
      unawaited(ref.read(appDatabaseProvider).setValue(key, jsonEncode(value)).catchError((Object _) {}));
    } catch (_) {}
  }
}
