import 'package:darkroom/features/sd_card/presentation/win98/win98_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Win98 windows close by shrinking back where they came from (the window
/// itself, fading), not by vanishing; and keep their state while opening.
void main() {
  testWidgets('a closing window shrinks towards where it opened', (tester) async {
    final a = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(milliseconds: 200),
      value: 1,
    );
    addTearDown(a.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Win98ZoomTransition(
          animation: a,
          origin: const Offset(40, 40),
          child: const Center(child: Text('window')),
        ),
      ),
    );
    final open = tester.getRect(find.text('window'));
    a.reverse();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // still there, smaller and moving to the file
    expect(find.text('window'), findsOneWidget);
    final mid = tester.getRect(find.text('window'));
    expect(mid.width, lessThan(open.width));
    expect(mid.center.dx, lessThan(open.center.dx));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('window'), findsNothing);
  });
}
