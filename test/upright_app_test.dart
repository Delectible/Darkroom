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

class _Turnable extends PhysicalOrientationNotifier {
  @override
  DeviceOrientation build() => DeviceOrientation.portraitUp;

  void turn(DeviceOrientation o) => state = o;
}

/// Landscape screens turn the app with the phone, only when auto-rotate is
/// on: laid out in landscape from the moment they start sliding in (no pop
/// when Android then turns), really rotated once they've arrived, back to
/// portrait as they slide out; the camera below keeps its portrait layout.
void main() {
  Future<List<List<dynamic>>> setUp(WidgetTester tester, bool autoRotate) async {
    final asked = <List<dynamic>>[];
    final m = tester.binding.defaultBinaryMessenger;
    m.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') asked.add(call.arguments as List<dynamic>);
      return null;
    });
    m.setMockMethodCallHandler(const MethodChannel('darkroom/rotation'), (call) async => autoRotate);
    addTearDown(() {
      m.setMockMethodCallHandler(SystemChannels.platform, null);
      m.setMockMethodCallHandler(const MethodChannel('darkroom/rotation'), null);
    });
    await AutoRotate.refresh();
    // a phone held upright (the default test surface is landscape)
    tester.view.physicalSize = const Size(1236, 2745);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    return asked;
  }

  Size? cameraSaw, boardSaw;
  final nav = GlobalKey<NavigatorState>();

  Future<void> pumpApp(WidgetTester tester, {bool turnable = false}) => tester.pumpWidget(
    ProviderScope(
      overrides: [physicalOrientationProvider.overrideWith(turnable ? _Turnable.new : _Held.new)],
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

  void pushBoard() => unawaited(
    nav.currentState!.push(
      PageRouteBuilder<void>(
        settings: UprightApp.landscape,
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, _, _) => UprightPage(
          child: Builder(
            builder: (context) {
              boardSaw = MediaQuery.sizeOf(context);
              return const Text('board');
            },
          ),
        ),
        transitionsBuilder: (_, a, _, child) => SlideTransition(
          position: Tween(begin: const Offset(-1, 0), end: Offset.zero).animate(a),
          child: child,
        ),
      ),
    ),
  );

  testWidgets('auto-rotate on: turns once arrived, laid out landscape all along', (tester) async {
    final asked = await setUp(tester, true);
    await pumpApp(tester);
    pushBoard();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(asked, isEmpty, reason: 'turns only once the screen has slid in');
    expect(boardSaw!.width, greaterThan(boardSaw!.height), reason: 'already laid out in landscape');
    await tester.pumpAndSettle();
    expect(asked.last, ['DeviceOrientation.landscapeLeft']);
    expect(
      ProviderScope.containerOf(nav.currentContext!).read(uprightOrientationProvider),
      DeviceOrientation.landscapeLeft,
    );

    // The phone really turned: the camera underneath still lays out upright,
    // the board is landscape without being turned again.
    tester.view.physicalSize = const Size(2745, 1236);
    await tester.pump();
    expect(cameraSaw!.height, greaterThan(cameraSaw!.width));
    expect(boardSaw!.width, greaterThan(boardSaw!.height));

    nav.currentState!.pop();
    await tester.pump();
    expect(asked.last, ['DeviceOrientation.portraitUp'], reason: 'back to portrait as it slides out');
    await tester.pumpAndSettle();
  });

  testWidgets('turning the phone on a page: fades out, turns, fades back in', (tester) async {
    final asked = await setUp(tester, true);
    await pumpApp(tester, turnable: true);
    pushBoard();
    await tester.pumpAndSettle();
    expect(boardSaw!.height, greaterThan(boardSaw!.width));

    final phone =
        ProviderScope.containerOf(nav.currentContext!).read(physicalOrientationProvider.notifier)
            as _Turnable;
    phone.turn(DeviceOrientation.landscapeLeft);
    await tester.pump();
    expect(UprightApp.veil.value, 0, reason: 'fading out');
    expect(boardSaw!.height, greaterThan(boardSaw!.width), reason: 'keeps its layout while it fades');
    expect(asked.where((a) => a.contains('DeviceOrientation.landscapeLeft')), isEmpty);

    await tester.pump(UprightPage.fade);
    expect(asked.last, ['DeviceOrientation.landscapeLeft'], reason: 'turns once faded out');
    tester.view.physicalSize = const Size(2745, 1236);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(UprightApp.veil.value, 1, reason: 'fades back in once turned');
    expect(boardSaw!.width, greaterThan(boardSaw!.height));
    nav.currentState!.pop();
    await tester.pumpAndSettle();
  });

  testWidgets('auto-rotate off: nothing turns', (tester) async {
    final asked = await setUp(tester, false);
    await pumpApp(tester);
    pushBoard();
    await tester.pumpAndSettle();
    expect(asked.where((a) => a.contains('DeviceOrientation.landscapeLeft')), isEmpty);
    expect(boardSaw!.height, greaterThan(boardSaw!.width), reason: 'stays portrait');
    expect(
      ProviderScope.containerOf(nav.currentContext!).read(uprightOrientationProvider),
      DeviceOrientation.portraitUp,
      reason: 'icons, labels, the carousel stay put too',
    );
    nav.currentState!.pop();
    await tester.pumpAndSettle();
  });
}
