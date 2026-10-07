import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../core/audio/sfx.dart';
import '../pixel_icons.dart';
import '../win98_widgets.dart';

/// SOL.EXE: Klondike, draw one, made for a phone: tap a card and it goes
/// where it can (home to the foundations first, else onto a column). Tap
/// the deck to deal; tap the empty deck to turn the pile over.
Future<void> showSolitaire(BuildContext context) => showWin98Window<void>(
  context,
  title: 'Solitaire',
  width: 300,
  icon: const PixelIconView(PixelIcon.rabbit),
  builder: (context) => Padding(
    padding: const EdgeInsets.all(4),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 430, child: SolitaireGame()),
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

enum Suit { spades, hearts, diamonds, clubs }

class PlayingCard {
  PlayingCard(this.rank, this.suit);

  final int rank; // 1 (ace) .. 13 (king)
  final Suit suit;
  bool up = false;

  bool get red => suit == Suit.hearts || suit == Suit.diamonds;
  String get label => switch (rank) {
    1 => 'A',
    11 => 'J',
    12 => 'Q',
    13 => 'K',
    _ => '$rank',
  };
}

/// The rules, separate from the drawing (and tested on their own).
class Klondike {
  Klondike({int? seed}) {
    final deck = [
      for (final s in Suit.values)
        for (var r = 1; r <= 13; r++) PlayingCard(r, s),
    ]..shuffle(math.Random(seed));
    for (var c = 0; c < 7; c++) {
      for (var i = 0; i <= c; i++) {
        tableau[c].add(deck.removeLast()..up = i == c);
      }
    }
    stock.addAll(deck);
  }

  final List<PlayingCard> stock = [];
  final List<PlayingCard> waste = [];
  final List<List<PlayingCard>> foundations = List.generate(4, (_) => []);
  final List<List<PlayingCard>> tableau = List.generate(7, (_) => []);
  int moves = 0;

  bool get won => foundations.every((f) => f.length == 13);

  void deal() {
    if (stock.isEmpty) {
      stock.addAll(waste.reversed.map((c) => c..up = false));
      waste.clear();
    } else {
      waste.add(stock.removeLast()..up = true);
    }
    moves++;
  }

  bool _toFoundation(PlayingCard c) {
    for (final f in foundations) {
      final ok = f.isEmpty ? c.rank == 1 : (f.last.suit == c.suit && f.last.rank == c.rank - 1);
      if (ok) {
        f.add(c);
        return true;
      }
    }
    return false;
  }

  bool _fitsOn(PlayingCard c, List<PlayingCard> col) =>
      col.isEmpty ? c.rank == 13 : (col.last.up && col.last.red != c.red && col.last.rank == c.rank + 1);

  /// Moves [run] (bottom card first) onto a column, preferring one that
  /// already has cards (kings go to the first empty one).
  int? _columnFor(List<PlayingCard> run, int? from) {
    for (final empty in [false, true]) {
      for (var i = 0; i < 7; i++) {
        if (i == from || tableau[i].isEmpty != empty) continue;
        if (_fitsOn(run.first, tableau[i])) return i;
      }
    }
    return null;
  }

  void _flipTops() {
    for (final col in tableau) {
      if (col.isNotEmpty && !col.last.up) col.last.up = true;
    }
  }

  bool tapWaste() {
    if (waste.isEmpty) return false;
    final c = waste.last;
    if (_toFoundation(c)) {
      waste.removeLast();
    } else {
      final to = _columnFor([c], null);
      if (to == null) return false;
      tableau[to].add(waste.removeLast());
    }
    moves++;
    return true;
  }

  bool tapTableau(int col, int index) {
    final pile = tableau[col];
    if (index < 0 || index >= pile.length || !pile[index].up) return false;
    final run = pile.sublist(index);
    if (run.length == 1 && _toFoundation(run.first)) {
      pile.removeLast();
    } else {
      final to = _columnFor(run, col);
      if (to == null) return false;
      pile.removeRange(index, pile.length);
      tableau[to].addAll(run);
    }
    _flipTops();
    moves++;
    return true;
  }

  bool tapFoundation(int f) {
    final pile = foundations[f];
    if (pile.isEmpty) return false;
    final to = _columnFor([pile.last], null);
    if (to == null) return false;
    tableau[to].add(pile.removeLast());
    moves++;
    return true;
  }
}

class SolitaireGame extends StatefulWidget {
  const SolitaireGame({super.key});

  @override
  State<SolitaireGame> createState() => _SolitaireGameState();
}

class _SolitaireGameState extends State<SolitaireGame> {
  Klondike _game = Klondike();

  void _act(bool Function() move) {
    final ok = move();
    if (ok) {
      Sfx.w98Click.play();
    } else {
      Sfx.w98Ding.play();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 3.0;
        final w = (box.maxWidth - gap * 8) / 7;
        final h = w * 1.4;
        double x(int i) => gap + i * (w + gap);
        const topY = 6.0;
        final rowY = topY + h + 10;
        final children = <Widget>[];

        Widget slot(double left, double top) =>
            Positioned(left: left, top: top, width: w, height: h, child: _Slot());

        // Deck.
        children.add(slot(x(0), topY));
        if (_game.stock.isNotEmpty) {
          children.add(Positioned(left: x(0), top: topY, width: w, height: h, child: const _CardBack()));
        }
        children.add(
          Positioned(
            left: x(0),
            top: topY,
            width: w,
            height: h,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _act(() {
                _game.deal();
                return true;
              }),
            ),
          ),
        );
        // Waste.
        children.add(slot(x(1), topY));
        if (_game.waste.isNotEmpty) {
          children.add(
            Positioned(
              left: x(1),
              top: topY,
              width: w,
              height: h,
              child: GestureDetector(onTap: () => _act(_game.tapWaste), child: _CardFace(_game.waste.last)),
            ),
          );
        }
        // Foundations.
        for (var f = 0; f < 4; f++) {
          children.add(slot(x(3 + f), topY));
          final pile = _game.foundations[f];
          if (pile.isNotEmpty) {
            children.add(
              Positioned(
                left: x(3 + f),
                top: topY,
                width: w,
                height: h,
                child: GestureDetector(
                  onTap: () => _act(() => _game.tapFoundation(f)),
                  child: _CardFace(pile.last),
                ),
              ),
            );
          }
        }
        // Columns: face-down cards tucked tight, face-up ones fanned.
        for (var c = 0; c < 7; c++) {
          children.add(slot(x(c), rowY));
          final pile = _game.tableau[c];
          final up = pile.where((k) => k.up).length;
          final down = pile.length - up;
          final room = box.maxHeight - rowY - h - 4;
          final fan = math.min(h * 0.32, up > 1 ? (room - down * 5) / (up - 1) : h * 0.32);
          var y = rowY;
          for (var i = 0; i < pile.length; i++) {
            final card = pile[i];
            children.add(
              Positioned(
                left: x(c),
                top: y,
                width: w,
                height: h,
                child: GestureDetector(
                  onTap: () => _act(() => _game.tapTableau(c, i)),
                  child: card.up ? _CardFace(card) : const _CardBack(),
                ),
              ),
            );
            y += card.up ? fan : 5;
          }
        }
        if (_game.won) {
          children.add(
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _game = Klondike()),
                child: Container(
                  color: Colors.black38,
                  alignment: Alignment.center,
                  child: Text(
                    'You won in ${_game.moves} moves!\nTap to deal again.',
                    textAlign: TextAlign.center,
                    style: W98.text.copyWith(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ),
          );
        }
        return Column(
          children: [
            Expanded(
              child: ColoredBox(
                color: const Color(0xFF008000),
                child: Stack(children: children),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Win98Button(onPressed: () => setState(() => _game = Klondike()), child: const Text('Deal')),
                const Spacer(),
                Text('Moves: ${_game.moves}'),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Slot extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFF00B000)),
      borderRadius: BorderRadius.circular(3),
    ),
  );
}

class _CardBack extends StatelessWidget {
  const _CardBack();

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(3),
      border: Border.all(color: Colors.black),
    ),
    padding: const EdgeInsets.all(2),
    child: Container(
      color: const Color(0xFF1F3C88),
      alignment: Alignment.center,
      child: const PixelIconView(PixelIcon.rabbit, size: 18),
    ),
  );
}

class _CardFace extends StatelessWidget {
  const _CardFace(this.card);

  final PlayingCard card;

  @override
  Widget build(BuildContext context) {
    final color = card.red ? const Color(0xFFD00000) : Colors.black;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.black),
      ),
      padding: const EdgeInsets.all(2),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  card.label,
                  style: W98.text.copyWith(
                    color: color,
                    fontSize: 11,
                    height: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 1),
                CustomPaint(size: const Size(8, 8), painter: SuitPainter(card.suit, color)),
              ],
            ),
          ),
          Align(
            alignment: const Alignment(0, 0.4),
            child: CustomPaint(size: const Size(16, 16), painter: SuitPainter(card.suit, color)),
          ),
        ],
      ),
    );
  }
}

/// Suit pips drawn as shapes (the pixel font has no suit glyphs).
class SuitPainter extends CustomPainter {
  const SuitPainter(this.suit, this.color);

  final Suit suit;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final w = size.width, h = size.height;
    Path heart() => Path()
      ..moveTo(w / 2, h)
      ..cubicTo(-w * 0.1, h * 0.45, w * 0.1, -h * 0.1, w / 2, h * 0.25)
      ..cubicTo(w * 0.9, -h * 0.1, w * 1.1, h * 0.45, w / 2, h)
      ..close();
    switch (suit) {
      case Suit.hearts:
        canvas.drawPath(heart(), p);
      case Suit.diamonds:
        canvas.drawPath(
          Path()
            ..moveTo(w / 2, 0)
            ..lineTo(w * 0.9, h / 2)
            ..lineTo(w / 2, h)
            ..lineTo(w * 0.1, h / 2)
            ..close(),
          p,
        );
      case Suit.spades:
        canvas.save();
        canvas.translate(0, h * 0.85);
        canvas.scale(1, -0.85);
        canvas.drawPath(heart(), p);
        canvas.restore();
        canvas.drawPath(
          Path()
            ..moveTo(w / 2, h * 0.55)
            ..lineTo(w * 0.68, h)
            ..lineTo(w * 0.32, h)
            ..close(),
          p,
        );
      case Suit.clubs:
        final r = w * 0.22;
        canvas.drawCircle(Offset(w / 2, h * 0.25), r, p);
        canvas.drawCircle(Offset(w * 0.27, h * 0.55), r, p);
        canvas.drawCircle(Offset(w * 0.73, h * 0.55), r, p);
        canvas.drawPath(
          Path()
            ..moveTo(w / 2, h * 0.45)
            ..lineTo(w * 0.68, h)
            ..lineTo(w * 0.32, h)
            ..close(),
          p,
        );
    }
  }

  @override
  bool shouldRepaint(SuitPainter old) => old.suit != suit || old.color != color;
}
