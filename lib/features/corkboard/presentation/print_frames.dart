import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/processing/instant_frame.dart';
import '../../camera/application/camera_ui_state.dart';
import '../../../core/processing/paper_wear.dart';

/// How a (non-instant) print is finished round its edges.
enum PrintFrame {
  /// The lab's white border.
  classic('Classic'),

  /// Printed to the edge.
  borderless('Borderless'),

  /// The scalloped edge of an old snapshot.
  deckle('Deckle'),

  /// Printed through a filed-out negative carrier: the film's rough black
  /// edge round the picture, the frame number in it.
  darkroom('Darkroom'),

  /// Set in a cream mount board, a bevel-cut window round it.
  mat('Mat'),

  /// A drugstore print: round corners, a thin white border, glossy.
  snapshot('Snapshot');

  const PrintFrame(this.label);
  final String label;
}

/// Each print's chosen frame, by print id: a [PrintFrame] name, or an
/// [InstantStyle] name for an instant print. Kept in prefs. One never
/// chosen looks classic, and its files are as before (35 mm: the bare
/// picture; instant: the classic paper).
final printFramesProvider = NotifierProvider<PrintFrames, Map<String, String>>(PrintFrames.new);

class PrintFrames extends Notifier<Map<String, String>> {
  /// Set in main.dart (exports read it without a ref; none in tests).
  static SharedPreferencesWithCache? prefs;

  static Map<String, String> _read() {
    final raw = prefs?.getString(PrefKeys.printFrames);
    if (raw == null) return _memory;
    try {
      return (jsonDecode(raw) as Map).cast<String, String>();
    } catch (_) {
      return const {};
    }
  }

  /// (Tests: no prefs, kept here.)
  static Map<String, String> _memory = const {};

  /// The frame chosen for print [id], if any (see [printFramesProvider]).
  static String? chosen(String id) => _read()[id];

  static PrintFrame frameOf(Map<String, String> m, String id) =>
      PrintFrame.values.asNameMap()[m[id]] ?? PrintFrame.classic;

  static InstantStyle styleOf(Map<String, String> m, String id) =>
      InstantStyle.named(m[id]) ?? InstantStyle.classic;

  @override
  Map<String, String> build() => _read();

  void set(String id, String name) {
    final next = {...state, id: name};
    state = _memory = next;
    prefs?.setString(PrefKeys.printFrames, jsonEncode(next));
  }
}

/// [picturePath] finished in [frame], as a JPEG at [outPath] the picture's
/// own size (short side at most 3072 px), drawn as [FramedPrint] draws it.
Future<String> exportFramedPrint({
  required String picturePath,
  required PrintFrame frame,
  required String outPath,
  String? number,
  int seed = 0,
  DateTime? takenAt,
  PaperWear? wear,
}) async {
  final pic = await InstantFrame.decode(picturePath);
  final w = pic.width.toDouble(), h = pic.height.toDouble();
  final full = Rect.fromLTWH(0, 0, w, h);
  final s = math.min(w, h);
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  // (cover: cropped to the box's shape, centred, as BoxFit.cover)
  void photo(Rect dst) {
    final k = math.max(dst.width / w, dst.height / h);
    final src = Rect.fromCenter(center: full.center, width: dst.width / k, height: dst.height / k);
    c.drawImageRect(pic, src, dst, Paint()..filterQuality = FilterQuality.high);
  }

  void sheet(Canvas c) {
    switch (frame) {
      case PrintFrame.classic:
        c.drawRect(full, Paint()..color = FramedPrint.paper);
        photo(full.deflate(s * 0.035));
      case PrintFrame.borderless:
        photo(full);
      case PrintFrame.mat:
        c.drawRect(full, Paint()..color = FramedPrint.board);
        final cut = Rect.fromLTRB(
          s * FramedPrint.matSide,
          s * FramedPrint.matSide,
          w - s * FramedPrint.matSide,
          h - s * FramedPrint.matBottom,
        );
        final b = s * FramedPrint.matBevel;
        final inner = cut.deflate(b);
        // the bevel's four faces
        Path face(List<Offset> pts) => Path()..addPolygon(pts, true);
        c.drawPath(
          face([cut.topLeft, cut.topRight, inner.topRight, inner.topLeft]),
          Paint()..color = FramedPrint.bevelTop,
        );
        c.drawPath(
          face([cut.topLeft, inner.topLeft, inner.bottomLeft, cut.bottomLeft]),
          Paint()..color = FramedPrint.bevelLeft,
        );
        c.drawPath(
          face([cut.topRight, cut.bottomRight, inner.bottomRight, inner.topRight]),
          Paint()..color = FramedPrint.bevelRight,
        );
        c.drawPath(
          face([cut.bottomLeft, inner.bottomLeft, inner.bottomRight, cut.bottomRight]),
          Paint()..color = FramedPrint.bevelBottom,
        );
        photo(inner.deflate(0));
      case PrintFrame.snapshot:
        c.drawRect(full, Paint()..color = const Color(0xFF26231F));
        c.save();
        c.clipRRect(RRect.fromRectAndRadius(full, Radius.circular(s * FramedPrint.snapshotCorner)));
        c.drawRect(full, Paint()..color = FramedPrint.paper);
        final pr = full.deflate(s * 0.045);
        photo(pr);
        c.drawRect(pr, Paint()..shader = FramedPrint.snapshotSheen.createShader(pr));
        c.restore();
      case PrintFrame.deckle:
        // (outside the scallops: a dark scanner bed)
        c.drawRect(full, Paint()..color = const Color(0xFF26231F));
        c.save();
        c.clipPath(deckleEdge(full.size, s * 0.018));
        c.drawRect(full, Paint()..color = FramedPrint.decklePaper);
        photo(full.deflate(s * 0.075));
        c.restore();
      case PrintFrame.darkroom:
        c.drawRect(full, Paint()..color = FramedPrint.paper);
        final inner = full.deflate(s * 0.03);
        c.drawRect(inner, Paint()..color = FramedPrint.film);
        final border = s * 0.07;
        final pr = inner.deflate(border);
        c.save();
        c.translate(pr.left, pr.top);
        c.clipPath(filedEdge(pr.size, s * 0.006, seed));
        photo(Offset.zero & pr.size);
        c.restore();
        if (number != null) {
          final tp = TextPainter(
            text: TextSpan(text: '▸ $number', style: FramedPrint.numberStyle(border)),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(c, Offset(inner.left + border, inner.bottom - border * 0.18 - tp.height));
        }
    }
  }

  if (wear != null && wear.on) {
    paintWornSheet(
      c,
      full.size,
      wear,
      sheet,
      corner: frame == PrintFrame.snapshot ? FramedPrint.snapshotCorner : 0,
    );
  } else {
    sheet(c);
  }
  final framed = await rec.endRecording().toImage(w.round(), h.round());
  pic.dispose();
  return InstantFrame.writeJpeg(framed, outPath, takenAt: takenAt);
}

/// [photo] finished in [frame], filling the [aspect] box it's given (the
/// photo's own shape). [number]: the frame number for the darkroom edge.
class FramedPrint extends StatelessWidget {
  const FramedPrint({
    super.key,
    required this.frame,
    required this.photo,
    this.number,
    this.seed = 0,
    this.shadow = true,
    this.shadows,
    this.wear,
  });

  /// The paper as a real sheet (see PaperWear); null: drawn plain (small
  /// previews).
  final PaperWear? wear;

  /// Its own shadow instead of the viewer's (the board's).
  final List<BoxShadow>? shadows;

  final PrintFrame frame;
  final Widget photo;
  final String? number;

  /// Keeps each print's rough edge its own.
  final int seed;

  /// The print's shadow (off for small previews).
  final bool shadow;

  static const paper = Color(0xFFFBF8F1);
  static const decklePaper = Color(0xFFF4EEDF);
  static const board = Color(0xFFEDE6D6);

  /// A snapshot's corner radius (of its short side).
  static const snapshotCorner = 0.05;

  /// A mat's board round the window (of the short side): sides and top,
  /// bottom; the bevel's white core.
  static const matSide = 0.11, matBottom = 0.14, matBevel = 0.016;

  /// The bevel's four faces (top in shade, bottom catching the light).
  static const bevelTop = Color(0xFFE3DDCF), bevelLeft = Color(0xFFF2EEE5);
  static const bevelRight = Color(0xFFFBF9F4), bevelBottom = Color(0xFFFFFFFF);
  static const film = Color(0xFF0E0D0C);

  /// The frame number in the darkroom edge ([border]: its width).
  static TextStyle numberStyle(double border) => TextStyle(
    color: const Color(0xB3D99A3E),
    fontSize: border * 0.6,
    fontWeight: FontWeight.w600,
    letterSpacing: 1,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final s = math.min(c.maxWidth, c.maxHeight);
      final shadows =
          this.shadows ??
          (shadow
              ? const [BoxShadow(color: Colors.black87, blurRadius: 24, offset: Offset(0, 12))]
              : const <BoxShadow>[]);
      final Widget sheet = switch (frame) {
        PrintFrame.classic => ColoredBox(
          color: paper,
          child: Padding(padding: EdgeInsets.all(s * 0.035), child: photo),
        ),
        PrintFrame.borderless => ColoredBox(color: paper, child: photo),
        PrintFrame.deckle => ClipPath(
          clipper: _Clip((size) => deckleEdge(size, s * 0.018)),
          child: ColoredBox(
            color: decklePaper,
            child: Padding(padding: EdgeInsets.all(s * 0.075), child: photo),
          ),
        ),
        PrintFrame.darkroom => _darkroom(s),
        PrintFrame.mat => ColoredBox(
          color: board,
          child: Padding(
            padding: EdgeInsets.fromLTRB(s * matSide, s * matSide, s * matSide, s * matBottom),
            child: DecoratedBox(
              // the bevel: the board's white core where the window was cut
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: bevelTop, width: s * matBevel),
                  left: BorderSide(color: bevelLeft, width: s * matBevel),
                  right: BorderSide(color: bevelRight, width: s * matBevel),
                  bottom: BorderSide(color: bevelBottom, width: s * matBevel),
                ),
              ),
              child: Padding(padding: EdgeInsets.all(s * matBevel), child: photo),
            ),
          ),
        ),
        PrintFrame.snapshot => ClipRRect(
          borderRadius: BorderRadius.circular(s * snapshotCorner),
          child: ColoredBox(
            color: paper,
            child: Padding(
              padding: EdgeInsets.all(s * 0.045),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  photo,
                  // glossy: a soft sheen across the picture
                  const DecoratedBox(decoration: BoxDecoration(gradient: snapshotSheen)),
                ],
              ),
            ),
          ),
        ),
      };
      final wear = this.wear;
      if (wear != null && wear.on) {
        return WornSheet(
          wear: wear,
          shadow: shadow,
          corner: frame == PrintFrame.snapshot ? snapshotCorner : 0,
          child: sheet,
        );
      }
      return DecoratedBox(
        // (the deckle's: the rectangle's, the scallops too small for their own)
        decoration: BoxDecoration(
          boxShadow: shadows,
          borderRadius: frame == PrintFrame.snapshot ? BorderRadius.circular(s * snapshotCorner) : null,
        ),
        child: sheet,
      );
    },
  );

  /// A snapshot's gloss.
  static const snapshotSheen = LinearGradient(
    begin: Alignment(-1, -0.6),
    end: Alignment(1, 0.6),
    colors: [Color(0x00FFFFFF), Color(0x1CFFFFFF), Color(0x00FFFFFF)],
    stops: [0.3, 0.45, 0.6],
  );

  Widget _darkroom(double s) {
    final border = s * 0.07;
    return ColoredBox(
      color: paper,
      child: Padding(
        padding: EdgeInsets.all(s * 0.03),
        child: ColoredBox(
          color: film,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: EdgeInsets.all(border),
                child: ClipPath(clipper: _Clip((size) => filedEdge(size, s * 0.006, seed)), child: photo),
              ),
              if (number != null && s > 120)
                Positioned(
                  left: border,
                  bottom: border * 0.18,
                  child: Text('▸ $number', style: numberStyle(border)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A scalloped edge all round a print [size]: small arcs [r] wide.
Path deckleEdge(Size size, double r) {
  final p = Path();
  final w = size.width, h = size.height;
  final nx = math.max(2, (w / (r * 2.2)).round()), ny = math.max(2, (h / (r * 2.2)).round());
  final dx = w / nx, dy = h / ny;
  p.moveTo(0, 0);
  for (var i = 0; i < nx; i++) {
    p.quadraticBezierTo(dx * (i + 0.5), r * 1.1, dx * (i + 1), 0);
  }
  for (var i = 0; i < ny; i++) {
    p.quadraticBezierTo(w - r * 1.1, dy * (i + 0.5), w, dy * (i + 1));
  }
  for (var i = nx; i > 0; i--) {
    p.quadraticBezierTo(dx * (i - 0.5), h - r * 1.1, dx * (i - 1), h);
  }
  for (var i = ny; i > 0; i--) {
    p.quadraticBezierTo(r * 1.1, dy * (i - 0.5), 0, dy * (i - 1));
  }
  return p..close();
}

/// The picture's edge as a filed negative carrier leaves it: slightly
/// rough, bulging a hair here and there ([j]: how far).
Path filedEdge(Size size, double j, int seed) {
  final rnd = math.Random(seed);
  final w = size.width, h = size.height;
  double n() => (rnd.nextDouble() - 0.5) * 2 * j;
  final p = Path()..moveTo(n().abs(), n().abs());
  const steps = 24;
  for (var i = 1; i <= steps; i++) {
    p.lineTo(w * i / steps, n().abs());
  }
  for (var i = 1; i <= steps; i++) {
    p.lineTo(w - n().abs(), h * i / steps);
  }
  for (var i = steps - 1; i >= 0; i--) {
    p.lineTo(w * i / steps, h - n().abs());
  }
  for (var i = steps - 1; i > 0; i--) {
    p.lineTo(n().abs(), h * i / steps);
  }
  return p..close();
}

class _Clip extends CustomClipper<Path> {
  const _Clip(this.path);
  final Path Function(Size size) path;

  @override
  Path getClip(Size size) => path(size);

  @override
  bool shouldReclip(_Clip old) => true;
}

/// The frames to choose from for one print: a small preview of it in each
/// ([swatch]), the one on it marked. Tapping one puts it on at once.
class FramePicker extends StatelessWidget {
  const FramePicker({
    super.key,
    required this.options,
    required this.current,
    required this.swatch,
    required this.onPick,
  });

  /// (name, label) of each.
  final List<(String, String)> options;
  final String current;
  final Widget Function(String name) swatch;
  final ValueChanged<String> onPick;

  static const _gold = Color(0xFFF2C46D);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (name, label) in options)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Semantics(
                button: true,
                selected: name == current,
                label: '$label frame',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onPick(name),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 64,
                        height: 64,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: name == current ? const Color(0x26FFFFFF) : Colors.transparent,
                          border: Border.all(
                            color: name == current ? _gold.withValues(alpha: 0.8) : const Color(0x1FFFFFFF),
                            width: name == current ? 1.5 : 1,
                          ),
                        ),
                        child: Center(child: swatch(name)),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        style: TextStyle(
                          color: name == current ? _gold : Colors.white70,
                          fontSize: 12,
                          fontWeight: name == current ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
