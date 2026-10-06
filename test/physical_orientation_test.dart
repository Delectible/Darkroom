import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:darkroom/core/device/physical_orientation.dart';

void main() {
  const up = DeviceOrientation.portraitUp;
  DeviceOrientation c(double x, double y, double z, [DeviceOrientation cur = up]) =>
      PhysicalOrientationNotifier.classify(x, y, z, cur);

  test('gravity picks the orientation', () {
    expect(c(0, 9.8, 0), DeviceOrientation.portraitUp);
    expect(c(9.8, 0, 0), DeviceOrientation.landscapeLeft); // turned counter-clockwise
    expect(c(-9.8, 0, 0), DeviceOrientation.landscapeRight);
    expect(c(0, -9.8, 0), DeviceOrientation.portraitDown);
  });

  test('flat on a table or in-between keeps the last orientation', () {
    expect(c(0, 0.5, 9.7, DeviceOrientation.landscapeLeft), DeviceOrientation.landscapeLeft);
    expect(c(6.9, 6.9, 0, DeviceOrientation.landscapeLeft), DeviceOrientation.landscapeLeft); // 45 degrees
  });

  test('capture rotation matches the classic JPEG orientation rule', () {
    expect(uprightQuarterTurns(DeviceOrientation.landscapeLeft), 1);
    expect(uprightQuarterTurns(DeviceOrientation.landscapeRight), 3);
  });
}
