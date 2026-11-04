import 'package:darkroom/features/camera/presentation/body_quality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('low-RAM 3D body: never drawn under 648 px wide, labels soften with it', () {
    // (enable() registers once per run: the numbers, worked out the same way)
    double base(double px) => px > 1080 ? 1080 / px : 1;
    double floor(double px) => (648 / (px * base(px))).clamp(0.6, 1.0);
    for (final (px, b, f) in [(720.0, 1.0, 0.9), (1080.0, 1.0, 0.6), (1440.0, 0.75, 0.6)]) {
      expect(base(px), closeTo(b, 1e-9));
      expect(floor(px), closeTo(f, 1e-9));
      expect(px * base(px) * floor(px), greaterThanOrEqualTo(648 - 1e-6));
    }
    BodyQuality.enable(1440);
    expect(BodyQuality.base, closeTo(0.75, 1e-9));
    expect(BodyQuality.floor, closeTo(0.6, 1e-9));
    BodyQuality.detail.value = 1;
    final at75 = BodyQuality.textBlur(3.5); // 75%: a hair soft
    expect(at75, lessThan(0.1));
    BodyQuality.detail.value = 0.6;
    expect(BodyQuality.textBlur(3.5), greaterThan(at75 * 3)); // 45%: soft, like the body
    BodyQuality.detail.value = 1;
    BodyQuality.base = 1;
    expect(BodyQuality.textBlur(3.5), 0); // full: crisp
  });
}
