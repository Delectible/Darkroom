import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolved storage roots.
///
/// The database only ever stores paths *relative* to these roots: on iOS the
/// app container path changes on every update/reinstall, so absolute paths
/// persisted in SQLite would dangle after an App Store update.
class AppPaths {
  AppPaths._(this.supportDir, this.documentsDir);

  /// Private, not user-visible, not purged by the OS. Holds the capture
  /// cache (un-filtered raw files waiting to be processed).
  final Directory supportDir;

  /// Holds finished output (film prints, SD card files).
  final Directory documentsDir;

  static AppPaths? _instance;

  static Future<AppPaths> resolve() async {
    if (_instance != null) return _instance!;
    final support = await getApplicationSupportDirectory();
    final docs = await getApplicationDocumentsDirectory();
    final paths = AppPaths._(support, docs);
    for (final d in [paths.captureCacheDir, paths.filmDir, paths.sdCardDir, paths.thumbsDir]) {
      await d.create(recursive: true);
    }
    return _instance = paths;
  }

  Directory get captureCacheDir => Directory(p.join(supportDir.path, 'capture_cache'));
  Directory get filmDir => Directory(p.join(documentsDir.path, 'film'));
  Directory get sdCardDir => Directory(p.join(documentsDir.path, 'sdcard', 'DCIM', '100RETRO'));
  Directory get thumbsDir => Directory(p.join(supportDir.path, 'thumbs'));

  /// Converts an absolute path under one of our roots into a storable token.
  String toStored(String absolute) {
    if (p.isWithin(documentsDir.path, absolute)) {
      return 'docs:${p.relative(absolute, from: documentsDir.path)}';
    }
    if (p.isWithin(supportDir.path, absolute)) {
      return 'support:${p.relative(absolute, from: supportDir.path)}';
    }
    return absolute;
  }

  String fromStored(String stored) {
    if (stored.startsWith('docs:')) return p.join(documentsDir.path, stored.substring(5));
    if (stored.startsWith('support:')) return p.join(supportDir.path, stored.substring(8));
    return stored;
  }

  String? fromStoredOrNull(String? stored) => stored == null ? null : fromStored(stored);
}
