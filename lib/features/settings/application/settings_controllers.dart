import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';

import '../../../core/processing/crop_math.dart';
import '../../../core/processing/film/film_profile.dart';
import '../../../core/providers.dart';
import '../../../core/settings/settings_repository.dart';
import '../../cameras/domain/camera_catalog.dart';

class GlobalSettingsNotifier extends Notifier<GlobalSettings> {
  @override
  GlobalSettings build() => ref.read(initialGlobalSettingsProvider);

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

  Future<void> setHighResFilm(bool enabled) async {
    state = state.copyWith(highResFilm: enabled);
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
