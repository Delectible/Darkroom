import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;

import '../../features/cameras/domain/camera_catalog.dart';
import '../../features/cameras/domain/camera_spec.dart';
import '../db/app_database.dart';
import '../db/media_repository.dart';
import '../paths/app_paths.dart';
import '../settings/settings_repository.dart';
import 'crop_math.dart';
import 'film/film_profile.dart';
import 'isolate_jobs.dart';
import 'photo_pipeline.dart';
import 'video_pipeline.dart';

/// Snapshot of the user-facing settings at the moment of capture.
class CaptureContext {
  const CaptureContext({
    required this.spec,
    required this.aspect,
    required this.previewAspect,
    required this.flash,
    required this.timestamp,
    required this.global,
    this.rotationTurns = 0,
    this.grain = GrainStrength.normal,
  });

  final CameraSpec spec;
  final AspectRatioOption aspect;
  final double previewAspect;
  final FlashSetting flash;
  final bool timestamp;
  final GlobalSettings global;

  /// Physical device orientation at the shutter, as clockwise quarter turns.
  final int rotationTurns;

  /// Film stocks: grain strength from settings.
  final GrainStrength grain;
}

/// Owns the capture -> processed-file lifecycle.
///
///  1. The plugin's capture file is *moved* (not copied) into our private
///     capture cache and a `processing` row is written. From this point the
///     shot survives an app kill.
///  2. Jobs run strictly one at a time (bounded memory) in a background
///     isolate (stills) or FFmpeg's native threads (video).
///  3. On success the row flips to `ready` (which also nulls raw_path in the
///     same UPDATE), and only then is the un-filtered file deleted.
///  4. On launch, `recover()` resumes interrupted jobs and `sweepOrphans()`
///     purges any cache file no row references (e.g. a crash between 3a
///     and 3b).
class CaptureProcessor {
  CaptureProcessor({
    required this.paths,
    required this.db,
    required this.film,
    required this.sdCard,
    required this.onFilmQueueChanged,
  });

  final AppPaths paths;
  final AppDatabase db;
  final MediaRepository film;
  final MediaRepository sdCard;

  /// Lets the darkroom re-arm notifications when prints are added/finished.
  final Future<void> Function() onFilmQueueChanged;

  final _queue = <Future<void> Function()>[];
  final _inFlightRaw = <String>{};
  bool _draining = false;

  /// Number of captures waiting for / in processing (drives a UI spinner).
  final ValueNotifier<int> pending = ValueNotifier<int>(0);

  final _rnd = math.Random();

  String _newId() {
    final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final r = _rnd.nextInt(1 << 32).toRadixString(36).padLeft(7, '0');
    return '$t$r';
  }

  MediaRepository _repoFor(CameraSpec spec) => spec.mode == AppMode.film ? film : sdCard;

  Future<String> _moveIntoCache(String captured, String id, String ext) async {
    final dest = p.join(paths.captureCacheDir.path, '$id$ext');
    try {
      await File(captured).rename(dest);
    } on FileSystemException {
      // Different filesystem (rare): copy, then delete the plugin's temp file.
      await File(captured).copy(dest);
      await File(captured).delete();
    }
    return dest;
  }

  Future<String> _fileName(CameraSpec spec, MediaKind kind) async {
    final prefix = kind == MediaKind.photo ? spec.photoPrefix : spec.videoPrefix;
    if (spec.mode == AppMode.film && kind == MediaKind.video) {
      final n = await db.nextCounter('reel');
      return '$prefix${n.toString().padLeft(3, '0')}.MP4';
    }
    final n = await db.nextCounter(spec.mode == AppMode.film ? spec.roll.counter : prefix);
    if (spec.mode == AppMode.film) {
      final r = spec.roll;
      final frame = ((n - 1) % r.frames) + 1;
      final roll = ((n - 1) ~/ r.frames) + 1;
      return '${r.prefix}${roll.toString().padLeft(3, '0')}_${frame.toString().padLeft(2, '0')}'
          '${kind == MediaKind.photo ? '.JPG' : '.MP4'}';
    }
    final digits = 8 - prefix.length;
    return '$prefix${(n % math.pow(10, digits).toInt()).toString().padLeft(digits, '0')}'
        '${kind == MediaKind.photo ? '.JPG' : '.MP4'}';
  }

  Future<String> _uniqueOutput(Directory dir, String name, String id, CameraSpec spec) async {
    if (spec.mode == AppMode.film) {
      return p.join(dir.path, '$id${p.extension(name).toLowerCase()}');
    }
    var candidate = p.join(dir.path, name);
    if (await File(candidate).exists()) {
      candidate = p.join(dir.path, '${p.basenameWithoutExtension(name)}_$id${p.extension(name)}');
    }
    return candidate;
  }

  DateTime _readyAt(CaptureContext ctx, DateTime now) =>
      ctx.spec.mode == AppMode.film && ctx.global.darkroomEnabled
      ? now.add(ctx.spec.developTime)
      : now;

  /// Queues a still. Returns as soon as the capture is safely persisted.
  Future<String> enqueuePhoto(String capturedPath, CaptureContext ctx) async {
    final id = _newId();
    final now = DateTime.now();
    final spec = ctx.spec;
    final raw = await _moveIntoCache(capturedPath, id, '.jpg');
    _inFlightRaw.add(raw);
    final fileName = await _fileName(spec, MediaKind.photo);
    final outDir = spec.mode == AppMode.film ? paths.filmDir : paths.sdCardDir;
    final job = PhotoJob(
      id: id,
      cameraId: spec.id,
      rawPath: raw,
      outputPath: await _uniqueOutput(outDir, fileName, id, spec),
      thumbPath: p.join(paths.thumbsDir.path, '$id.jpg'),
      aspect: ctx.aspect,
      previewAspect: ctx.previewAspect,
      flash: ctx.flash,
      timestamp: ctx.timestamp,
      capturedAtMs: now.millisecondsSinceEpoch,
      rotationTurns: ctx.rotationTurns,
      grain: ctx.grain,
      originalCopyPath: ctx.global.saveOriginalCopy
          ? p.join(paths.captureCacheDir.path, '${id}_original.jpg')
          : null,
    );
    final repo = _repoFor(spec);
    await repo.insertProcessing(
      id: id,
      cameraId: spec.id,
      kind: MediaKind.photo,
      fileName: fileName,
      rawPath: raw,
      capturedAt: now,
      readyAt: _readyAt(ctx, now),
      jobJson: jsonEncode({'type': 'photo', ...job.toJson()}),
    );
    if (spec.mode == AppMode.film) unawaited(onFilmQueueChanged());
    _enqueue(() => _runPhoto(repo, job));
    return id;
  }

  /// Queues a recorded clip.
  Future<String> enqueueVideo(
    String capturedPath,
    CaptureContext ctx, {
    required DateTime startedAt,
    required Duration duration,
  }) async {
    final id = _newId();
    final now = DateTime.now();
    final spec = ctx.spec;
    final ext = p.extension(capturedPath).isEmpty ? '.mp4' : p.extension(capturedPath);
    final raw = await _moveIntoCache(capturedPath, id, ext);
    _inFlightRaw.add(raw);
    final fileName = await _fileName(spec, MediaKind.video);
    final outDir = spec.mode == AppMode.film ? paths.filmDir : paths.sdCardDir;
    final job = VideoJob(
      id: id,
      cameraId: spec.id,
      rawPath: raw,
      outputPath: await _uniqueOutput(outDir, fileName, id, spec),
      thumbPath: p.join(paths.thumbsDir.path, '$id.jpg'),
      workDir: p.join(paths.captureCacheDir.path, 'work_$id'),
      aspect: ctx.aspect,
      previewAspect: ctx.previewAspect,
      timestamp: ctx.timestamp,
      capturedAtMs: startedAt.millisecondsSinceEpoch,
      durationMs: duration.inMilliseconds,
      rotationTurns: ctx.rotationTurns,
      grain: ctx.grain,
    );
    final repo = _repoFor(spec);
    await repo.insertProcessing(
      id: id,
      cameraId: spec.id,
      kind: MediaKind.video,
      fileName: fileName,
      rawPath: raw,
      capturedAt: startedAt,
      readyAt: _readyAt(ctx, now),
      jobJson: jsonEncode({'type': 'video', ...job.toJson()}),
    );
    if (spec.mode == AppMode.film) unawaited(onFilmQueueChanged());
    _enqueue(() => _runVideo(repo, job));
    return id;
  }

  void _enqueue(Future<void> Function() task) {
    _queue.add(task);
    pending.value = _queue.length + (_draining ? 1 : 0);
    if (!_draining) unawaited(_drain());
  }

  Future<void> _drain() async {
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        final task = _queue.removeAt(0);
        pending.value = _queue.length + 1;
        try {
          await task();
        } catch (e, st) {
          debugPrint('Capture job crashed: $e\n$st');
        }
      }
    } finally {
      _draining = false;
      pending.value = 0;
    }
  }

  Future<void> _runPhoto(MediaRepository repo, PhotoJob job) async {
    try {
      await repo.bumpAttempts(job.id);
      // Heavy lifting (decode, crop, grade, grain, encode) never touches the
      // UI isolate.
      final r = await renderPhotoInIsolate(job);
      await repo.markReady(
        id: job.id,
        outputPath: job.outputPath,
        thumbPath: job.thumbPath,
        width: r.width,
        height: r.height,
        bytes: r.bytes,
      );
      await _deleteQuietly(job.rawPath);
      if (r.originalCopyPath != null) {
        await _saveOriginalToGallery(r.originalCopyPath!);
      }
    } catch (e) {
      await _handleFailure(repo, job.id, job.rawPath, e, retry: () => _runPhoto(repo, job));
    } finally {
      _inFlightRaw.remove(job.rawPath);
      if (identical(repo, film)) unawaited(onFilmQueueChanged());
    }
  }

  Future<void> _runVideo(MediaRepository repo, VideoJob job) async {
    try {
      await repo.bumpAttempts(job.id);
      final r = await VideoPipeline.run(job);
      await repo.markReady(
        id: job.id,
        outputPath: job.outputPath,
        thumbPath: job.thumbPath,
        width: r.width,
        height: r.height,
        bytes: r.bytes,
        durationMs: job.durationMs,
      );
      await _deleteQuietly(job.rawPath);
    } catch (e) {
      await _handleFailure(repo, job.id, job.rawPath, e, retry: () => _runVideo(repo, job));
    } finally {
      _inFlightRaw.remove(job.rawPath);
      if (identical(repo, film)) unawaited(onFilmQueueChanged());
    }
  }

  /// A job gets three attempts in total (counted in the DB, so they also
  /// span app restarts) before it is marked failed and its raw file purged,
  /// so a corrupt capture can never leak storage or loop forever.
  Future<void> _handleFailure(
    MediaRepository repo,
    String id,
    String raw,
    Object e, {
    required Future<void> Function() retry,
  }) async {
    debugPrint('Processing $id failed: $e');
    final item = await repo.byId(id);
    if (item == null || item.attempts >= 3 || !File(raw).existsSync()) {
      await repo.markFailed(id, e.toString());
      await _deleteQuietly(raw);
      return;
    }
    // Transient (e.g. low memory while the camera is busy): back off, retry.
    Timer(Duration(seconds: 2 * item.attempts), () {
      _inFlightRaw.add(raw);
      _enqueue(retry);
    });
  }

  Future<void> _saveOriginalToGallery(String path) async {
    try {
      final ok = await Gal.hasAccess(toAlbum: true) || await Gal.requestAccess(toAlbum: true);
      if (ok) await Gal.putImage(path, album: 'Darkroom Originals');
    } catch (e) {
      debugPrint('Could not save original: $e');
    } finally {
      await _deleteQuietly(path);
    }
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } on FileSystemException catch (e) {
      debugPrint('Could not delete $path: $e');
    }
  }

  /// Resumes jobs interrupted by an app kill. Call once at startup.
  Future<void> recover() async {
    for (final repo in [film, sdCard]) {
      for (final item in await repo.processing()) {
        final raw = item.rawPath;
        final jobJson = item.job;
        if (raw == null || jobJson == null || !File(raw).existsSync()) {
          await repo.markFailed(item.id, 'Capture file missing after restart');
          continue;
        }
        _inFlightRaw.add(raw);
        final map = jsonDecode(jobJson) as Map<String, Object?>;
        if (map['type'] == 'video') {
          final job = VideoJob.fromJson(map);
          _enqueue(() => _runVideo(repo, job));
        } else {
          final job = PhotoJob.fromJson(map);
          _enqueue(() => _runPhoto(repo, job));
        }
      }
    }
  }

  /// Deletes capture-cache files no DB row references, stale `.part` files
  /// and failed rows' leftovers.
  Future<void> sweepOrphans() async {
    final referenced = {...await film.referencedPaths(), ...await sdCard.referencedPaths(), ..._inFlightRaw};
    final dir = paths.captureCacheDir;
    if (!await dir.exists()) return;
    await for (final e in dir.list()) {
      final path = e.path;
      if (referenced.contains(path)) continue;
      // Work dirs of in-flight video jobs are named after the job id.
      if (e is Directory &&
          _inFlightRaw.any((r) => p.basename(path) == 'work_${p.basenameWithoutExtension(r)}')) {
        continue;
      }
      try {
        await e.delete(recursive: true);
      } on FileSystemException {
        // in use / already gone
      }
    }
    for (final d in [paths.filmDir, paths.sdCardDir, paths.thumbsDir]) {
      if (!await d.exists()) continue;
      await for (final e in d.list()) {
        if (e is File && e.path.endsWith('.part')) {
          await _deleteQuietly(e.path);
        }
      }
    }
  }

  /// Convenience for UIs that need the spec of a stored item.
  static CameraSpec specFor(MediaItem item) => CameraCatalog.byId(item.cameraId);
}
