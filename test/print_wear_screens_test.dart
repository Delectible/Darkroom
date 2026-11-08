import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/processing/instant_frame.dart';
import 'package:darkroom/features/corkboard/presentation/instant_print.dart';
import 'package:darkroom/core/processing/paper_wear.dart';
import 'package:darkroom/features/corkboard/presentation/print_frames.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

class _Sunset extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final r = Offset.zero & s;
    c.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2C3A62), Color(0xFFB0687A), Color(0xFFF0A868), Color(0xFF1D2230)],
          stops: [0, 0.42, 0.62, 0.63],
        ).createShader(r),
    );
    c.drawCircle(
      Offset(s.width * 0.64, s.height * 0.56),
      s.height * 0.1,
      Paint()..color = const Color(0xFFFFE2B0),
    );
    c.drawRect(
      Rect.fromLTWH(s.width * 0.2, s.height * 0.45, s.width * 0.02, s.height * 0.3),
      Paint()..color = const Color(0xFF12151D),
    );
    c.drawCircle(
      Offset(s.width * 0.21, s.height * 0.42),
      s.height * 0.1,
      Paint()..color = const Color(0xFF12151D),
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

void main() {
  // Paper wear options (2.2.2 mock): now / new / handled, and new frames.
  testWidgets('print paper wear and new frames', (tester) async {
    await tester.runAsync(() => PaperTexture.image());
    tester.view.physicalSize = const Size(1200, 1820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    final pic = CustomPaint(painter: _Sunset(), size: Size.infinite);
    Widget instant(int level) {
      final print = InstantPrint(picture: pic, note: 'Lake, July', shadow: level == 0);
      if (level == 0) return print;
      return AspectRatio(
        aspectRatio: InstantFrame.aspect,
        child: WornSheet(
          wear: PaperWear(seed: 11 + level, level: level.toDouble()),
          window: (size) => InstantFrame.pictureRect(size.width / (1 + 2 * InstantFrame.side)),
          child: print,
        ),
      );
    }

    Widget classic(int level) {
      final print = AspectRatio(
        aspectRatio: 2 / 3,
        child: FramedPrint(
          frame: PrintFrame.classic,
          photo: pic,
          shadow: level == 0,
          shadows: level == 0
              ? const [BoxShadow(color: Colors.black45, blurRadius: 7, offset: Offset(3, 5))]
              : null,
        ),
      );
      if (level == 0) return print;
      return AspectRatio(
        aspectRatio: 2 / 3,
        child: WornSheet(
          wear: PaperWear(seed: 5 + level, level: level.toDouble()),
          child: FramedPrint(frame: PrintFrame.classic, photo: pic, shadow: false),
        ),
      );
    }

    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Text(
        t,
        style: const TextStyle(fontFamily: 'Manual', color: Colors.white, fontSize: 24),
      ),
    );
    Widget cell(Widget w, String t) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          children: [
            SizedBox(height: 440, child: Center(child: w)),
            label(t),
          ],
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Material(
          type: MaterialType.transparency,
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: const Color(0xFF8E6B45),
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Row(
                      children: [
                        cell(instant(0), 'Now'),
                        cell(instant(1), 'A: new'),
                        cell(instant(2), 'B: handled'),
                      ],
                    ),
                    const SizedBox(height: 40),
                    Row(
                      children: [
                        cell(classic(0), 'Now'),
                        cell(classic(1), 'A: new'),
                        cell(classic(2), 'B: handled'),
                      ],
                    ),
                    const SizedBox(height: 40),
                    Row(
                      children: [
                        cell(mat(pic), 'New: Mat'),
                        cell(taped(pic), 'New: Taped'),
                        cell(snapshot(pic), 'New: Snapshot'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final shots = Platform.environment['SHOTS'];
    if (shots == null) return;
    await tester.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$shots/wear_mock.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}

const _paper = Color(0xFFFBF8F1);

Widget mat(Widget pic) => AspectRatio(
  aspectRatio: 0.8,
  child: WornSheet(
    wear: const PaperWear(seed: 21),
    child: LayoutBuilder(
      builder: (context, c) {
        final s = c.maxWidth;
        return ColoredBox(
          color: const Color(0xFFEDE6D6),
          child: Padding(
            padding: EdgeInsets.fromLTRB(s * 0.13, s * 0.13, s * 0.13, s * 0.17),
            child: DecoratedBox(
              // the bevel: the board's white core where the window was cut
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: const Color(0xFFE3DDCF), width: s * 0.018),
                  left: BorderSide(color: const Color(0xFFF2EEE5), width: s * 0.018),
                  right: BorderSide(color: const Color(0xFFFBF9F4), width: s * 0.018),
                  bottom: BorderSide(color: const Color(0xFFFFFFFF), width: s * 0.018),
                ),
              ),
              child: Padding(padding: EdgeInsets.all(s * 0.018), child: pic),
            ),
          ),
        );
      },
    ),
  ),
);

Widget taped(Widget pic) => AspectRatio(
  aspectRatio: 2 / 3,
  child: LayoutBuilder(
    builder: (context, c) {
      final s = c.maxWidth;
      Widget tape(double angle) => Transform.rotate(
        angle: angle,
        child: CustomPaint(size: Size(s * 0.34, s * 0.1), painter: _Tape()),
      );
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: WornSheet(
              wear: const PaperWear(seed: 33),
              child: ColoredBox(
                color: _paper,
                child: Padding(padding: EdgeInsets.all(s * 0.025), child: pic),
              ),
            ),
          ),
          Positioned(left: -s * 0.08, top: s * 0.0, child: tape(-0.72)),
          Positioned(right: -s * 0.08, top: s * 0.0, child: tape(0.68)),
        ],
      );
    },
  ),
);

class _Tape extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // torn ends: a few teeth
    final p = Path()..moveTo(0, 0);
    p.lineTo(w, 0);
    for (var i = 0; i <= 5; i++) {
      p.lineTo(w - (i.isEven ? 0 : h * 0.07), h * i / 5);
    }
    p.lineTo(0, h);
    for (var i = 5; i >= 0; i--) {
      p.lineTo(i.isEven ? 0 : h * 0.07, h * i / 5);
    }
    p.close();
    canvas.drawPath(
      p.shift(const Offset(0, 1.5)),
      Paint()
        ..color = const Color(0x22000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawPath(p, Paint()..color = const Color(0xC8E9DEC0));
    canvas.drawPath(
      p,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x22FFFFFF), Color(0x00FFFFFF), Color(0x14000000)],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

Widget snapshot(Widget pic) => AspectRatio(
  aspectRatio: 2 / 3,
  child: LayoutBuilder(
    builder: (context, c) {
      final s = c.maxWidth;
      return WornSheet(
        wear: const PaperWear(seed: 44),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(s * 0.05),
          child: ColoredBox(
            color: _paper,
            child: Padding(
              padding: EdgeInsets.all(s * 0.045),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  pic,
                  // the gloss: a soft sheen across the picture
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(-1, -0.6),
                        end: Alignment(1, 0.6),
                        colors: [Color(0x00FFFFFF), Color(0x1CFFFFFF), Color(0x00FFFFFF)],
                        stops: [0.3, 0.45, 0.6],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  ),
);
