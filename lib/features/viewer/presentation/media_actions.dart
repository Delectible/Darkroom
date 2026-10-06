import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/db/media_repository.dart';

/// Native share sheet (SMS, WhatsApp, Instagram Stories, AirDrop...).
///
/// [anchor] is the widget the sheet should point at on iPad / large screens.
Future<void> shareMedia(BuildContext anchor, MediaItem item) async {
  final path = item.outputPath;
  if (path == null || !File(path).existsSync()) return;
  final box = anchor.findRenderObject() as RenderBox?;
  final origin = box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
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
  final path = item.outputPath;
  if (path == null) return 'File is still processing';
  try {
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
