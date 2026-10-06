import 'package:darkroom/core/device/system_gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Swipes that start in the phone's back strips (sides) or notification
/// strip (top) are left to the phone, except where the app was given the
/// edge.
void main() {
  testWidgets('edge strips belong to the phone', (tester) async {
    tester.view.physicalSize = const Size(1280, 2856);
    tester.view.devicePixelRatio = 3.1;
    tester.view.padding = const FakeViewPadding(top: 40 * 3.1);
    tester.view.systemGestureInsets = const FakeViewPadding(left: 30 * 3.1, right: 30 * 3.1);
    addTearDown(tester.view.reset);
    late BuildContext ctx;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          ctx = c;
          return const SizedBox.expand();
        },
      ),
    );
    final w = 1280 / 3.1;
    expect(SystemGestureZones.startsInEdge(ctx, const Offset(20, 400)), isTrue); // back, left
    expect(SystemGestureZones.startsInEdge(ctx, Offset(w - 20, 400)), isTrue); // back, right
    expect(SystemGestureZones.startsInEdge(ctx, const Offset(200, 30)), isTrue); // shade
    expect(SystemGestureZones.startsInEdge(ctx, const Offset(200, 400)), isFalse);
    final peek = Rect.fromLTWH(w - 48, 350, 48, 190);
    expect(SystemGestureZones.startsInEdge(ctx, Offset(w - 20, 400), allowed: [peek]), isFalse);
  });
}
