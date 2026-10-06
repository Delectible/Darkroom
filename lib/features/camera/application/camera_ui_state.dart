import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/processing/photo_pipeline.dart';
import '../../../core/providers.dart';
import '../../../core/settings/settings_repository.dart';
import '../../cameras/domain/camera_catalog.dart';
import '../../cameras/domain/camera_spec.dart';
import '../../settings/application/settings_controllers.dart';

/// SharedPreferences keys (the cache allow-list is built from this set).
class PrefKeys {
  const PrefKeys._();

  static const mode = 'ui.mode';
  static const cameraFilm = 'ui.camera.film';
  static const cameraDigital = 'ui.camera.digital';
  static const flashFilm = 'ui.flash.film';
  static const flashDigital = 'ui.flash.digital';
  static const explorerView = 'ui.explorer.view';
  static const explorerSort = 'ui.explorer.sort';
  static const explorerSortAsc = 'ui.explorer.sortAsc';
  static const explorerFilter = 'ui.explorer.filter';
  static const explorerTree = 'ui.explorer.tree';

  static const all = <String>{
    mode,
    cameraFilm,
    cameraDigital,
    flashFilm,
    flashDigital,
    explorerView,
    explorerSort,
    explorerSortAsc,
    explorerFilter,
    explorerTree,
  };
}

class AppModeNotifier extends Notifier<AppMode> {
  @override
  AppMode build() {
    final v = ref.read(sharedPrefsProvider).getString(PrefKeys.mode);
    return v == AppMode.digital.name ? AppMode.digital : AppMode.film;
  }

  Future<void> set(AppMode mode) async {
    if (mode == state) return;
    state = mode;
    await ref.read(sharedPrefsProvider).setString(PrefKeys.mode, mode.name);
  }

  Future<void> toggle() => set(state == AppMode.film ? AppMode.digital : AppMode.film);
}

final appModeProvider = NotifierProvider<AppModeNotifier, AppMode>(AppModeNotifier.new);

/// Selected camera per mode (each mode remembers its own stock/body).
class SelectedCameraNotifier extends Notifier<Map<AppMode, String>> {
  @override
  Map<AppMode, String> build() {
    final prefs = ref.read(sharedPrefsProvider);
    String pick(String key, List<CameraSpec> list) {
      final id = prefs.getString(key);
      return list.any((c) => c.id == id) ? id! : list.first.id;
    }

    return {
      AppMode.film: pick(PrefKeys.cameraFilm, CameraCatalog.film),
      AppMode.digital: pick(PrefKeys.cameraDigital, CameraCatalog.digital),
    };
  }

  Future<void> select(AppMode mode, String id) async {
    if (state[mode] == id) return;
    state = {...state, mode: id};
    await ref
        .read(sharedPrefsProvider)
        .setString(mode == AppMode.film ? PrefKeys.cameraFilm : PrefKeys.cameraDigital, id);
  }

  /// Next / previous stock or body in catalog order (wraps around).
  Future<void> step(AppMode mode, int delta) {
    final list = CameraCatalog.forMode(mode);
    final i = list.indexWhere((c) => c.id == state[mode]);
    return select(mode, list[(i + delta) % list.length].id);
  }
}

final selectedCameraProvider = NotifierProvider<SelectedCameraNotifier, Map<AppMode, String>>(
  SelectedCameraNotifier.new,
);

final activeSpecProvider = Provider<CameraSpec>((ref) {
  final mode = ref.watch(appModeProvider);
  final id = ref.watch(selectedCameraProvider)[mode]!;
  return CameraCatalog.byId(id);
});

final activeCameraSettingsProvider = Provider<CameraLocalSettings>((ref) {
  final spec = ref.watch(activeSpecProvider);
  return ref.watch(cameraSettingsProvider)[spec.id] ?? CameraLocalSettings.defaultsFor(spec);
});

class FlashNotifier extends Notifier<Map<AppMode, FlashSetting>> {
  @override
  Map<AppMode, FlashSetting> build() {
    final prefs = ref.read(sharedPrefsProvider);
    FlashSetting read(String k) => FlashSetting.values.asNameMap()[prefs.getString(k)] ?? FlashSetting.auto;
    return {AppMode.film: read(PrefKeys.flashFilm), AppMode.digital: read(PrefKeys.flashDigital)};
  }

  Future<void> cycle(AppMode mode) async {
    const order = [FlashSetting.auto, FlashSetting.on, FlashSetting.off];
    final next = order[(order.indexOf(state[mode]!) + 1) % order.length];
    state = {...state, mode: next};
    await ref
        .read(sharedPrefsProvider)
        .setString(mode == AppMode.film ? PrefKeys.flashFilm : PrefKeys.flashDigital, next.name);
  }
}

final flashProvider = NotifierProvider<FlashNotifier, Map<AppMode, FlashSetting>>(FlashNotifier.new);

final activeFlashProvider = Provider<FlashSetting>((ref) {
  return ref.watch(flashProvider)[ref.watch(appModeProvider)]!;
});

class LensNotifier extends Notifier<CameraLensDirection> {
  @override
  CameraLensDirection build() => CameraLensDirection.back;

  void toggle() =>
      state = state == CameraLensDirection.back ? CameraLensDirection.front : CameraLensDirection.back;
}

final lensProvider = NotifierProvider<LensNotifier, CameraLensDirection>(LensNotifier.new);

/// Maps the pure-Dart capture class onto the plugin preset.
///
/// The camera plugin uses one preset for both the live preview and the
/// capture, so this is also the preview stream size. 1080p keeps the shader
/// preview smooth on old phones; film only goes to 2160p when the user opts
/// into "High-resolution film".
ResolutionPreset presetFor(CaptureQuality q, {bool highResFilm = false}) => switch (q) {
  CaptureQuality.high => highResFilm ? ResolutionPreset.ultraHigh : ResolutionPreset.veryHigh,
  CaptureQuality.standard => ResolutionPreset.veryHigh,
  CaptureQuality.low => ResolutionPreset.medium,
};

final activeGlobalSettingsProvider = Provider<GlobalSettings>((ref) => ref.watch(globalSettingsProvider));
