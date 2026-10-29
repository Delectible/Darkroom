import 'package:darkroom/core/app_info.dart';
import 'package:darkroom/core/support/support.dart';
import 'package:flutter_test/flutter_test.dart';

/// Send feedback's email: room to write first, then the version and system
/// (no crash log here, so none is attached).
void main() {
  test('feedback email body', () {
    final body = Support.feedbackBody();
    expect(body.startsWith('\n\n\n---'), isTrue);
    expect(body, contains('Darkroom ${AppInfo.version}'));
    expect(body, isNot(contains('crash report')));
    expect(Support.privacyUrl, startsWith('https://'));
  });
}
