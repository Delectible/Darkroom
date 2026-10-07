import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// Tiny one-shot sound effects, played through the video_player plugin we
/// already ship (no extra native audio dependency). Mixes with whatever the
/// user is listening to instead of taking audio focus.
class Sfx {
  Sfx._(this._asset, {this.loop = false});

  /// The two camera bodies changing places (mode switch). Kept quiet.
  static final cameraSwap = Sfx._('assets/sfx/camera_swap.wav');

  /// The framed corkboard sliding in from the left (and back out).
  static final corkSwoosh = Sfx._('assets/sfx/cork_swoosh.wav');
  static final corkThud = Sfx._('assets/sfx/cork_thud.wav');

  // Projector deck piano keys: press (clunk) and release (lighter tick).
  static final keyDown = Sfx._('assets/sfx/deck_key_down.wav');
  static final keyUp = Sfx._('assets/sfx/deck_key_up.wav');

  // Shutters: quiet, so they never take over.
  static final shutterDigital = Sfx._('assets/sfx/shutter_digital.wav');
  static final shutterFilm = Sfx._('assets/sfx/shutter_film.wav');
  static final shutterRun = Sfx._('assets/sfx/shutter_run.wav');

  // Windows 98 (made by tool/sfx/make_sfx.py; all original sounds).
  static final w98Click = Sfx._('assets/sfx/w98_click.wav');
  static final w98Ding = Sfx._('assets/sfx/w98_ding.wav');
  static final w98Error = Sfx._('assets/sfx/w98_error.wav');
  static final w98Login = Sfx._('assets/sfx/w98_login.wav');
  static final w98Exit = Sfx._('assets/sfx/w98_exit.wav');
  static final w98Shutdown = Sfx._('assets/sfx/w98_shutdown.wav');
  static final crtOff = Sfx._('assets/sfx/crt_off.wav');

  static List<Sfx> get windows98 => [w98Click, w98Ding, w98Error, w98Exit, w98Login];

  // Games in Start > Run (tool/sfx/make_sfx.py game_* etc.).
  static final gameBop = Sfx._('assets/sfx/game_bop.wav');
  static final gameBlip = Sfx._('assets/sfx/game_blip.wav');
  static final gameLose = Sfx._('assets/sfx/game_lose.wav');
  static final gameWin = Sfx._('assets/sfx/game_win.wav');
  static final cardSnap = Sfx._('assets/sfx/card_snap.wav');
  static final cardRiffle = Sfx._('assets/sfx/card_riffle.wav');
  static final mineBoom = Sfx._('assets/sfx/mine_boom.wav');
  static final pinFlipper = Sfx._('assets/sfx/pin_flipper.wav');
  static final pinBumper = Sfx._('assets/sfx/pin_bumper.wav');
  static final pinChime = Sfx._('assets/sfx/pin_chime.wav');
  static final pinSling = Sfx._('assets/sfx/pin_sling.wav');
  static final pinDrop = Sfx._('assets/sfx/pin_drop.wav');
  static final pinWarp = Sfx._('assets/sfx/pin_warp.wav');
  static final pinLaunch = Sfx._('assets/sfx/pin_launch.wav');
  static final pinDrain = Sfx._('assets/sfx/pin_drain.wav');
  static final pinStart = Sfx._('assets/sfx/pin_start.wav');

  /// Digital bodies' zoom motor: loops while the zoom moves.
  static final zoomMotor = Sfx._('assets/sfx/zoom_motor.wav', loop: true);

  // Each sound's own level is baked into its .wav (tool/sfx/make_sfx.py
  // LEVELS); the player volume is only the user's slider ([level]).

  /// Settings > Sound effects slider, 0 (off) .. 1. The player volume is
  /// level², so the slider feels even (half way = a quarter of full scale).
  static double level = 0.5;

  final String _asset;

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
      await c.setVolume(level * level);
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
    if (level <= 0) return;
    final gen = ++_gen;
    unawaited(() async {
      await preload();
      final c = _c;
      if (c == null || gen != _gen) return;
      try {
        await c.setVolume(level * level); // the slider may have moved
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
