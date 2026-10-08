import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../core/audio/sfx.dart';
import '../pixel_icons.dart';
import '../win98_widgets.dart';
import '../../../../../core/device/haptics.dart';

/// MINES.EXE: Minefield, the way it came with the machine: mine counter,
/// smiley, timer. Tap to dig, hold to plant a flag; tap a number whose
/// flags are all placed to clear round it. The first dig is always safe.
Future<void> showMinesweeper(BuildContext context) => showWin98Window<void>(
  context,
  title: 'Minefield',
  width: 300,
  icon: const PixelIconView(PixelIcon.rabbit),
  builder: (context) => const Padding(padding: EdgeInsets.all(6), child: MinesweeperGame()),
);

enum MineLevel {
  beginner(9, 9, 10),
  intermediate(16, 16, 40);

  const MineLevel(this.cols, this.rows, this.mines);
  final int cols, rows, mines;
}

/// The rules, apart from the drawing.
class MineField {
  MineField(this.level, {int? seed}) : _rnd = math.Random(seed);

  final MineLevel level;
  final math.Random _rnd;
  late final List<bool> mine = List.filled(level.cols * level.rows, false);
  late final List<bool> open = List.filled(level.cols * level.rows, false);
  late final List<bool> flag = List.filled(level.cols * level.rows, false);
  bool laid = false;
  bool lost = false;
  int? blown;

  int get cells => level.cols * level.rows;
  int get flags => flag.where((f) => f).length;
  bool get won => !lost && laid && List.generate(cells, (i) => mine[i] || open[i]).every((ok) => ok);

  Iterable<int> around(int i) sync* {
    final x = i % level.cols, y = i ~/ level.cols;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx, ny = y + dy;
        if (nx >= 0 && ny >= 0 && nx < level.cols && ny < level.rows) yield ny * level.cols + nx;
      }
    }
  }

  int count(int i) => around(i).where((j) => mine[j]).length;

  void _lay(int safe) {
    final keepClear = {safe, ...around(safe)};
    var placed = 0;
    while (placed < level.mines) {
      final i = _rnd.nextInt(cells);
      if (mine[i] || keepClear.contains(i)) continue;
      mine[i] = true;
      placed++;
    }
    laid = true;
  }

  /// Digs [i]. Returns false if it was a mine.
  bool dig(int i) {
    if (lost || won || flag[i] || open[i]) return true;
    if (!laid) _lay(i);
    if (mine[i]) {
      lost = true;
      blown = i;
      return false;
    }
    // Flood out from empty squares.
    final todo = [i];
    while (todo.isNotEmpty) {
      final j = todo.removeLast();
      if (open[j] || flag[j]) continue;
      open[j] = true;
      if (count(j) == 0) todo.addAll(around(j).where((k) => !open[k]));
    }
    return true;
  }

  /// Tapping an opened number with all its flags placed digs the rest.
  bool chord(int i) {
    if (!open[i] || lost) return true;
    final n = count(i);
    if (n == 0 || around(i).where((j) => flag[j]).length != n) return true;
    var ok = true;
    for (final j in around(i)) {
      if (!flag[j] && !open[j]) ok = dig(j) && ok;
    }
    return ok;
  }

  void toggleFlag(int i) {
    if (open[i] || lost || won) return;
    flag[i] = !flag[i];
  }
}

class MinesweeperGame extends StatefulWidget {
  const MinesweeperGame({super.key});

  @override
  State<MinesweeperGame> createState() => _MinesweeperGameState();
}

class _MinesweeperGameState extends State<MinesweeperGame> {
  MineLevel _level = MineLevel.beginner;
  late MineField _field = MineField(_level);
  int _seconds = 0;
  Timer? _clock;
  bool _pressing = false;

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  void _new([MineLevel? level]) {
    _clock?.cancel();
    _clock = null;
    setState(() {
      _level = level ?? _level;
      _field = MineField(_level);
      _seconds = 0;
    });
  }

  void _startClock() {
    _clock ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds = math.min(999, _seconds + 1));
    });
  }

  void _after(bool ok) {
    if (!ok) {
      _clock?.cancel();
      Sfx.mineBoom.play();
      unawaited(Haptics.heavyImpact());
    } else if (_field.won) {
      _clock?.cancel();
      // Flags go on every mine, the way the real one finishes.
      for (var i = 0; i < _field.cells; i++) {
        if (_field.mine[i]) _field.flag[i] = true;
      }
      Sfx.gameWin.play();
    } else {
      Sfx.w98Click.play();
    }
    setState(() {});
  }

  void _tap(int i) {
    if (_field.lost || _field.won) return;
    _startClock();
    _after(_field.open[i] ? _field.chord(i) : _field.dig(i));
  }

  void _hold(int i) {
    if (_field.lost || _field.won || _field.open[i]) return;
    unawaited(Haptics.selectionClick());
    Sfx.cardSnap.play();
    setState(() => _field.toggleFlag(i));
  }

  @override
  Widget build(BuildContext context) {
    final f = _field;
    final face = f.lost
        ? _Face.dead
        : f.won
        ? _Face.cool
        : _pressing
        ? _Face.oh
        : _Face.smile;
    return Win98Bevel(
      style: BevelStyle.raised,
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Win98Bevel(
            style: BevelStyle.sunken,
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            child: Row(
              children: [
                _Led(value: f.level.mines - f.flags),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    Sfx.w98Click.play();
                    _new();
                  },
                  child: Win98Bevel(
                    style: BevelStyle.raised,
                    child: SizedBox(width: 30, height: 30, child: CustomPaint(painter: _FacePainter(face))),
                  ),
                ),
                const Spacer(),
                _Led(value: _seconds),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Win98Bevel(
            style: BevelStyle.sunken,
            child: LayoutBuilder(
              builder: (context, box) {
                final cell = (box.maxWidth / f.level.cols).floorToDouble();
                return SizedBox(
                  width: cell * f.level.cols,
                  height: cell * f.level.rows,
                  child: GestureDetector(
                    onTapDown: (_) => setState(() => _pressing = true),
                    onTapUp: (d) {
                      setState(() => _pressing = false);
                      _tap(_index(d.localPosition, cell));
                    },
                    onTapCancel: () => setState(() => _pressing = false),
                    onLongPressStart: (d) {
                      setState(() => _pressing = false);
                      _hold(_index(d.localPosition, cell));
                    },
                    child: CustomPaint(painter: _FieldPainter(f, cell)),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final l in MineLevel.values) ...[
                Win98Button(
                  toggled: l == _level,
                  onPressed: () => _new(l),
                  child: Text(l == MineLevel.beginner ? 'Beginner' : 'Intermediate'),
                ),
                const SizedBox(width: 6),
              ],
              const Spacer(),
              Win98Button(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
            ],
          ),
        ],
      ),
    );
  }

  int _index(Offset p, double cell) {
    final x = (p.dx / cell).floor().clamp(0, _field.level.cols - 1);
    final y = (p.dy / cell).floor().clamp(0, _field.level.rows - 1);
    return y * _field.level.cols + x;
  }
}

/// Three red seven-segment digits on black.
class _Led extends StatelessWidget {
  const _Led({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.black,
    child: CustomPaint(size: const Size(42, 26), painter: _LedPainter(value)),
  );
}

class _LedPainter extends CustomPainter {
  _LedPainter(this.value);

  final int value;

  static const _segs = {
    '0': 'abcdef',
    '1': 'bc',
    '2': 'abged',
    '3': 'abgcd',
    '4': 'fgbc',
    '5': 'afgcd',
    '6': 'afgedc',
    '7': 'abc',
    '8': 'abcdefg',
    '9': 'abcdfg',
    '-': 'g',
  };

  @override
  void paint(Canvas canvas, Size size) {
    final text = value < 0
        ? '-${(-value).clamp(0, 99).toString().padLeft(2, '0')}'
        : value.clamp(0, 999).toString().padLeft(3, '0');
    final w = size.width / 3;
    for (var i = 0; i < 3; i++) {
      _digit(canvas, Offset(i * w + 2, 2), Size(w - 4, size.height - 4), text[i]);
    }
  }

  void _digit(Canvas canvas, Offset o, Size s, String ch) {
    final on = _segs[ch] ?? '';
    const t = 2.4;
    final w = s.width, h = s.height, m = h / 2;
    final segs = {
      'a': Rect.fromLTWH(o.dx + t, o.dy, w - 2 * t, t),
      'b': Rect.fromLTWH(o.dx + w - t, o.dy + t, t, m - 1.5 * t),
      'c': Rect.fromLTWH(o.dx + w - t, o.dy + m + t / 2, t, m - 1.5 * t),
      'd': Rect.fromLTWH(o.dx + t, o.dy + h - t, w - 2 * t, t),
      'e': Rect.fromLTWH(o.dx, o.dy + m + t / 2, t, m - 1.5 * t),
      'f': Rect.fromLTWH(o.dx, o.dy + t, t, m - 1.5 * t),
      'g': Rect.fromLTWH(o.dx + t, o.dy + m - t / 2, w - 2 * t, t),
    };
    for (final e in segs.entries) {
      canvas.drawRect(
        e.value,
        Paint()..color = on.contains(e.key) ? const Color(0xFFFF1A1A) : const Color(0xFF3A0000),
      );
    }
  }

  @override
  bool shouldRepaint(_LedPainter old) => old.value != value;
}

enum _Face { smile, oh, dead, cool }

class _FacePainter extends CustomPainter {
  _FacePainter(this.face);

  final _Face face;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.4;
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFFFFFF00));
    final ink = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawCircle(c, r, ink);
    final fill = Paint()..color = Colors.black;
    final le = c + Offset(-r * 0.38, -r * 0.25), re = c + Offset(r * 0.38, -r * 0.25);
    switch (face) {
      case _Face.dead:
        for (final e in [le, re]) {
          canvas.drawLine(e + const Offset(-2, -2), e + const Offset(2, 2), ink);
          canvas.drawLine(e + const Offset(2, -2), e + const Offset(-2, 2), ink);
        }
        canvas.drawArc(
          Rect.fromCenter(center: c + Offset(0, r * 0.55), width: r, height: r * 0.6),
          math.pi,
          math.pi,
          false,
          ink,
        );
      case _Face.cool:
        canvas.drawRect(Rect.fromCenter(center: le, width: r * 0.6, height: r * 0.32), fill);
        canvas.drawRect(Rect.fromCenter(center: re, width: r * 0.6, height: r * 0.32), fill);
        canvas.drawLine(le, re, ink);
        canvas.drawArc(
          Rect.fromCenter(center: c + Offset(0, r * 0.15), width: r, height: r * 0.7),
          0.3,
          math.pi - 0.6,
          false,
          ink,
        );
      case _Face.oh:
        canvas.drawCircle(le, 1.6, fill);
        canvas.drawCircle(re, 1.6, fill);
        canvas.drawCircle(c + Offset(0, r * 0.4), r * 0.18, ink);
      case _Face.smile:
        canvas.drawCircle(le, 1.6, fill);
        canvas.drawCircle(re, 1.6, fill);
        canvas.drawArc(
          Rect.fromCenter(center: c + Offset(0, r * 0.15), width: r, height: r * 0.7),
          0.3,
          math.pi - 0.6,
          false,
          ink,
        );
    }
  }

  @override
  bool shouldRepaint(_FacePainter old) => old.face != face;
}

class _FieldPainter extends CustomPainter {
  _FieldPainter(this.f, this.cell);

  final MineField f;
  final double cell;

  static const _numbers = [
    Color(0xFF0000FF),
    Color(0xFF008000),
    Color(0xFFFF0000),
    Color(0xFF000080),
    Color(0xFF800000),
    Color(0xFF008080),
    Color(0xFF000000),
    Color(0xFF808080),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cols = f.level.cols;
    for (var i = 0; i < f.cells; i++) {
      final r = Rect.fromLTWH((i % cols) * cell, (i ~/ cols) * cell, cell, cell);
      final showMine = f.mine[i] && (f.lost && !f.flag[i]);
      if (f.open[i] || showMine) {
        canvas.drawRect(r, Paint()..color = i == f.blown ? const Color(0xFFFF0000) : W98.face);
        canvas.drawRect(
          r,
          Paint()
            ..color = W98.shadow
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.6,
        );
        if (showMine) {
          _mine(canvas, r);
        } else {
          final n = f.count(i);
          if (n > 0) {
            final tp = TextPainter(
              text: TextSpan(
                text: '$n',
                style: W98.text.copyWith(
                  color: _numbers[n - 1],
                  fontSize: cell * 0.62,
                  fontWeight: FontWeight.w900,
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            tp.paint(canvas, r.center - Offset(tp.width / 2, tp.height / 2));
          }
        }
      } else {
        // Raised square.
        canvas.drawRect(r, Paint()..color = W98.face);
        final b = cell * 0.12;
        canvas.drawPath(
          Path()..addPolygon([
            r.topLeft,
            r.topRight,
            r.topRight + Offset(-b, b),
            r.topLeft + Offset(b, b),
            r.bottomLeft + Offset(b, -b),
            r.bottomLeft,
          ], true),
          Paint()..color = Colors.white,
        );
        canvas.drawPath(
          Path()..addPolygon([
            r.bottomRight,
            r.bottomLeft,
            r.bottomLeft + Offset(b, -b),
            r.bottomRight + Offset(-b, -b),
            r.topRight + Offset(-b, b),
            r.topRight,
          ], true),
          Paint()..color = W98.shadow,
        );
        if (f.flag[i]) _flag(canvas, r, wrong: f.lost && !f.mine[i]);
      }
    }
  }

  void _mine(Canvas canvas, Rect r) {
    final c = r.center;
    final rad = r.width * 0.24;
    final p = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.4;
    for (var k = 0; k < 4; k++) {
      final d = Offset.fromDirection(k * math.pi / 4) * rad * 1.45;
      canvas.drawLine(c - d, c + d, p);
    }
    canvas.drawCircle(c, rad, p);
    canvas.drawCircle(c - Offset(rad * 0.35, rad * 0.35), rad * 0.28, Paint()..color = Colors.white);
  }

  void _flag(Canvas canvas, Rect r, {required bool wrong}) {
    final x = r.center.dx, top = r.top + r.height * 0.2, bottom = r.bottom - r.height * 0.22;
    canvas.drawRect(Rect.fromLTRB(x - 0.8, top, x + 0.8, bottom), Paint()..color = Colors.black);
    canvas.drawPath(
      Path()
        ..moveTo(x + 0.8, top)
        ..lineTo(x - r.width * 0.28, top + r.height * 0.15)
        ..lineTo(x + 0.8, top + r.height * 0.3)
        ..close(),
      Paint()..color = const Color(0xFFFF0000),
    );
    canvas.drawRect(
      Rect.fromLTRB(x - r.width * 0.22, bottom - 2, x + r.width * 0.22, bottom),
      Paint()..color = Colors.black,
    );
    if (wrong) {
      final p = Paint()
        ..color = Colors.black
        ..strokeWidth = 1.4;
      canvas.drawLine(r.topLeft + const Offset(3, 3), r.bottomRight - const Offset(3, 3), p);
      canvas.drawLine(r.topRight + const Offset(-3, 3), r.bottomLeft + const Offset(3, -3), p);
    }
  }

  @override
  bool shouldRepaint(_FieldPainter old) => true;
}
