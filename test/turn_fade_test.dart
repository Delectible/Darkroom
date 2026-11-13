import 'package:darkroom/features/camera/presentation/turn_fade.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// A readout pinned by a corner (as the digital keys are) turning in place:
/// the new way round lands where it ends up and stays there, with no jump
/// when the old one has faded out.
void main() {
  Widget at(int q, Alignment corner) => MaterialApp(
    home: Stack(
      children: [
        Positioned(
          right: corner.x > 0 ? 6 : null,
          left: corner.x < 0 ? 6 : null,
          top: 4,
          child: TurnFade(
            quarterTurns: q,
            alignment: corner,
            child: const SizedBox(key: ValueKey('key'), width: 60, height: 20),
          ),
        ),
      ],
    ),
  );

  for (final corner in [Alignment.topRight, Alignment.topLeft]) {
    testWidgets('turns in place, pinned $corner', (tester) async {
      await tester.pumpWidget(at(0, corner));
      await tester.pumpWidget(at(1, corner));
      final rects = <Rect>[];
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        rects.add(tester.getRect(find.byKey(const ValueKey('key')).last));
      }
      await tester.pumpAndSettle();
      final end = tester.getRect(find.byKey(const ValueKey('key')));
      // (the new key is turned: its box is 20 x 60; the scale is round its centre)
      for (final r in rects) {
        expect((r.center - end.center).distance, lessThan(0.5), reason: '$r vs $end');
      }
    });
  }

  testWidgets('a cap in a row keeps its place', (tester) async {
    Widget row(int q) => MaterialApp(
      home: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              TurnFade(
                quarterTurns: q,
                child: SizedBox(key: ValueKey(i), width: 42, height: 60),
              ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(row(0));
    await tester.pumpWidget(row(1));
    await tester.pump(const Duration(milliseconds: 20));
    final during = tester.getRect(find.byKey(const ValueKey(2)).last);
    await tester.pumpAndSettle();
    final end = tester.getRect(find.byKey(const ValueKey(2)));
    expect((during.center - end.center).distance, lessThan(0.5), reason: '$during vs $end');
  });
}
