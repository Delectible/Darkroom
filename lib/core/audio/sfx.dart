import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// Tiny one-shot sound effects, played through the video_player plugin we
/// already ship (no extra native audio dependency). Mixes with whatever the
/// user is listening to instead of taking audio focus.
class Sfx {
  Sfx._(this._asset);

  /// The two camera bodies changing places (mode switch).
  static final cameraSwap = Sfx._('assets/sfx/camera_swap.wav');

  final String _asset;
  VideoPlayerController? _c;
  Future<void>? _ready;

  /// Loads ahead of time so the first play isn't late.
  Future<void> preload() => _ready ??= _init();

  Future<void> _init() async {
    final c = VideoPlayerController.asset(_asset, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    try {
      await c.initialize();
      await c.setVolume(0.5);
      _c = c;
    } catch (e) {
      debugPrint('Sound $_asset unavailable: $e');
      await c.dispose();
    }
  }

  void play() {
    unawaited(() async {
      await preload();
      final c = _c;
      if (c == null) return;
      try {
        await c.seekTo(Duration.zero);
        await c.play();
      } catch (_) {
        // A missed click is never worth an error.
      }
    }());
  }
}
