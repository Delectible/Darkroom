import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import '../processing/capture_processor.dart';

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

  /// Reads the RAM and sets the limits from it.
  static Future<void> apply() async {
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('memory');
      final total = (m?['total'] as num?)?.toDouble();
      if (total == null || total <= 0) return;
      gb = total / (1024 * 1024 * 1024);
      final lowRam = m?['lowRam'] == true;
      CaptureProcessor.maxWorkers = workersFor(gb!, lowRam: lowRam);
      PaintingBinding.instance.imageCache.maximumSizeBytes = cacheBytesFor(gb!, lowRam: lowRam);
    } catch (_) {
      // unknown: the defaults stand
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
