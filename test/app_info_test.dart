import 'dart:io';

import 'package:darkroom/core/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

/// Help > About and error reports show AppInfo.version: keep it in step
/// with pubspec.yaml (it sat at 1.3.24 for five releases).
void main() {
  test('AppInfo.version matches pubspec.yaml', () {
    final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    final version = line.split(':')[1].trim().split('+').first;
    expect(AppInfo.version, version);
  });
}
