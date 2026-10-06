import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/db/media_repository.dart';
import '../../../core/processing/instant_frame.dart';
import '../../cameras/domain/camera_catalog.dart';

/// The file that leaves the app for [item]: instant prints get their border
/// and handwritten note baked in; everything else is shared as stored.
Future<String?> exportPathFor(MediaItem item) async {
  final path = item.outputPath;
  if (path == null || !File(path).existsSync()) return null;
  if (item.isVideo || !CameraCatalog.byId(item.cameraId).isInstant) return path;
  try {
    return await InstantFrame.exportJpeg(
      picturePath: path,
      note: item.note,
      outPath: '${Directory.systemTemp.path}/instant_export/${item.fileName}',
    );
  } catch (e) {
    // Never lose the share/save over the frame: fall back to the bare picture.
    debugPrint('Instant export failed: $e');
    return path;
  }
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
