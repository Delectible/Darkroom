import 'package:sqflite/sqflite.dart';

import '../../features/cameras/domain/camera_catalog.dart';
import '../../features/cameras/domain/camera_spec.dart';
import '../db/app_database.dart';
import '../processing/crop_math.dart';
import '../processing/film/film_profile.dart';

/// App-wide toggles. Stored in SQLite (not SharedPreferences) because the
/// WorkManager isolate needs to read them too.
class GlobalSettings {
  const GlobalSettings({
    this.darkroomEnabled = true,
    this.notificationsEnabled = true,
    this.saveOriginalCopy = false,
    this.volumeZoom = false,
    this.soundEffects = true,
    this.haptics = true,
  });

  final bool darkroomEnabled;
  final bool notificationsEnabled;
  final bool saveOriginalCopy;

  /// The volume buttons are the shutter; with this on they zoom instead on
  /// digital bodies (film keeps them as the shutter).
  final bool volumeZoom;

  /// The app's own sounds (shutters, clicks, swooshes...). Video and clip
  /// audio play regardless.
  final bool soundEffects;

  /// Vibration feedback.
  final bool haptics;

  GlobalSettings copyWith({
    bool? darkroomEnabled,
    bool? notificationsEnabled,
    bool? saveOriginalCopy,
    bool? volumeZoom,
    bool? soundEffects,
    bool? haptics,
  }) => GlobalSettings(
    darkroomEnabled: darkroomEnabled ?? this.darkroomEnabled,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    saveOriginalCopy: saveOriginalCopy ?? this.saveOriginalCopy,
    volumeZoom: volumeZoom ?? this.volumeZoom,
    soundEffects: soundEffects ?? this.soundEffects,
    haptics: haptics ?? this.haptics,
  );
}

/// Per-stock / per-body preferences.
class CameraLocalSettings {
  const CameraLocalSettings({
    required this.aspect,
    required this.timestamp,
    this.grain = GrainStrength.normal,
  });

  final AspectRatioOption aspect;
  final bool timestamp;

  /// Film stocks only.
  final GrainStrength grain;

  CameraLocalSettings copyWith({AspectRatioOption? aspect, bool? timestamp, GrainStrength? grain}) =>
      CameraLocalSettings(
        aspect: aspect ?? this.aspect,
        timestamp: timestamp ?? this.timestamp,
        grain: grain ?? this.grain,
      );

  static CameraLocalSettings defaultsFor(CameraSpec spec) =>
      CameraLocalSettings(aspect: spec.defaultAspect, timestamp: spec.supportsTimestamp);
}

class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  static const _kDarkroom = 'global.darkroom';
  static const _kNotify = 'global.notifications';
  static const _kOriginal = 'global.saveOriginal';
  static const _kVolumeZoom = 'global.volumeZoom';
  static const _kSounds = 'global.soundEffects';
  static const _kHaptics = 'global.haptics';

  Future<GlobalSettings> loadGlobal() async {
    bool read(String? v, bool fallback) => v == null ? fallback : v == '1';
    const d = GlobalSettings();
    return GlobalSettings(
      darkroomEnabled: read(await _db.getValue(_kDarkroom), d.darkroomEnabled),
      notificationsEnabled: read(await _db.getValue(_kNotify), d.notificationsEnabled),
      saveOriginalCopy: read(await _db.getValue(_kOriginal), d.saveOriginalCopy),
      volumeZoom: read(await _db.getValue(_kVolumeZoom), d.volumeZoom),
      soundEffects: read(await _db.getValue(_kSounds), d.soundEffects),
      haptics: read(await _db.getValue(_kHaptics), d.haptics),
    );
  }

  Future<void> saveGlobal(GlobalSettings s) async {
    await _db.setValue(_kDarkroom, s.darkroomEnabled ? '1' : '0');
    await _db.setValue(_kNotify, s.notificationsEnabled ? '1' : '0');
    await _db.setValue(_kOriginal, s.saveOriginalCopy ? '1' : '0');
    await _db.setValue(_kVolumeZoom, s.volumeZoom ? '1' : '0');
    await _db.setValue(_kSounds, s.soundEffects ? '1' : '0');
    await _db.setValue(_kHaptics, s.haptics ? '1' : '0');
  }

  Future<Map<String, CameraLocalSettings>> loadCameraSettings() async {
    final rows = await _db.db.query('camera_settings');
    final byId = {for (final r in rows) r['camera_id']! as String: r};
    return {
      for (final spec in CameraCatalog.all)
        spec.id: () {
          final r = byId[spec.id];
          final d = CameraLocalSettings.defaultsFor(spec);
          if (r == null) return d;
          var aspect = AspectRatioOption.fromName(r['aspect'] as String?, d.aspect);
          if (!spec.aspects.contains(aspect)) aspect = spec.defaultAspect;
          final ts = r['timestamp'] as int?;
          return CameraLocalSettings(
            aspect: aspect,
            timestamp: spec.supportsTimestamp && (ts == null ? d.timestamp : ts == 1),
            grain: spec.film == null ? GrainStrength.normal : GrainStrength.fromName(r['grain'] as String?),
          );
        }(),
    };
  }

  Future<void> saveCameraSettings(String cameraId, CameraLocalSettings s) => _db.db.insert(
    'camera_settings',
    {'camera_id': cameraId, 'aspect': s.aspect.name, 'timestamp': s.timestamp ? 1 : 0, 'grain': s.grain.name},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}
