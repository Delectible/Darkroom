import 'dart:async';

import 'package:video_player/video_player.dart';

/// Stops a clip a moment before its last frame instead of letting it run
/// out. Android's player reaching the end of a file is where things went
/// wrong: it sat in its "ended" state (2.1.7), and once the whole app froze
/// black as a clip finished in the Win98 player, then stopped responding
/// (2.2.0). Paused [margin] short, the decoder never gets there; nobody
/// misses the last few frames.
class StopShort {
  StopShort(this.onEnd);

  /// The clip has stopped at its end (paused [margin] short of it).
  final void Function() onEnd;

  static const margin = Duration(milliseconds: 150);

  Timer? _timer;
  VideoPlayerController? _on;

  /// After a play (or a seek while playing): times the stop.
  Future<void> arm(VideoPlayerController c) async {
    _on = c;
    _timer?.cancel();
    _timer = null;
    final d = c.value.duration;
    if (d <= margin) return;
    final at = await c.position ?? c.value.position;
    if (!identical(_on, c)) return;
    final left = d - margin - at;
    _timer = Timer(left.isNegative ? Duration.zero : left, () => unawaited(_fire(c)));
  }

  Future<void> _fire(VideoPlayerController c) async {
    _timer = null;
    if (!identical(_on, c) || !c.value.isPlaying) return;
    final at = await c.position ?? c.value.position;
    final left = c.value.duration - margin - at;
    // (a stall or a seek back on the way: not there yet)
    if (left > const Duration(milliseconds: 60)) {
      _timer = Timer(left, () => unawaited(_fire(c)));
      return;
    }
    await c.pause();
    if (identical(_on, c)) onEnd();
  }

  /// From the player's listener: a seek forward while playing lands near
  /// the end without a new [arm].
  void watch(VideoPlayerController c) {
    final v = c.value;
    if (_timer != null || !v.isPlaying || v.duration <= margin) return;
    if (v.duration - v.position < const Duration(seconds: 1)) unawaited(arm(c));
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _on = null;
  }
}
