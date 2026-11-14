import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Paper stickers for the scrapbook: die-cut, a white edge round each and
/// a soft shadow, as if peeled off a sheet. (A first few, to be dialled in.)
enum Sticker {
  star('Star', 0.2),
  heart('Heart', 0.18),
  arrow('Arrow', 0.28),
  note('Sticky note', 0.3),
  tape('Tape', 0.3),
  flower('Flower', 0.2);

  const Sticker(this.label, this.size);
  final String label;

  /// How wide it starts, in page widths.
  final double size;
}

/// One sticker, [width] wide; a sticky note carries [text].
class StickerView extends StatelessWidget {
  const StickerView({super.key, required this.sticker, required this.width, this.text});

  final Sticker sticker;
  final double width;
  final String? text;

  double get _aspect => switch (sticker) {
    Sticker.arrow => 2.2,
    Sticker.tape => 3.6,
    _ => 1,
  };

  @override
  Widget build(BuildContext context) {
    final h = width / _aspect;
    final paint = CustomPaint(size: Size(width, h), painter: _StickerPainter(sticker));
    if (sticker != Sticker.note) return paint;
    return SizedBox(
      width: width,
      height: h,
      child: Stack(
        children: [
          paint,
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(width * 0.12, width * 0.16, width * 0.12, width * 0.12),
              child: Center(
                child: Text(
                  text ?? '',
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.fade,
                  style: TextStyle(
                    fontFamily: 'Caveat',
                    fontWeight: FontWeight.w600,
                    fontSize: width * 0.16,
                    height: 1.0,
                    color: const Color(0xFF2A2A6A),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StickerPainter extends CustomPainter {
  const _StickerPainter(this.sticker);

  final Sticker sticker;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    switch (sticker) {
      case Sticker.star:
        _dieCut(canvas, _star(Offset(w / 2, h / 2), w * 0.42, w * 0.19), const [
          Color(0xFFF7D35A),
          Color(0xFFE0A42A),
        ], w);
      case Sticker.heart:
        _dieCut(canvas, _heart(Rect.fromLTWH(w * 0.1, h * 0.12, w * 0.8, h * 0.76)), const [
          Color(0xFFEF6F6C),
          Color(0xFFC0392B),
        ], w);
      case Sticker.flower:
        final petals = Path();
        for (var i = 0; i < 6; i++) {
          final a = i * math.pi / 3;
          petals.addOval(
            Rect.fromCircle(
              center: Offset(w / 2 + math.cos(a) * w * 0.22, h / 2 + math.sin(a) * w * 0.22),
              radius: w * 0.17,
            ),
          );
        }
        _dieCut(canvas, petals, const [Color(0xFFF6A9C4), Color(0xFFE07AA0)], w);
        canvas.drawCircle(Offset(w / 2, h / 2), w * 0.13, Paint()..color = const Color(0xFFF7D35A));
        canvas.drawCircle(
          Offset(w / 2, h / 2),
          w * 0.13,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 0.015
            ..color = const Color(0x33000000),
        );
      case Sticker.arrow:
        // a hand-cut paper arrow, slightly bent
        final p = Path()
          ..moveTo(w * 0.04, h * 0.42)
          ..quadraticBezierTo(w * 0.35, h * 0.3, w * 0.66, h * 0.36)
          ..lineTo(w * 0.64, h * 0.12)
          ..lineTo(w * 0.96, h * 0.5)
          ..lineTo(w * 0.62, h * 0.88)
          ..lineTo(w * 0.64, h * 0.64)
          ..quadraticBezierTo(w * 0.35, h * 0.58, w * 0.06, h * 0.7)
          ..close();
        _dieCut(canvas, p, const [Color(0xFFC79A64), Color(0xFFA0723F)], w);
      case Sticker.note:
        final r = Rect.fromLTWH(w * 0.05, h * 0.05, w * 0.9, h * 0.9);
        final fold = w * 0.14;
        final p = Path()
          ..moveTo(r.left, r.top)
          ..lineTo(r.right, r.top)
          ..lineTo(r.right, r.bottom - fold)
          ..lineTo(r.right - fold, r.bottom)
          ..lineTo(r.left, r.bottom)
          ..close();
        canvas.drawShadow(p, const Color(0xFF000000), w * 0.03, false);
        canvas.drawPath(
          p,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFF27A), Color(0xFFF7DF4F)],
            ).createShader(r),
        );
        // the sticky strip at the top, a touch darker
        canvas.drawRect(
          Rect.fromLTWH(r.left, r.top, r.width, r.height * 0.14),
          Paint()..color = const Color(0x14000000),
        );
        canvas.drawPath(
          Path()
            ..moveTo(r.right, r.bottom - fold)
            ..lineTo(r.right - fold, r.bottom - fold)
            ..lineTo(r.right - fold, r.bottom)
            ..close(),
          Paint()..color = const Color(0xFFE2C93A),
        );
      case Sticker.tape:
        // washi tape: torn zigzag ends, see-through, striped
        final p = Path()..moveTo(0, 0);
        const teeth = 5;
        for (var i = 1; i <= teeth; i++) {
          p.lineTo(i.isOdd ? w * 0.03 : 0, h * i / teeth);
        }
        p.lineTo(w, h);
        for (var i = teeth - 1; i >= 0; i--) {
          p.lineTo(i.isOdd ? w * 0.97 : w, h * i / teeth);
        }
        p.close();
        canvas.save();
        canvas.clipPath(p);
        canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xB37FC4B3));
        final stripe = Paint()
          ..color = const Color(0x55FFFFFF)
          ..strokeWidth = h * 0.18;
        for (var x = -h; x < w + h; x += h * 0.55) {
          canvas.drawLine(Offset(x, h), Offset(x + h, 0), stripe);
        }
        canvas.restore();
    }
  }

  /// A sticker cut out with a white margin round it, a shadow under it,
  /// a gentle shine across.
  void _dieCut(Canvas canvas, Path shape, List<Color> colors, double w) {
    final edge = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.07
      ..strokeJoin = StrokeJoin.round;
    final outline = Path()..addPath(shape, Offset.zero);
    canvas.drawShadow(outline, const Color(0xFF000000), w * 0.03, false);
    canvas.drawPath(shape, edge);
    canvas.drawPath(shape, Paint()..color = const Color(0xFFFFFFFF));
    final b = shape.getBounds();
    canvas.drawPath(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ).createShader(b),
    );
    canvas.drawPath(
      shape,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)],
        ).createShader(b),
    );
  }

  Path _star(Offset c, double outer, double inner) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / 5;
      final q = c + Offset(math.cos(a), math.sin(a)) * r;
      if (i == 0) {
        p.moveTo(q.dx, q.dy);
      } else {
        p.lineTo(q.dx, q.dy);
      }
    }
    return p..close();
  }

  Path _heart(Rect r) {
    final w = r.width, h = r.height;
    return Path()
      ..moveTo(r.left + w / 2, r.top + h * 0.28)
      ..cubicTo(
        r.left + w * 0.2,
        r.top - h * 0.1,
        r.left - w * 0.1,
        r.top + h * 0.45,
        r.left + w / 2,
        r.bottom,
      )
      ..cubicTo(
        r.right + w * 0.1,
        r.top + h * 0.45,
        r.right - w * 0.2,
        r.top - h * 0.1,
        r.left + w / 2,
        r.top + h * 0.28,
      )
      ..close();
  }

  @override
  bool shouldRepaint(_StickerPainter old) => old.sticker != sticker;
}
