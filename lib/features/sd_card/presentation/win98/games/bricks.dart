import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';

import '../../../../../core/audio/sfx.dart';
import '../pixel_icons.dart';
import '../../../../../core/skins/camera_skins.dart';
import '../win98_widgets.dart';
import 'game_help.dart';
import 'high_scores.dart';
import 'skin_awards.dart';
import '../../../../../core/device/haptics.dart';

/// BRICKS.EXE: brick breaker. Drag anywhere on the field to move the bat,
/// tap to serve. Three balls; clear the wall to win.
Future<void> showBricks(BuildContext context) => showWin98Window<void>(
  context,
  title: 'Bricks',
  width: 300,
  icon: const PixelIconView(PixelIcon.bricks),
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
        Row(
          children: [
            Win98Button(
              onPressed: () => showGameHelp(
                context,
                game: 'Bricks',
                icon: PixelIcon.bricks,
                howTo: [
                  'Drag anywhere on the field to move the bat; tap to serve.',
                  'Break every brick to win. Three balls to start.',
                  'Some bricks drop a capsule: catch it on the bat.',
                  for (final p in _Power.values) '${p.letter}: ${p.what}.',
                ],
              ),
              child: const Text('Help'),
            ),
            const Spacer(),
            Win98Button(
              minWidth: 76,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
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
  _Brick(this.rect, this.color, this.power);
  final Rect rect;
  final Color color;

  /// What it drops when broken (about one in six).
  final _Power? power;
  bool alive = true;
}

/// The capsules some bricks drop: catch one on the bat.
enum _Power {
  wide('W', Color(0xFF3A7BFF), 'Wide bat'),
  multi('M', Color(0xFFFF4FD8), 'Three balls'),
  slow('S', Color(0xFF2EC27E), 'Slow ball'),
  life('+', Color(0xFFFF3B30), 'Extra ball'),
  catcher('C', Color(0xFFFFB020), 'Catch: the ball sticks; tap to let go');

  const _Power(this.letter, this.color, this.what);
  final String letter;
  final Color color;
  final String what;
}

class _Ball {
  _Ball(this.p, this.v);
  Offset p, v;
}

class _Drop {
  _Drop(this.p, this.power);
  Offset p;
  final _Power power;
}

class _BricksGameState extends State<BricksGame> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  Size _size = Size.zero;
  final _rnd = math.Random();

  static const _ballR = 4.0;
  static const _batH = 7.0;
  static const _speed = 230.0;

  double _bat = 0.5; // centre, as a fraction of the width
  final _balls = <_Ball>[];
  final _drops = <_Drop>[];
  bool _served = false;
  int _lives = 3;
  int _score = 0;
  String? _banner = 'Tap to serve';
  List<_Brick> _bricks = [];

  // power-ups running: seconds left (0: off)
  double _wide = 0, _slow = 0, _catch = 0;

  /// A ball held on the bat by Catch (its offset from the bat's centre).
  double? _stuckAt;

  /// The last power caught, shown a moment.
  String? _caught;
  double _caughtFor = 0;

  double get _batW => _wide > 0 ? 82.0 : 52.0;

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
          _Brick(
            Rect.fromLTWH(4 + c * (w + gap), top + r * (h + gap), w, h),
            _rows[r],
            _rnd.nextDouble() < 0.17 ? _Power.values[_rnd.nextInt(_Power.values.length)] : null,
          ),
    ];
    _lives = 3;
    _score = 0;
    _reset();
  }

  void _reset() {
    _served = false;
    _balls.clear();
    _drops.clear();
    _wide = _slow = _catch = 0;
    _stuckAt = null;
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

  double get _pace => _slow > 0 ? 0.62 : 1.0;

  void _launch(_Ball b, double hit) {
    final a = -math.pi / 2 + hit * 1.05;
    b.v = Offset(math.cos(a), math.sin(a)) * _speed;
  }

  void _serve() {
    if (_lives <= 0 || _bricks.every((b) => !b.alive)) {
      setState(_newGame);
      return;
    }
    if (_stuckAt != null && _balls.isNotEmpty) {
      // let a caught ball go
      _launch(_balls.first, (_stuckAt! / (_batW / 2)).clamp(-1.0, 1.0));
      _stuckAt = null;
      return;
    }
    if (_served) return;
    final ball = _Ball(Offset(_bat * _size.width, _batY - _batH / 2 - _ballR - 1), Offset.zero);
    _launch(ball, (_rnd.nextDouble() - 0.5) * 0.8);
    _balls
      ..clear()
      ..add(ball);
    _served = true;
    _banner = null;
  }

  void _tick(Duration now) {
    final dt = math.min(0.033, (now - _last).inMicroseconds / 1e6);
    _last = now;
    if (_size == Size.zero) return;
    if (!_served) {
      setState(() {});
      return;
    }
    _wide = math.max(0, _wide - dt);
    _slow = math.max(0, _slow - dt);
    _catch = math.max(0, _catch - dt);
    _caughtFor = math.max(0, _caughtFor - dt);
    // Small steps so a fast ball never skips a brick.
    const steps = 4;
    for (var i = 0; i < steps; i++) {
      _step(dt / steps);
      if (!_served) break;
    }
    setState(() {});
  }

  void _power(_Power p) {
    _caught = p.what.split(':').first;
    _caughtFor = 1.6;
    Sfx.gameBlip.play();
    unawaited(Haptics.selectionClick());
    switch (p) {
      case _Power.wide:
        _wide = 14;
      case _Power.slow:
        _slow = 12;
      case _Power.catcher:
        _catch = 15;
      case _Power.life:
        _lives = math.min(_lives + 1, 6);
      case _Power.multi:
        if (_balls.isEmpty) return;
        final from = _balls.first;
        for (final turn in [-0.5, 0.5]) {
          final v = from.v.distance == 0 ? const Offset(0, -_speed) : from.v;
          final a = math.atan2(v.dy, v.dx) + turn;
          _balls.add(_Ball(from.p, Offset(math.cos(a), math.sin(a)) * v.distance));
        }
    }
  }

  void _step(double dt) {
    final bat = _batRect;
    // the capsules falling; caught on the bat, or lost
    for (final d in [..._drops]) {
      d.p = d.p + Offset(0, 95 * dt);
      if (bat.inflate(4).contains(d.p)) {
        _drops.remove(d);
        _power(d.power);
      } else if (d.p.dy > _size.height + 10) {
        _drops.remove(d);
      }
    }
    for (final ball in [..._balls]) {
      // held by Catch: rides on the bat
      if (_stuckAt != null && identical(ball, _balls.first)) {
        ball.p = Offset(bat.center.dx + _stuckAt!, bat.top - _ballR);
        continue;
      }
      var p = ball.p + ball.v * dt * _pace;
      var v = ball.v;
      if (p.dx < _ballR || p.dx > _size.width - _ballR) {
        v = Offset(-v.dx, v.dy);
        p = Offset(p.dx.clamp(_ballR, _size.width - _ballR), p.dy);
      }
      if (p.dy < _ballR) {
        v = Offset(v.dx, v.dy.abs());
        p = Offset(p.dx, _ballR);
      }
      // The bat: where it lands sets the angle out.
      if (v.dy > 0 && bat.inflate(_ballR).contains(p)) {
        final hit = ((p.dx - bat.center.dx) / (bat.width / 2)).clamp(-1.0, 1.0);
        if (_catch > 0 && _stuckAt == null && identical(ball, _balls.first)) {
          _stuckAt = p.dx - bat.center.dx;
          ball.p = Offset(p.dx, bat.top - _ballR);
          ball.v = Offset.zero;
          Sfx.gameBop.play();
          continue;
        }
        final a = -math.pi / 2 + hit * 1.05;
        final speed = math.min(v.distance * 1.01, _speed * 1.6);
        v = Offset(math.cos(a), math.sin(a)) * speed;
        p = Offset(p.dx, bat.top - _ballR);
        Sfx.gameBop.play();
      }
      for (final b in _bricks) {
        if (!b.alive || !b.rect.inflate(_ballR).contains(p)) continue;
        b.alive = false;
        _score += 10;
        if (b.power != null) _drops.add(_Drop(b.rect.center, b.power!));
        // Bounce off the side we came through.
        final r = b.rect;
        final fromSide = ball.p.dx < r.left || ball.p.dx > r.right;
        v = fromSide ? Offset(-v.dx, v.dy) : Offset(v.dx, -v.dy);
        Sfx.gameBlip.play();
        if (_bricks.every((b) => !b.alive)) {
          _served = false;
          _banner = 'You win! $_score points. Tap to play again';
          HighScores.best(context, HighScores.bricks, _score);
          Sfx.gameWin.play();
          awardSkins(context, SkinStats.bricksWalls);
          unawaited(Haptics.mediumImpact());
          return;
        }
        break;
      }
      ball.p = p;
      ball.v = v;
      if (p.dy > _size.height + _ballR) _balls.remove(ball);
    }
    // the last ball gone: one life
    if (_balls.isEmpty) {
      _lives--;
      Sfx.gameLose.play();
      _banner = _lives > 0 ? '$_lives left. Tap to serve' : 'Game over: $_score points. Tap to play again';
      if (_lives <= 0) HighScores.best(context, HighScores.bricks, _score);
      _reset();
    }
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
                  ? (_caughtFor > 0 && _caught != null
                        ? Text(
                            _caught!,
                            style: W98.text.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                          )
                        : null)
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
    final ballPaint = Paint()..color = Colors.white;
    if (!g._served) {
      canvas.drawCircle(
        Offset(g._bat * size.width, g._batY - _BricksGameState._batH / 2 - _BricksGameState._ballR - 1),
        _BricksGameState._ballR,
        ballPaint,
      );
    }
    for (final b in g._balls) {
      canvas.drawCircle(b.p, _BricksGameState._ballR, ballPaint);
    }
    // the capsules: a lit pill with its letter
    for (final d in g._drops) {
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: d.p, width: 20, height: 9),
        const Radius.circular(4.5),
      );
      canvas.drawRRect(r, Paint()..color = d.power.color);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(r.left + 2, r.top + 1, r.width - 4, 2.5),
          const Radius.circular(1.5),
        ),
        Paint()..color = Colors.white54,
      );
      final t = TextPainter(
        text: TextSpan(
          text: d.power.letter,
          style: W98.text.copyWith(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800, height: 1),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      t.paint(canvas, d.p - Offset(t.width / 2, t.height / 2));
    }
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
