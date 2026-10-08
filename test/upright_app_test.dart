import 'dart:async';

import 'package:darkroom/core/device/physical_orientation.dart';
import 'package:darkroom/core/device/upright.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Held extends PhysicalOrientationNotifier {
  @override
  DeviceOrientation build() => DeviceOrientation.landscapeLeft;
}

/// Landscape screens really rotate the app once they've slid in (the
/// camera below keeps its portrait layout), and it goes back to portrait
/// as they slide out.
void main() {
  testWidgets('landscape screens rotate the app; the camera stays portrait', (tester) async {
    final asked = <List<dynamic>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') asked.add(call.arguments as List<dynamic>);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    Size? cameraSaw;
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [physicalOrientationProvider.overrideWith(_Held.new)],
        child: MaterialApp(
          navigatorKey: nav,
          navigatorObservers: [UprightApp.observer],
          builder: (context, child) => UprightApp(child: child!),
          home: PortraitLock(
            child: Builder(
              builder: (context) {
                cameraSaw = MediaQuery.sizeOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    unawaited(
      nav.currentState!.push(
        PageRouteBuilder<void>(
          settings: UprightApp.landscape,
          transitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (_, _, _) => const Text('board'),
          transitionsBuilder: (_, a, _, child) => SlideTransition(
            position: Tween(begin: const Offset(-1, 0), end: Offset.zero).animate(a),
            child: child,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(asked, isEmpty, reason: 'turns only once the screen has slid in');
    await tester.pumpAndSettle();
    expect(asked.last, ['DeviceOrientation.landscapeLeft']);

    // The phone really turned: the camera underneath still lays out upright.
    tester.view.physicalSize = Size(tester.view.physicalSize.height, tester.view.physicalSize.width);
    addTearDown(tester.view.reset);
    await tester.pump();
    expect(cameraSaw!.height, greaterThan(cameraSaw!.width));

    nav.currentState!.pop();
    await tester.pump();
    expect(asked.last, ['DeviceOrientation.portraitUp'], reason: 'back to portrait as it slides out');
    await tester.pumpAndSettle();
  });
}
