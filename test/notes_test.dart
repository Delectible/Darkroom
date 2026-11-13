import 'package:darkroom/core/navigation.dart';
import 'package:darkroom/core/theme/note_box.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// A note a screen raises goes with that screen (not left over the camera
/// when the board slides away), and can be swiped away or closed with its ×.
void main() {
  Future<BuildContext> setUp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        home: const Scaffold(body: Text('camera')),
      ),
    );
    late BuildContext board;
    appNavigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (context) {
          board = context;
          return const Scaffold(body: Text('board'));
        },
      ),
    );
    await tester.pumpAndSettle();
    return board;
  }

  testWidgets('goes when its screen is left', (tester) async {
    final board = await setUp(tester);
    var byUser = true;
    Notes.show(
      'A print you saved is no longer on your phone.',
      action: 'Save again',
      context: board,
      onClosed: (u) => byUser = u,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('no longer on your phone'), findsOneWidget);
    appNavigatorKey.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(Notes.showing, isFalse, reason: 'gone as the board starts to slide away');
    expect(byUser, isFalse, reason: 'left behind, not waved off');
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('its × closes it, by the user', (tester) async {
    final board = await setUp(tester);
    var byUser = false;
    Notes.show('Saved prints missing.', action: 'Save again', context: board, onClosed: (u) => byUser = u);
    await tester.pumpAndSettle();
    await tester.tap(find.text('×'));
    await tester.pump();
    expect(Notes.showing, isFalse);
    expect(byUser, isTrue);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('swiped away', (tester) async {
    final board = await setUp(tester);
    var byUser = false;
    Notes.show('Saved prints missing.', action: 'Save again', context: board, onClosed: (u) => byUser = u);
    await tester.pumpAndSettle();
    await tester.fling(find.text('Saved prints missing.'), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Saved prints missing.'), findsNothing);
    expect(byUser, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 10));
  });
}
