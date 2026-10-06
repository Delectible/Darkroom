import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../paths/app_paths.dart';
import 'app_database.dart';

enum MediaKind { photo, video }

enum MediaStatus { processing, ready, failed }

/// Where a digital file lives: still on the virtual SD card, or moved to
/// "Local Disk (C:)" (and the phone's photo library).
enum MediaLocation { sd, c }

/// A captured photo/video in either the Darkroom/Corkboard (film) or the
/// virtual SD card (digital). Paths are absolute (resolved from the DB's
/// relative tokens by the repository).
class MediaItem {
  const MediaItem({
    required this.id,
    required this.cameraId,
    required this.kind,
    required this.status,
    required this.fileName,
    required this.capturedAt,
    required this.readyAt,
    this.rawPath,
    this.outputPath,
    this.thumbPath,
    this.width,
    this.height,
    this.bytes,
    this.durationMs,
    this.notified = false,
    this.seen = false,
    this.job,
    this.attempts = 0,
    this.error,
    this.location = MediaLocation.sd,
    this.savedAt,
    this.note,
  });

  final String id;
  final String cameraId;
  final MediaKind kind;
  final MediaStatus status;
  final String fileName;
  final DateTime capturedAt;

  /// Film only: when the print comes out of the developer.
  final DateTime readyAt;
  final String? rawPath;
  final String? outputPath;
  final String? thumbPath;
  final int? width;
  final int? height;
  final int? bytes;
  final int? durationMs;
  final bool notified;
  final bool seen;
  final String? job;
  final int attempts;
  final String? error;
  final MediaLocation location;

  /// When the file was copied into the phone's photo library (null = never).
  final DateTime? savedAt;

  /// Instant prints: what the user wrote on the bottom border.
  final String? note;

  bool get isVideo => kind == MediaKind.video;
  bool get isReady => status == MediaStatus.ready;
  bool get isSaved => savedAt != null;
  bool get onSdCard => location == MediaLocation.sd;

  /// Processed *and* past its development time.
  bool isDevelopedAt(DateTime now) => isReady && !readyAt.isAfter(now);
}

/// CRUD for one media table plus a change feed for Riverpod providers.
class MediaRepository {
  MediaRepository(this._db, this._paths, {required this.table});

  final AppDatabase _db;
  final AppPaths _paths;
  final String table;

  final _changes = StreamController<void>.broadcast();

  /// Emits whenever this table is modified *from this isolate*.
  Stream<void> get changes => _changes.stream;

  void notifyChanged() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Database get _sql => _db.db;

  MediaItem _fromRow(Map<String, Object?> r) => MediaItem(
    id: r['id']! as String,
    cameraId: r['camera_id']! as String,
    kind: MediaKind.values.byName(r['kind']! as String),
    status: MediaStatus.values.byName(r['status']! as String),
    fileName: r['file_name']! as String,
    capturedAt: DateTime.fromMillisecondsSinceEpoch(r['captured_at']! as int),
    readyAt: DateTime.fromMillisecondsSinceEpoch(r['ready_at']! as int),
    rawPath: _paths.fromStoredOrNull(r['raw_path'] as String?),
    outputPath: _paths.fromStoredOrNull(r['output_path'] as String?),
    thumbPath: _paths.fromStoredOrNull(r['thumb_path'] as String?),
    width: r['width'] as int?,
    height: r['height'] as int?,
    bytes: r['bytes'] as int?,
    durationMs: r['duration_ms'] as int?,
    notified: (r['notified'] as int? ?? 0) == 1,
    seen: (r['seen'] as int? ?? 0) == 1,
    job: r['job'] as String?,
    attempts: r['attempts'] as int? ?? 0,
    error: r['error'] as String?,
    location: (r['location'] as String?) == 'c' ? MediaLocation.c : MediaLocation.sd,
    savedAt: r['saved_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['saved_at']! as int),
    note: r['note'] as String?,
  );

  Future<void> insertProcessing({
    required String id,
    required String cameraId,
    required MediaKind kind,
    required String fileName,
    required String rawPath,
    required DateTime capturedAt,
    required DateTime readyAt,
    required String jobJson,
  }) async {
    await _sql.insert(table, {
      'id': id,
      'camera_id': cameraId,
      'kind': kind.name,
      'status': MediaStatus.processing.name,
      'raw_path': _paths.toStored(rawPath),
      'file_name': fileName,
      'captured_at': capturedAt.millisecondsSinceEpoch,
      'ready_at': readyAt.millisecondsSinceEpoch,
      'job': jobJson,
    });
    notifyChanged();
  }

  /// Marks a job finished. The raw path is cleared in the same statement so a
  /// crash between "file written" and "raw deleted" can never re-process.
  Future<void> markReady({
    required String id,
    required String outputPath,
    required String thumbPath,
    required int width,
    required int height,
    required int bytes,
    int? durationMs,
  }) async {
    await _sql.update(
      table,
      {
        'status': MediaStatus.ready.name,
        'output_path': _paths.toStored(outputPath),
        'thumb_path': _paths.toStored(thumbPath),
        'raw_path': null,
        'width': width,
        'height': height,
        'bytes': bytes,
        'duration_ms': durationMs,
        'job': null,
        'error': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    notifyChanged();
  }

  Future<void> markFailed(String id, String error) async {
    await _sql.update(
      table,
      {'status': MediaStatus.failed.name, 'error': error, 'raw_path': null},
      where: 'id = ?',
      whereArgs: [id],
    );
    notifyChanged();
  }

  /// Records that [ids] were copied to the photo library; with [moveToC]
  /// the files also leave the SD card for "Local Disk (C:)".
  Future<void> markSaved(List<String> ids, {bool moveToC = false}) async {
    if (ids.isEmpty) return;
    final values = <String, Object?>{'saved_at': DateTime.now().millisecondsSinceEpoch};
    if (moveToC) values['location'] = MediaLocation.c.name;
    await _sql.update(
      table,
      values,
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
    notifyChanged();
  }

  /// Writes (or clears, with an empty string) an instant print's note.
  Future<void> setNote(String id, String note) async {
    final v = note.trim();
    await _sql.update(table, {'note': v.isEmpty ? null : v}, where: 'id = ?', whereArgs: [id]);
    notifyChanged();
  }

  /// Renames an item: its label ([fileName]) and, when the file on disk
  /// moved too, its [outputPath].
  Future<void> rename(String id, {required String fileName, String? outputPath}) async {
    await _sql.update(
      table,
      {'file_name': fileName, if (outputPath != null) 'output_path': _paths.toStored(outputPath)},
      where: 'id = ?',
      whereArgs: [id],
    );
    notifyChanged();
  }

  Future<void> bumpAttempts(String id) =>
      _sql.rawUpdate('UPDATE $table SET attempts = attempts + 1 WHERE id = ?', [id]);

  Future<void> delete(String id) async {
    await _sql.delete(table, where: 'id = ?', whereArgs: [id]);
    notifyChanged();
  }

  Future<List<MediaItem>> all() async {
    final rows = await _sql.query(table, orderBy: 'captured_at DESC');
    return rows.map(_fromRow).toList();
  }

  Future<MediaItem?> byId(String id) async {
    final rows = await _sql.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<List<MediaItem>> processing() async {
    final rows = await _sql.query(
      table,
      where: 'status = ?',
      whereArgs: [MediaStatus.processing.name],
      orderBy: 'captured_at ASC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<List<MediaItem>> readyItems() async {
    final rows = await _sql.query(
      table,
      where: 'status = ?',
      whereArgs: [MediaStatus.ready.name],
      orderBy: 'captured_at ASC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Every stored file path (for orphan sweeping).
  Future<Set<String>> referencedPaths() async {
    final rows = await _sql.query(table, columns: ['raw_path', 'output_path', 'thumb_path']);
    return {
      for (final r in rows)
        for (final k in ['raw_path', 'output_path', 'thumb_path'])
          if (r[k] != null) _paths.fromStored(r[k]! as String),
    };
  }

  // ---- Darkroom bookkeeping (film table) ------------------------------------

  /// Earliest ready_at among processed prints that have not been announced.
  Future<DateTime?> nextUnnotifiedReadyAt({required DateTime after}) async {
    final rows = await _sql.rawQuery(
      'SELECT MIN(ready_at) AS t FROM $table WHERE notified = 0 AND status != ? AND ready_at > ?',
      [MediaStatus.failed.name, after.millisecondsSinceEpoch],
    );
    final t = rows.first['t'] as int?;
    return t == null ? null : DateTime.fromMillisecondsSinceEpoch(t);
  }

  /// Developed prints that have not been announced yet.
  ///
  /// Announcing is "post notification, then [markNotified]": the darkroom
  /// notification has a fixed id, so if the UI timer and the WorkManager
  /// worker race, the loser merely re-posts the same card (silently, thanks
  /// to onlyAlertOnce) instead of losing or duplicating an announcement.
  Future<List<MediaItem>> developedUnnotified(DateTime now) async {
    final rows = await _sql.query(
      table,
      where: 'notified = 0 AND status = ? AND ready_at <= ?',
      whereArgs: [MediaStatus.ready.name, now.millisecondsSinceEpoch],
    );
    return rows.map(_fromRow).toList();
  }

  Future<void> markNotified(List<String> ids) async {
    if (ids.isEmpty) return;
    await _sql.rawUpdate(
      'UPDATE $table SET notified = 1 WHERE id IN (${List.filled(ids.length, '?').join(',')})',
      ids,
    );
    notifyChanged();
  }

  /// Developed prints the user has not looked at yet (drives the cumulative
  /// "N photos have finished developing" text).
  Future<({int photos, int videos})> unseenDevelopedCounts(DateTime now) async {
    final rows = await _sql.rawQuery(
      'SELECT kind, COUNT(*) AS n FROM $table WHERE seen = 0 AND status = ? AND ready_at <= ? GROUP BY kind',
      [MediaStatus.ready.name, now.millisecondsSinceEpoch],
    );
    var photos = 0, videos = 0;
    for (final r in rows) {
      if (r['kind'] == MediaKind.video.name) {
        videos = r['n']! as int;
      } else {
        photos = r['n']! as int;
      }
    }
    return (photos: photos, videos: videos);
  }

  /// Pending prints in ready_at order (iOS notification batching).
  Future<List<MediaItem>> pendingDevelopment(DateTime now) async {
    final rows = await _sql.query(
      table,
      where: 'status != ? AND ready_at > ?',
      whereArgs: [MediaStatus.failed.name, now.millisecondsSinceEpoch],
      orderBy: 'ready_at ASC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<void> markAllSeen(DateTime now) async {
    final n = await _sql.update(
      table,
      {'seen': 1, 'notified': 1},
      where: 'seen = 0 AND status = ? AND ready_at <= ?',
      whereArgs: [MediaStatus.ready.name, now.millisecondsSinceEpoch],
    );
    if (n > 0) notifyChanged();
  }

  /// Darkroom toggled off: everything still in the developer is done now.
  Future<void> developAllNow(DateTime now) async {
    final n = await _sql.update(
      table,
      {'ready_at': now.millisecondsSinceEpoch},
      where: 'ready_at > ?',
      whereArgs: [now.millisecondsSinceEpoch],
    );
    if (n > 0) notifyChanged();
  }

  Future<void> dispose() => _changes.close();
}
