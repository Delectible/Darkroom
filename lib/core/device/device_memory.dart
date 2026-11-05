import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import '../processing/capture_processor.dart';
import '../performance/quality.dart';

/// The phone's RAM (native: MainActivity / AppDelegate, channel
/// `darkroom/device`), read once at launch to size the app's appetite:
/// how many prints develop side by side (each full-size one holds a few
/// hundred MB while it forms) and how many decoded pictures stay cached.
/// On a 3-4 GB phone four prints at once crowded out the system itself.
class DeviceMemory {
  const DeviceMemory._();

  static const _channel = MethodChannel('darkroom/device');

  /// Total RAM in GB, once read (null: unknown, tests).
  static double? gb;

  /// A phone with little RAM (about 4 GB or less, or Android's low-RAM flag).
  /// (Was 3 GB: a 3.3 GB tablet with ~0.5 GB free still got the full
  /// settings and dropped most frames while swiping; 2.0.15.)
  static bool low = false;

  /// The slowest phones (about 2 GB, or 3 GB with 4 cores or fewer): a
  /// first start begins with Fancy graphics off (onboarding_screen.dart).
  static bool lowest = false;

  /// Completes once the RAM has been read (or couldn't be); at once if it
  /// isn't being read (tests).
  static Future<void> get ready => _started ? _ready.future : Future<void>.value();
  static final _ready = Completer<void>();
  static bool _started = false;

  /// The "low" cutoff, GB (4 GB phones report about 3.6-3.8).
  static const lowGb = 4.2;

  /// Reads the RAM and sets the limits from it.
  static Future<void> apply() async {
    _started = true;
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('memory');
      final total = (m?['total'] as num?)?.toDouble();
      if (total == null || total <= 0) return;
      gb = total / (1024 * 1024 * 1024);
      final lowRam = m?['lowRam'] == true;
      low = lowRam || gb! <= lowGb;
      lowest = gb! <= 2.2 || (gb! <= 3.2 && Platform.numberOfProcessors <= 4);
      // A first start begins a step or two down the quality manager's
      // ladder (before the 3D loads: it reads the steps).
      Quality.lowMemory(low: low, lowest: lowest);
      CaptureProcessor.maxWorkers = workersFor(gb!, lowRam: lowRam);
      PaintingBinding.instance.imageCache.maximumSizeBytes = cacheBytesFor(gb!, lowRam: lowRam);
    } catch (_) {
      // unknown: the defaults stand
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  /// Prints developing at once for [gb] of RAM (never more than the cores
  /// allow, see [CaptureProcessor.coreWorkers]).
  static int workersFor(double gb, {bool lowRam = false}) {
    final byRam = lowRam || gb <= 3.2
        ? 1
        : gb <= 4.5
        ? 2
        : gb <= 6.5
        ? 3
        : 4;
    return byRam < CaptureProcessor.coreWorkers ? byRam : CaptureProcessor.coreWorkers;
  }

  /// Decoded-image cache (Flutter's default is 100 MB).
  static int cacheBytesFor(double gb, {bool lowRam = false}) =>
      (lowRam || gb <= 3.2 ? 40 : (gb <= 4.5 ? 64 : 100)) << 20;
}
