import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/app_info.dart';
import '../../../core/db/media_repository.dart';
import '../../../core/device/gallery_check.dart';
import '../../../core/processing/instant_frame.dart';
import '../../cameras/domain/camera_catalog.dart';

/// The file that leaves the app for [item]: instant prints get their border
/// and handwritten note baked in; everything else is shared as stored.
Future<String?> exportPathFor(MediaItem item) async {
  final path = item.outputPath;
  if (path == null || !File(path).existsSync()) return null;
  if (item.isVideo || !CameraCatalog.byId(item.cameraId).isInstant) return path;
  // Framing + JPEG-encoding an instant print takes a few seconds (the
  // encoder is pure Dart), so each version (picture + note) is made once,
  // ahead of time where possible (warmShareExport), and reused.
  final stamp = File(path).lastModifiedSync().millisecondsSinceEpoch;
  final key = '${item.id}_${stamp}_${(item.note ?? '').trim().hashCode.toUnsigned(32)}';
  final out = File('${Directory.systemTemp.path}/instant_export/$key/${item.fileName}');
  if (out.existsSync() && out.lengthSync() > 0) return out.path;
  return _exporting[key] ??= () async {
    try {
      // Written next to the final name and moved into place, so a half-
      // written file (the app killed mid-encode) is never picked up.
      final part = '${out.path}.part';
      await InstantFrame.exportJpeg(picturePath: path, note: item.note, outPath: part);
      await File(part).rename(out.path);
      return out.path;
    } catch (e) {
      // Never lose the share/save over the frame: fall back to the bare picture.
      debugPrint('Instant export failed: $e');
      return path;
    } finally {
      unawaited(Future<void>(() => _exporting.remove(key)));
    }
  }();
}

/// Instant-print exports being made right now (a share that arrives while
/// one is cooking waits for it rather than starting another).
final _exporting = <String, Future<String?>>{};
Future<void> _warmQueue = Future.value();

/// Makes [item]'s share file in the background (one at a time), so holding
/// a print on the corkboard brings the share sheet up straight away.
void warmShareExport(MediaItem item) {
  if (item.isVideo || item.outputPath == null || !CameraCatalog.byId(item.cameraId).isInstant) return;
  _warmQueue = _warmQueue.then((_) => exportPathFor(item)).then((_) {}, onError: (Object _) {});
}

/// Native share sheet (SMS, WhatsApp, Instagram Stories, AirDrop...).
///
/// [anchor] is the widget the sheet should point at on iPad / large screens.
Future<void> shareMedia(BuildContext anchor, MediaItem item) async {
  final box = anchor.findRenderObject() as RenderBox?;
  final origin = box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
  final path = await exportPathFor(item);
  if (path == null) return;
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(path, mimeType: item.isVideo ? 'video/mp4' : 'image/jpeg')],
      fileNameOverrides: [item.fileName.toLowerCase()],
      sharePositionOrigin: origin,
    ),
  );
}

/// Photo-library albums.
const filmAlbum = 'Darkroom Film';
const digitalAlbum = 'Darkroom';

/// Copies a file into the public photo library. Returns an error message or
/// null on success.
Future<String?> saveToGallery(MediaItem item, {required String album}) async {
  if (item.outputPath == null) return 'File is still processing';
  try {
    final path = await exportPathFor(item);
    if (path == null) return 'File is missing';
    final ok = await Gal.hasAccess(toAlbum: true) || await Gal.requestAccess(toAlbum: true);
    if (!ok) return 'Photo library access was denied';
    if (item.isVideo) {
      await Gal.putVideo(path, album: album);
    } else {
      await Gal.putImage(path, album: album);
    }
    return null;
  } on GalException catch (e) {
    return e.type.message;
  }
}

/// The name [item] goes into the photo library under (see [exportPathFor]:
/// instant prints are exported as their file name, the rest as stored).
String galleryNameFor(MediaItem item) {
  if (!item.isVideo && CameraCatalog.byId(item.cameraId).isInstant) return item.fileName;
  final p = item.outputPath ?? item.fileName;
  return p.substring(p.lastIndexOf(Platform.pathSeparator) + 1);
}

/// The saved items among [items] whose copy is no longer in [album] (the
/// user deleted it from the phone's photos); null when the phone won't
/// say. Saves from the last minute are left alone (the library may not
/// list them yet).
Future<List<MediaItem>?> missingFromGallery(Iterable<MediaItem> items, String album) async {
  final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
  final saved = items.where((m) => m.isSaved && m.savedAt!.isBefore(cutoff)).toList();
  if (saved.isEmpty) return const [];
  final names = await GalleryCheck.names(album);
  if (names == null) return null;
  return [
    for (final m in saved)
      if (!GalleryCheck.contains(names, galleryNameFor(m))) m,
  ];
}

/// Whether the albums can be looked in: on iOS that needs photo-library
/// access, which [explain] asks for once (true: go ahead and ask).
Future<bool> galleryCheckAllowed({
  required bool alreadyAsked,
  required void Function() markAsked,
  required Future<bool> Function() explain,
}) async {
  final access = await GalleryCheck.access();
  if (access == 'full' || access == 'limited') return true;
  if (access != 'undetermined' || alreadyAsked) return false;
  markAsked();
  if (!await explain()) return false;
  return GalleryCheck.request();
}

/// Saves [item] to the photo library and records it on the row ([moveToC]:
/// the digital file also leaves the SD card for "Local Disk (C:)").
/// Returns an error message or null.
Future<String?> keepMedia(
  MediaRepository repo,
  MediaItem item, {
  required String album,
  bool moveToC = false,
}) async {
  final err = await saveToGallery(item, album: album);
  if (err == null) await repo.markSaved([item.id], moveToC: moveToC);
  return err;
}

/// Deletes a media item's files and row.
Future<void> deleteMedia(MediaRepository repo, MediaItem item) async {
  for (final p in [item.outputPath, item.thumbPath, item.rawPath]) {
    if (p == null) continue;
    final f = File(p);
    if (await f.exists()) await f.delete();
  }
  await repo.delete(item.id);
}

/// Longest reel label (fits the label tape on the spool).
const maxReelLabel = 22;

/// The label written on a reel's tape: its file name without the extension.
String reelLabel(MediaItem item) {
  final dot = item.fileName.lastIndexOf('.');
  return dot > 0 ? item.fileName.substring(0, dot) : item.fileName;
}

/// Relabels a reel: the name on its tape and its file on disk (so shares and
/// saves carry the new name). Characters a file name can't hold are dropped;
/// a name already taken gets " 2", " 3"... Returns the label used, or null
/// when [label] had nothing usable in it.
Future<String?> renameReel(MediaRepository repo, MediaItem item, String label) async {
  var name = label.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (name.length > maxReelLabel) name = name.substring(0, maxReelLabel).trim();
  if (name.isEmpty) return null;
  if (name == reelLabel(item)) return name;
  final dot = item.fileName.lastIndexOf('.');
  final ext = dot > 0 ? item.fileName.substring(dot) : '.MP4';
  final old = item.outputPath;
  String? newPath;
  if (old != null && await File(old).exists()) {
    final dir = File(old).parent.path;
    var candidate = name;
    for (var n = 2; await File('$dir/$candidate$ext').exists(); n++) {
      candidate = '$name $n';
    }
    name = candidate;
    newPath = (await File(old).rename('$dir/$name$ext')).path;
  }
  await repo.rename(item.id, fileName: '$name$ext', outputPath: newPath);
  return name;
}

String formatBytes(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes bytes';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
}

String formatDuration(int? ms) {
  if (ms == null) return '';
  final d = Duration(milliseconds: ms);
  return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

/// Plain-text report for a shot that failed to process (to paste into a
/// message).
String errorReport(MediaItem item) {
  final spec = CameraCatalog.byId(item.cameraId);
  return [
    '${AppInfo.name} ${AppInfo.version} on ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    '${spec.name} (${item.cameraId}) · ${item.isVideo ? 'video' : 'photo'} · ${item.fileName}',
    'Taken ${item.capturedAt.toIso8601String()}',
    '',
    item.error ?? 'Unknown error',
  ].join('\n');
}
