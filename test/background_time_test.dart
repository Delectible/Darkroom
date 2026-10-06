import 'package:darkroom/core/background/background_time.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('holds iOS background time only while shots are processing', () async {
    const channel = MethodChannel('darkroom/background_test');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return null;
    });

    final pending = ValueNotifier<int>(0);
    final time = BackgroundTime(pending, channel: channel, enabled: true);
    pending.value = 1;
    pending.value = 2; // already held
    pending.value = 0;
    pending.value = 1;
    time.dispose(); // releases what it holds
    pending.value = 0; // no longer listening
    await Future<void>.delayed(Duration.zero);

    expect(calls, ['begin', 'end', 'begin', 'end']);
  });
}
