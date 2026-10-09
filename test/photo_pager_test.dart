import 'package:darkroom/features/viewer/presentation/zoomable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The film print viewer's touch handling: swipes page, pinches zoom (even
/// when the first finger slid sideways first), double tap zooms in and out,
/// double tap and slide zooms gradually, a swipe up or down puts it away.
void main() {
  late PageController pages;
  late int page, dismissed, taps;
  final key = GlobalKey<PhotoPagerState>();

  Future<void> pump(WidgetTester tester) async {
    pages = PageController();
    page = 0;
    dismissed = 0;
    taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhotoPager(
            key: key,
            controller: pages,
            itemCount: 3,
            onPageChanged: (i) => page = i,
            onDismiss: () => dismissed++,
            onTap: (_) => taps++,
            itemBuilder: (_, i) => ColoredBox(
              color: Colors.primaries[i],
              child: Center(child: Text('$i')),
            ),
          ),
        ),
      ),
    );
  }

  double scale() => key.currentState!.scale;
  final centre = const Offset(400, 300);

  testWidgets('a sideways swipe turns the page', (tester) async {
    await pump(tester);
    await tester.flingFrom(centre, const Offset(-300, 0), 1500);
    await tester.pumpAndSettle();
    expect(page, 1);
    expect(dismissed, 0);
  });

  testWidgets('a small sideways drift does not turn the page', (tester) async {
    await pump(tester);
    final g = await tester.startGesture(centre);
    await g.moveBy(const Offset(-15, 0));
    await g.up();
    await tester.pumpAndSettle();
    expect(page, 0);
  });

  testWidgets('a swipe up or down puts the photo away', (tester) async {
    await pump(tester);
    await tester.flingFrom(centre, const Offset(0, 260), 1200);
    await tester.pumpAndSettle();
    expect(dismissed, 1);
    await tester.flingFrom(centre, const Offset(0, -260), 1200);
    await tester.pumpAndSettle();
    expect(dismissed, 2);
    expect(page, 0);
  });

  testWidgets('a pinch zooms even if the first finger slid sideways first', (tester) async {
    await pump(tester);
    final a = await tester.startGesture(centre);
    await a.moveBy(const Offset(-40, 0));
    await tester.pump();
    final b = await tester.startGesture(centre + const Offset(60, 0));
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(-10, 0));
      await b.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(page, 0);
    expect(scale(), greaterThan(1.5));
    // Zoomed in, one finger pans instead of paging.
    await tester.dragFrom(centre, const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(page, 0);
  });

  testWidgets('double tap zooms in, again back out', (tester) async {
    await pump(tester);
    await tester.tapAt(centre);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(centre);
    await tester.pumpAndSettle();
    expect(scale(), closeTo(2.5, 0.01));
    await tester.tapAt(centre);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(centre);
    await tester.pumpAndSettle();
    expect(scale(), closeTo(1, 0.01));
    expect(taps, 0, reason: 'a double tap is not two taps');
  });

  testWidgets('double tap and slide zooms gradually', (tester) async {
    await pump(tester);
    await tester.tapAt(centre);
    await tester.pump(const Duration(milliseconds: 80));
    final g = await tester.startGesture(centre);
    var last = 1.0;
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(0, 20));
      await tester.pump();
      expect(scale(), greaterThanOrEqualTo(last));
      last = scale();
    }
    expect(last, greaterThan(1.3));
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(0, -20));
      await tester.pump();
    }
    expect(scale(), lessThan(last));
    await g.up();
    await tester.pumpAndSettle();
    expect(dismissed, 0);
    expect(page, 0);
  });

  testWidgets('a single tap is reported once the double-tap window passes', (tester) async {
    await pump(tester);
    await tester.tapAt(centre);
    expect(taps, 0);
    await tester.pump(const Duration(milliseconds: 350));
    expect(taps, 1);
  });
}
