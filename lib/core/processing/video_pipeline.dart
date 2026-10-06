import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'isolate_jobs.dart';
import 'video_plan.dart';

export 'video_plan.dart' show VideoJob;

class VideoResult {
  const VideoResult({required this.width, required this.height, required this.bytes});

  final int width;
  final int height;
  final int bytes;
}

class VideoProcessingException implements Exception {
  VideoProcessingException(this.message, [this.log]);

  final String message;
  final String? log;

  @override
  String toString() => log == null ? message : '$message\n$log';
}

/// FFmpeg-based video renderer. FFmpeg runs on native worker threads, so the
/// Dart side only awaits; OSD frame rendering runs in an isolate.
class VideoPipeline {
  const VideoPipeline._();

  /// MPEG-4 Part 2 (Simple Profile) in MP4: software-encoded, built into every
  /// FFmpegKit variant, decodes on every Android/iOS device and imports into
  /// the iOS Photos library at camcorder resolutions. Hardware H.264 encoders
  /// (MediaCodec) were dropped: on some devices they stall at end-of-stream,
  /// which left clips "processing" forever.
  static List<String> _encoder(int kbps) => [
    '-c:v', 'mpeg4', '-b:v', '${kbps}k', '-maxrate', '${(kbps * 1.5).round()}k', //
    '-bufsize', '${kbps * 2}k', '-vtag', 'mp4v',
  ];

  static Future<VideoResult> run(VideoJob job) async {
    final work = Directory(job.workDir);
    await work.create(recursive: true);
    final seconds = (job.durationMs / 1000).ceil();
    // Generous ceiling; a clip that takes longer than this is stuck, not slow.
    final encodeTimeout = Duration(seconds: 90 + seconds * 12);
    try {
      // 1. Oriented dimensions: grab one (autorotated) frame.
      final probe = p.join(work.path, 'probe.jpg');
      await _ffmpeg(['-y', '-i', job.rawPath, '-frames:v', '1', '-q:v', '4', probe]);
      final info = img.JpegDecoder().startDecode(await File(probe).readAsBytes());
      if (info == null || info.width == 0) {
        throw VideoProcessingException('Could not read clip dimensions');
      }

      // 2. Crop/filtergraph/OSD frames (pure Dart, off the UI isolate).
      final plan = await planVideoInIsolate(job, info.width, info.height);

      // 3. Encode; fat-pixel looks get a nearest-neighbour upscale pass.
      await _ffmpeg([
        ...plan.mainInputArgs,
        ..._encoder(plan.bitrateKbps),
        ...plan.mainOutputArgs,
      ], timeout: encodeTimeout);
      if (plan.upscale > 1) {
        await _ffmpeg([
          ...plan.upscaleInputArgs(),
          ..._encoder(1500),
          '-movflags',
          '+faststart',
          job.outputPath,
        ], timeout: encodeTimeout);
      }

      // 4. Thumbnail from the *processed* clip.
      final thumbOk = await _ffmpeg([
        '-y',
        '-ss',
        '0.3',
        '-i',
        job.outputPath,
        '-frames:v',
        '1',
        '-vf',
        'scale=480:-2',
        job.thumbPath,
      ], throwOnError: false);
      if (!thumbOk || !File(job.thumbPath).existsSync()) {
        await _ffmpeg(['-y', '-i', job.outputPath, '-frames:v', '1', '-vf', 'scale=480:-2', job.thumbPath]);
      }

      final bytes = await File(job.outputPath).length();
      return VideoResult(width: plan.finalW, height: plan.finalH, bytes: bytes);
    } finally {
      if (await work.exists()) {
        await work.delete(recursive: true);
      }
    }
  }

  /// Runs FFmpeg with an argument list (no shell-quoting pitfalls with
  /// filtergraphs).
  ///
  /// Uses FFmpegKit's *synchronous* execute: the native side runs FFmpeg on
  /// its own worker thread and answers the method call when done, so nothing
  /// blocks Flutter's threads and we don't depend on the asynchronous
  /// completion event (which never arrived on some devices, leaving clips
  /// stuck in "processing"). A timeout cancels a hung session.
  static Future<bool> _ffmpeg(
    List<String> args, {
    bool throwOnError = true,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final session = await FFmpegSession.create(args);
    try {
      await FFmpegKitConfig.ffmpegExecute(session).timeout(timeout);
    } on TimeoutException {
      await FFmpegKit.cancel(session.getSessionId());
      if (!throwOnError) return false;
      throw VideoProcessingException('FFmpeg timed out after ${timeout.inSeconds}s');
    }
    final rc = await session.getReturnCode();
    if (ReturnCode.isSuccess(rc)) return true;
    final log = await session.getAllLogsAsString();
    if (kDebugMode) debugPrint('ffmpeg failed (${rc?.getValue()}): ${args.join(' ')}\n$log');
    if (!throwOnError) return false;
    throw VideoProcessingException('FFmpeg exited with ${rc?.getValue()}', _tail(log));
  }

  static String? _tail(String? log) {
    if (log == null) return null;
    final lines = log.trim().split('\n');
    return lines.sublist(lines.length > 6 ? lines.length - 6 : 0).join('\n');
  }
}
