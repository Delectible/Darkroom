import 'package:darkroom/core/performance/quality.dart';
import 'package:darkroom/features/camera/application/camera_ui_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every key the app reads at start is in the preferences allowlist: one
/// that isn't throws, and the app fails to start (2.1.10: the quality
/// manager's new keys).
void main() {
  test('the quality keys are allowed', () {
    expect(PrefKeys.all, containsAll(Quality.keys));
    expect(PrefKeys.all, containsAll(Quality.oldKeys));
  });
}
