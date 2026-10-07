import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// Tiny one-shot sound effects, played through the video_player plugin we
/// already ship (no extra native audio dependency). Mixes with whatever the
/// user is listening to instead of taking audio focus.
class Sfx {
  Sfx._(this._asset, {this.volume = 0.25, this.loop = false});

  /// The two camera bodies changing places (mode switch). Kept quiet.
  static final cameraSwap = Sfx._('assets/sfx/camera_swap.wav', volume: 0.075);

  /// The framed corkboard sliding in from the left (and back out).
  static final corkSwoosh = Sfx._('assets/sfx/cork_swoosh.wav', volume: 0.12);

  // Projector deck piano keys: press (clunk) and release (lighter tick).
  static final keyDown = Sfx._('assets/sfx/deck_key_down.wav', volume: 0.275);
  static final keyUp = Sfx._('assets/sfx/deck_key_up.wav', volume: 0.225);

  // Shutters: quiet, so they never take over.
  static final shutterDigital = Sfx._('assets/sfx/shutter_digital.wav', volume: 0.12);
  static final shutterFilm = Sfx._('assets/sfx/shutter_film.wav', volume: 0.12);
  static final shutterRun = Sfx._('assets/sfx/shutter_run.wav', volume: 0.12);

  // Windows 98 (made by tool/sfx/make_sfx.py; all original sounds).
  static final w98Click = Sfx._('assets/sfx/w98_click.wav', volume: 0.15);
  static final w98Ding = Sfx._('assets/sfx/w98_ding.wav', volume: 0.15);
  static final w98Error = Sfx._('assets/sfx/w98_error.wav', volume: 0.175);
  static final w98Login = Sfx._('assets/sfx/w98_login.wav', volume: 0.15);
  static final w98Exit = Sfx._('assets/sfx/w98_exit.wav', volume: 0.15);
  static final w98Shutdown = Sfx._('assets/sfx/w98_shutdown.wav', volume: 0.2);
  static final crtOff = Sfx._('assets/sfx/crt_off.wav', volume: 0.225);

  static List<Sfx> get windows98 => [w98Click, w98Ding, w98Error, w98Exit, w98Login];

  // Games in Start > Run (tool/sfx/make_sfx.py game_* etc.).
  static final gameBop = Sfx._('assets/sfx/game_bop.wav', volume: 0.1);
  static final gameBlip = Sfx._('assets/sfx/game_blip.wav', volume: 0.1);
  static final gameLose = Sfx._('assets/sfx/game_lose.wav', volume: 0.12);
  static final gameWin = Sfx._('assets/sfx/game_win.wav', volume: 0.12);
  static final cardSnap = Sfx._('assets/sfx/card_snap.wav', volume: 0.15);
  static final cardRiffle = Sfx._('assets/sfx/card_riffle.wav', volume: 0.15);
  static final mineBoom = Sfx._('assets/sfx/mine_boom.wav', volume: 0.15);
  static final pinFlipper = Sfx._('assets/sfx/pin_flipper.wav', volume: 0.14);
  static final pinBumper = Sfx._('assets/sfx/pin_bumper.wav', volume: 0.1);
  static final pinChime = Sfx._('assets/sfx/pin_chime.wav', volume: 0.1);
  static final pinSling = Sfx._('assets/sfx/pin_sling.wav', volume: 0.1);
  static final pinDrop = Sfx._('assets/sfx/pin_drop.wav', volume: 0.12);
  static final pinWarp = Sfx._('assets/sfx/pin_warp.wav', volume: 0.1);
  static final pinLaunch = Sfx._('assets/sfx/pin_launch.wav', volume: 0.12);
  static final pinDrain = Sfx._('assets/sfx/pin_drain.wav', volume: 0.12);
  static final pinStart = Sfx._('assets/sfx/pin_start.wav', volume: 0.12);

  /// Digital bodies' zoom motor: loops while the zoom moves.
  static final zoomMotor = Sfx._('assets/sfx/zoom_motor.wav', volume: 0.06, loop: true);

  final String _asset;
  final double volume;

  /// Loops until [stop] (a motor, not a one-shot).
  final bool loop;
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
      if (loop) await c.setLooping(true);
      _c = c;
    } catch (e) {
      debugPrint('Sound $_asset unavailable: $e');
      await c.dispose();
    }
  }

  /// Bumped by every play / stop, so a stop that lands while a play is
  /// still loading wins.
  int _gen = 0;

  void play() {
    final gen = ++_gen;
    unawaited(() async {
      await preload();
      final c = _c;
      if (c == null || gen != _gen) return;
      try {
        await c.seekTo(Duration.zero);
        if (gen != _gen) return;
        await c.play();
      } catch (_) {
        // A missed click is never worth an error.
      }
    }());
  }

  /// Stops a looping sound (or cuts a one-shot short).
  void stop() {
    _gen++;
    final c = _c;
    if (c == null) return;
    unawaited(c.pause().catchError((Object _) {}));
  }
}
