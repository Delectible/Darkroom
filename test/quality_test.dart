import 'package:darkroom/core/performance/quality.dart';
import 'package:flutter_test/flutter_test.dart';

/// [n] moving frames [gapMs] apart with these UI / GPU times.
List<({double ui, double gpu, int vsync})> frames(int n, double gapMs, double ui, double gpu) => [
  for (var i = 0; i < n; i++) (ui: ui, gpu: gpu, vsync: (i * gapMs * 1000).round()),
];

void main() {
  test('a phone held to 60 Hz by Android, its frames cheap, is not blamed', () {
    // 120 Hz screen, frames every 16.7 ms (a Pixel with its camera running),
    // each taking 5 ms: the rate is Android's, not the app's.
    final v = Quality.verdict(frames(48, 16.67, 5, 5), 120)!;
    expect(v.bad, isFalse);
    expect(v.hz.round(), 60);
    expect(v.drop, lessThan(0.05));
  });

  test('a steady 60 on a 120 Hz screen is fine, even when frames are not cheap', () {
    // The Pixel with its camera on: 60 a second, 9 ms of work each. It was
    // judged against 120 Hz and stepped all the way down.
    final v = Quality.verdict(frames(48, 16.67, 9, 9), 120)!;
    expect(v.bad, isFalse);
    expect(v.drop, lessThan(0.05));
  });

  test('stuttering below 60 with real work is bad', () {
    // 120 Hz screen, frames 25 ms apart (40 a second), 14 ms of GPU work each.
    final fs = [for (var i = 0; i < 48; i++) (ui: 6.0, gpu: 14.0, vsync: (i * 25.0 * 1000).round())];
    final v = Quality.verdict(fs, 120)!;
    expect(v.bad, isTrue);
  });

  test('a phone whose graphics chip is the limit steps the GPU ladder', () {
    // 90 Hz screen, frames 33 ms apart, the GPU taking 30 ms each.
    final v = Quality.verdict(frames(48, 33.3, 2, 30), 90)!;
    expect(v.bad, isTrue);
    expect(v.gpuBound, isTrue);
  });

  test('a phone with room to spare is clean', () {
    final v = Quality.verdict(frames(48, 8.33, 3, 3.5), 120)!;
    expect(v.clean, isTrue);
    expect(v.bad, isFalse);
  });

  test('the ladders: GPU first steps, back up in reverse, reset', () {
    Quality.reset();
    expect(Quality.summary, 'full');
    Quality.stepDown(gpuSide: true);
    Quality.stepDown(gpuSide: true);
    expect(Quality.fxaa.value, isTrue);
    expect(Quality.noHalation.value, isTrue);
    expect(Quality.scale3d.value, 1);
    Quality.stepDown(gpuSide: false);
    expect(Quality.lightStrap.value, isTrue);
    Quality.stepUp(); // the UI step goes first (the last taken)
    expect(Quality.lightStrap.value, isFalse);
    expect(Quality.noHalation.value, isTrue);
    for (var i = 0; i < 10; i++) {
      Quality.stepDown(gpuSide: true);
    }
    expect(Quality.scale3d.value, 0.7);
    expect(Quality.cap60.value, isTrue);
    Quality.reset();
    expect(Quality.cap60.value, isFalse);
    expect(Quality.summary, 'full');
  });

  test('every step on both ladders taken: the slow prompt may ask', () {
    Quality.reset();
    expect(Quality.exhausted, isFalse);
    for (var i = 0; i < 12; i++) {
      Quality.stepDown(gpuSide: true);
    }
    expect(Quality.exhausted, isTrue);
    Quality.reset();
    expect(Quality.exhausted, isFalse);
  });
}
