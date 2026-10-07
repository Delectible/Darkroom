import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../../../core/audio/sfx.dart';
import '../pixel_icons.dart';
import '../win98_widgets.dart';

/// BRICKS.EXE: brick breaker. Drag anywhere on the field to move the bat,
/// tap to serve. Three balls; clear the wall to win.
Future<void> showBricks(BuildContext context) => showWin98Window<void>(
  context,
  title: 'Bricks',
  width: 300,
  icon: const PixelIconView(PixelIcon.rabbit),
  builder: (context) => Padding(
    padding: const EdgeInsets.all(6),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Win98Bevel(
          style: BevelStyle.sunken,
          child: SizedBox(height: 380, child: BricksGame()),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: Win98Button(
            minWidth: 76,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ),
      ],
    ),
  ),
);

class BricksGame extends StatefulWidget {
  const BricksGame({super.key});

  @override
  State<BricksGame> createState() => _BricksGameState();
}

class _Brick {
  _Brick(this.rect, this.color);
  final Rect rect;
  final Color color;
  bool alive = true;
}

class _BricksGameState extends State<BricksGame> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  Size _size = Size.zero;

  static const _ballR = 4.0;
  static const _batW = 52.0, _batH = 7.0;
  static const _speed = 230.0;

  double _bat = 0.5; // centre, as a fraction of the width
  Offset _ball = Offset.zero;
  Offset _vel = Offset.zero;
  bool _served = false;
  int _lives = 3;
  int _score = 0;
  String? _banner = 'Tap to serve';
  List<_Brick> _bricks = [];

  static const _rows = [
    Color(0xFFFF0000),
    Color(0xFFFF8000),
    Color(0xFFFFFF00),
    Color(0xFF00C000),
    Color(0xFF0080FF),
    Color(0xFF8000FF),
  ];

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _layout(Size size) {
    if (size == _size) return;
    _size = size;
    _newGame();
  }

  void _newGame() {
    const cols = 8, top = 36.0, h = 12.0, gap = 2.0;
    final w = (_size.width - 8 - gap * (cols - 1)) / cols;
    _bricks = [
      for (var r = 0; r < _rows.length; r++)
        for (var c = 0; c < cols; c++)
          _Brick(Rect.fromLTWH(4 + c * (w + gap), top + r * (h + gap), w, h), _rows[r]),
    ];
    _lives = 3;
    _score = 0;
    _reset();
  }

  void _reset() {
    _served = false;
    _vel = Offset.zero;
    _banner = _lives == 3 && _score == 0 ? 'Tap to serve' : _banner;
  }

  /// Follows the finger, but the bat never leaves the field.
  void _moveBat(double x) {
    final half = _batW / 2 / _size.width;
    _bat = (x / _size.width).clamp(half, 1 - half);
  }

  double get _batY => _size.height - 22;
  Rect get _batRect =>
      Rect.fromCenter(center: Offset(_bat * _size.width, _batY), width: _batW, height: _batH);

  void _serve() {
    if (_lives <= 0 || _bricks.every((b) => !b.alive)) {
      setState(_newGame);
      return;
    }
    if (_served) return;
    final a = -math.pi / 2 + (math.Random().nextDouble() - 0.5) * 0.8;
    _vel = Offset(math.cos(a), math.sin(a)) * _speed;
    _served = true;
    _banner = null;
  }

  void _tick(Duration now) {
    final dt = math.min(0.033, (now - _last).inMicroseconds / 1e6);
    _last = now;
    if (_size == Size.zero) return;
    if (!_served) {
      _ball = Offset(_bat * _size.width, _batY - _batH / 2 - _ballR - 1);
      setState(() {});
      return;
    }
    // Small steps so a fast ball never skips a brick.
    const steps = 4;
    for (var i = 0; i < steps; i++) {
      _step(dt / steps);
      if (!_served) break;
    }
    setState(() {});
  }

  void _step(double dt) {
    var p = _ball + _vel * dt;
    var v = _vel;
    if (p.dx < _ballR || p.dx > _size.width - _ballR) {
      v = Offset(-v.dx, v.dy);
      p = Offset(p.dx.clamp(_ballR, _size.width - _ballR), p.dy);
    }
    if (p.dy < _ballR) {
      v = Offset(v.dx, v.dy.abs());
      p = Offset(p.dx, _ballR);
    }
    // The bat: where it lands sets the angle out.
    final bat = _batRect;
    if (v.dy > 0 && bat.inflate(_ballR).contains(p)) {
      final hit = ((p.dx - bat.center.dx) / (bat.width / 2)).clamp(-1.0, 1.0);
      final a = -math.pi / 2 + hit * 1.05;
      final speed = math.min(v.distance * 1.01, _speed * 1.6);
      v = Offset(math.cos(a), math.sin(a)) * speed;
      p = Offset(p.dx, bat.top - _ballR);
      Sfx.w98Click.play();
    }
    for (final b in _bricks) {
      if (!b.alive || !b.rect.inflate(_ballR).contains(p)) continue;
      b.alive = false;
      _score += 10;
      // Bounce off the side we came through.
      final r = b.rect;
      final fromSide = _ball.dx < r.left || _ball.dx > r.right;
      v = fromSide ? Offset(-v.dx, v.dy) : Offset(v.dx, -v.dy);
      Sfx.w98Click.play();
      if (_bricks.every((b) => !b.alive)) {
        _served = false;
        _banner = 'You win! $_score points. Tap to play again';
        unawaited(HapticFeedback.mediumImpact());
      }
      break;
    }
    if (p.dy > _size.height + _ballR) {
      _lives--;
      _served = false;
      Sfx.w98Ding.play();
      _banner = _lives > 0 ? '$_lives left. Tap to serve' : 'Game over: $_score points. Tap to play again';
      return;
    }
    _ball = p;
    _vel = v;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        _layout(box.biggest);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _serve,
          onPanDown: (d) => _moveBat(d.localPosition.dx),
          onPanUpdate: (d) => _moveBat(d.localPosition.dx),
          child: CustomPaint(
            size: box.biggest,
            painter: _BricksPainter(this),
            child: Align(
              alignment: const Alignment(0, 0.35),
              child: _banner == null
                  ? null
                  : Container(
                      color: Colors.black54,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text(_banner!, style: W98.text.copyWith(color: Colors.white)),
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _BricksPainter extends CustomPainter {
  _BricksPainter(this.g);

  final _BricksGameState g;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    for (final b in g._bricks) {
      if (!b.alive) continue;
      canvas.drawRect(b.rect, Paint()..color = b.color);
      // 9x bevel on every brick.
      canvas.drawRect(
        Rect.fromLTWH(b.rect.left, b.rect.top, b.rect.width, 2),
        Paint()..color = Colors.white54,
      );
      canvas.drawRect(
        Rect.fromLTWH(b.rect.left, b.rect.bottom - 2, b.rect.width, 2),
        Paint()..color = Colors.black38,
      );
    }
    canvas.drawRect(g._batRect, Paint()..color = W98.face);
    canvas.drawRect(
      Rect.fromLTWH(g._batRect.left, g._batRect.top, g._batRect.width, 2),
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(g._ball, _BricksGameState._ballR, Paint()..color = Colors.white);
    final tp = TextPainter(
      text: TextSpan(
        text: 'SCORE ${g._score}    BALLS',
        style: W98.text.copyWith(color: Colors.white, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    tp.paint(canvas, const Offset(6, 8));
    for (var i = 0; i < g._lives; i++) {
      canvas.drawCircle(
        Offset(6 + tp.width + 9 + i * 10, 8 + tp.height / 2),
        3.5,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_BricksPainter old) => true;
}
