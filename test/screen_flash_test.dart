import 'package:darkroom/core/device/screen_flash.dart';
import 'package:flutter_test/flutter_test.dart';

/// The front flash: the screen is lit before the shot is taken (long enough
/// for the camera to settle on the lit face), and goes out after it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('lit through the shot, out after', () async {
    final clock = Stopwatch()..start();
    double? during;
    final r = await ScreenFlash.during(() async {
      during = ScreenFlash.light.value;
      return clock.elapsed;
    });
    expect(during, 1);
    expect(r, greaterThanOrEqualTo(ScreenFlash.settle));
    expect(ScreenFlash.light.value, 0);
  });

  test('out again when the shot fails', () async {
    await expectLater(ScreenFlash.during<void>(() async => throw StateError('no')), throwsStateError);
    expect(ScreenFlash.light.value, 0);
  });
}
