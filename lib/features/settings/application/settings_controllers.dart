import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';

import '../../../core/audio/sfx.dart';
import '../../../core/device/haptics.dart';
import '../../../core/processing/crop_math.dart';
import '../../../core/processing/film/film_profile.dart';
import '../../../core/providers.dart';
import '../../../core/shaders/shader_library.dart' show FilmUniforms;
import '../../../core/settings/settings_repository.dart';
import '../../cameras/domain/camera_catalog.dart';

class GlobalSettingsNotifier extends Notifier<GlobalSettings> {
  @override
  GlobalSettings build() {
    final s = ref.read(initialGlobalSettingsProvider);
    _apply(s);
    return s;
  }

  /// Sounds and haptics are switched app-wide (no ref needed at call sites).
  static void _apply(GlobalSettings s) {
    Sfx.level = s.sfxVolume;
    Haptics.enabled = s.haptics;
    FilmUniforms.lite = s.performance;
  }

  /// Sound effects level, 0 (off) .. 1; saved when the slider is let go.
  Future<void> setSfxVolume(double v, {bool save = true}) async {
    state = state.copyWith(sfxVolume: v.clamp(0.0, 1.0));
    _apply(state);
    if (save) await _repo.saveGlobal(state);
  }

  Future<void> setHaptics(bool enabled) async {
    state = state.copyWith(haptics: enabled);
    _apply(state);
    await _repo.saveGlobal(state);
  }

  Future<void> setPerformance(bool enabled) async {
    state = state.copyWith(performance: enabled);
    _apply(state);
    await _repo.saveGlobal(state);
  }

  Future<void> setControls3d(bool enabled) async {
    state = state.copyWith(controls3d: enabled);
    await _repo.saveGlobal(state);
  }

  SettingsRepository get _repo => ref.read(settingsRepositoryProvider);

  Future<void> setDarkroomEnabled(bool enabled) async {
    state = state.copyWith(darkroomEnabled: enabled);
    await _repo.saveGlobal(state);
    final engine = ref.read(darkroomEngineProvider);
    if (enabled) {
      await engine.reschedule();
    } else {
      // Instant development: anything still in the tanks is done now.
      await engine.developEverythingNow();
    }
  }

  /// Returns false if the OS refused the permission.
  Future<bool> setNotificationsEnabled(bool enabled) async {
    final notifications = ref.read(notificationServiceProvider);
    var granted = true;
    if (enabled) granted = await notifications.requestPermission();
    state = state.copyWith(notificationsEnabled: enabled && granted);
    await _repo.saveGlobal(state);
    if (!state.notificationsEnabled) await notifications.cancelDeveloped();
    await ref.read(darkroomEngineProvider).reschedule();
    return granted;
  }

  Future<void> setVolumeZoom(bool enabled) async {
    state = state.copyWith(volumeZoom: enabled);
    await _repo.saveGlobal(state);
  }

  Future<void> setSaveOriginalCopy(bool enabled) async {
    if (enabled) {
      final ok = await Gal.hasAccess(toAlbum: true) || await Gal.requestAccess(toAlbum: true);
      if (!ok) return;
    }
    state = state.copyWith(saveOriginalCopy: enabled);
    await _repo.saveGlobal(state);
  }
}

final globalSettingsProvider = NotifierProvider<GlobalSettingsNotifier, GlobalSettings>(
  GlobalSettingsNotifier.new,
);

class CameraSettingsNotifier extends Notifier<Map<String, CameraLocalSettings>> {
  @override
  Map<String, CameraLocalSettings> build() => ref.read(initialCameraSettingsProvider);

  CameraLocalSettings of(String cameraId) =>
      state[cameraId] ?? CameraLocalSettings.defaultsFor(CameraCatalog.byId(cameraId));

  Future<void> _put(String cameraId, CameraLocalSettings s) async {
    state = {...state, cameraId: s};
    await ref.read(settingsRepositoryProvider).saveCameraSettings(cameraId, s);
  }

  Future<void> setAspect(String cameraId, AspectRatioOption aspect) async {
    final spec = CameraCatalog.byId(cameraId);
    if (!spec.aspects.contains(aspect)) return;
    await _put(cameraId, of(cameraId).copyWith(aspect: aspect));
  }

  /// Cycles to the next ratio the stock allows (the viewport's quick toggle).
  Future<void> cycleAspect(String cameraId) async {
    final spec = CameraCatalog.byId(cameraId);
    if (spec.aspectLocked) return;
    final i = spec.aspects.indexOf(of(cameraId).aspect);
    await setAspect(cameraId, spec.aspects[(i + 1) % spec.aspects.length]);
  }

  Future<void> setGrain(String cameraId, GrainStrength grain) async {
    if (CameraCatalog.byId(cameraId).film == null) return;
    await _put(cameraId, of(cameraId).copyWith(grain: grain));
  }

  Future<void> setTimestamp(String cameraId, bool enabled) async {
    final spec = CameraCatalog.byId(cameraId);
    if (!spec.supportsTimestamp) return;
    await _put(cameraId, of(cameraId).copyWith(timestamp: enabled));
  }
}

final cameraSettingsProvider = NotifierProvider<CameraSettingsNotifier, Map<String, CameraLocalSettings>>(
  CameraSettingsNotifier.new,
);
