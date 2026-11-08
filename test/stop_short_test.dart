import 'package:darkroom/core/media/stop_short.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

/// A player that plays in fake time.
class _Fake extends VideoPlayerController {
  _Fake(this.clock, Duration duration) : super.networkUrl(Uri.parse('file:///clip.mp4')) {
    value = VideoPlayerValue(duration: duration, isInitialized: true);
  }

  final FakeAsync clock;
  Duration _from = Duration.zero;
  Duration _startedAt = Duration.zero;
  int pauses = 0;

  Duration get now => value.isPlaying ? _from + clock.elapsed - _startedAt : _from;

  @override
  Future<Duration?> get position async => now;

  @override
  Future<void> play() async {
    _startedAt = clock.elapsed;
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    _from = now;
    pauses++;
    value = value.copyWith(isPlaying: false, position: _from);
  }

  @override
  Future<void> seekTo(Duration to) async {
    _from = to;
    _startedAt = clock.elapsed;
  }
}

/// A clip is paused just short of its end, never run out (Android's player
/// reaching the end froze the app once: 2.2.0).
void main() {
  test('stops a moment before the end', () {
    fakeAsync((clock) {
      var ended = 0;
      final c = _Fake(clock, const Duration(seconds: 4));
      final end = StopShort(() => ended++);
      c.play();
      end.arm(c);
      clock.elapse(const Duration(milliseconds: 3800));
      expect(ended, 0);
      clock.elapse(const Duration(milliseconds: 100));
      expect(ended, 1);
      expect(c.value.isPlaying, isFalse);
      expect(c.now, lessThan(const Duration(seconds: 4)));
      expect(c.now, greaterThan(const Duration(milliseconds: 3800)));
    });
  });

  test('a seek back while playing: not stopped early', () {
    fakeAsync((clock) {
      var ended = 0;
      final c = _Fake(clock, const Duration(seconds: 4));
      final end = StopShort(() => ended++);
      c.play();
      end.arm(c);
      clock.elapse(const Duration(seconds: 2));
      c.seekTo(Duration.zero); // (no new arm)
      clock.elapse(const Duration(milliseconds: 1900));
      expect(ended, 0, reason: 'only 1.9 s into the clip again');
      clock.elapse(const Duration(seconds: 2));
      expect(ended, 1);
    });
  });

  test('a seek forward while playing: the listener catches it', () {
    fakeAsync((clock) {
      var ended = 0;
      final c = _Fake(clock, const Duration(seconds: 10));
      final end = StopShort(() => ended++);
      c.play();
      end.arm(c);
      clock.elapse(const Duration(milliseconds: 500));
      c.seekTo(const Duration(milliseconds: 9500));
      end.cancel(); // (the old timer is far off: as if the seek came from elsewhere)
      c.value = c.value.copyWith(position: c.now);
      end.watch(c);
      clock.elapse(const Duration(milliseconds: 400));
      expect(ended, 1);
      expect(c.now, lessThan(const Duration(seconds: 10)));
    });
  });

  test('paused before the end: nothing happens', () {
    fakeAsync((clock) {
      var ended = 0;
      final c = _Fake(clock, const Duration(seconds: 4));
      final end = StopShort(() => ended++);
      c.play();
      end.arm(c);
      clock.elapse(const Duration(seconds: 1));
      c.pause();
      clock.elapse(const Duration(seconds: 10));
      expect(ended, 0);
      expect(c.pauses, 1);
    });
  });
}
