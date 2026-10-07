import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// Tiny one-shot sound effects, played through the video_player plugin we
/// already ship (no extra native audio dependency). Mixes with whatever the
/// user is listening to instead of taking audio focus.
class Sfx {
  Sfx._(this._asset, {this.volume = 0.5});

  /// The two camera bodies changing places (mode switch). Kept quiet.
  static final cameraSwap = Sfx._('assets/sfx/camera_swap.wav', volume: 0.15);

  // Projector deck piano keys: press (clunk) and release (lighter tick).
  static final keyDown = Sfx._('assets/sfx/deck_key_down.wav', volume: 0.55);
  static final keyUp = Sfx._('assets/sfx/deck_key_up.wav', volume: 0.45);

  // Windows 98 (made by tool/sfx/make_sfx.py; all original sounds).
  static final w98Click = Sfx._('assets/sfx/w98_click.wav', volume: 0.3);
  static final w98Ding = Sfx._('assets/sfx/w98_ding.wav', volume: 0.3);
  static final w98Error = Sfx._('assets/sfx/w98_error.wav', volume: 0.35);
  static final w98Exit = Sfx._('assets/sfx/w98_exit.wav', volume: 0.3);
  static final w98Shutdown = Sfx._('assets/sfx/w98_shutdown.wav', volume: 0.4);
  static final crtOff = Sfx._('assets/sfx/crt_off.wav', volume: 0.45);

  static List<Sfx> get windows98 => [w98Click, w98Ding, w98Error, w98Exit];

  final String _asset;
  final double volume;
  VideoPlayerController? _c;
  Future<void>? _ready;

  /// Loads ahead of time so the first play isn't late.
  Future<void> preload() => _ready ??= _init();

  Future<void> _init() async {
    final c = VideoPlayerController.asset(
      _asset,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    try {
      await c.initialize();
      await c.setVolume(volume);
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
