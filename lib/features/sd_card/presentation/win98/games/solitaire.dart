import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../../../core/audio/sfx.dart';
import '../pixel_icons.dart';
import '../../../../../core/skins/camera_skins.dart';
import '../win98_widgets.dart';
import 'game_help.dart';
import 'high_scores.dart';
import 'skin_awards.dart';

/// SOL.EXE: Klondike, draw one: drag a card (or a run of them) onto a
/// column or home to the foundations, as on the real thing. Tap the deck
/// to deal; tap the empty deck to turn the pile over.
Future<void> showSolitaire(BuildContext context) => showWin98Window<void>(
  context,
  title: 'Solitaire',
  width: 300,
  icon: const PixelIconView(PixelIcon.cards),
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

  // ---- dragging: a card (or a run) dropped on one place ----

  /// The cards a drag from [from] picks up (bottom first), or none.
  List<PlayingCard> pickUp(CardSpot from) => switch (from) {
    WasteSpot() => waste.isEmpty ? const [] : [waste.last],
    FoundationSpot(:final f) => foundations[f].isEmpty ? const [] : [foundations[f].last],
    ColumnSpot(:final c, :final i) =>
      i >= 0 && i < tableau[c].length && tableau[c][i].up ? tableau[c].sublist(i) : const [],
  };

  /// Drops what [from] holds on foundation [f] (one card) or column [c].
  bool drop(CardSpot from, {int? f, int? c}) {
    final run = pickUp(from);
    if (run.isEmpty) return false;
    if (f != null) {
      if (run.length != 1 || (from is FoundationSpot && from.f == f)) return false;
      final pile = foundations[f];
      final card = run.first;
      final ok = pile.isEmpty
          ? card.rank == 1
          : (pile.last.suit == card.suit && pile.last.rank == card.rank - 1);
      if (!ok) return false;
      _take(from, 1);
      pile.add(card);
    } else if (c != null) {
      if (from is ColumnSpot && from.c == c) return false;
      if (!_fitsOn(run.first, tableau[c])) return false;
      _take(from, run.length);
      tableau[c].addAll(run);
    } else {
      return false;
    }
    _flipTops();
    moves++;
    return true;
  }

  void _take(CardSpot from, int n) {
    final pile = switch (from) {
      WasteSpot() => waste,
      FoundationSpot(:final f) => foundations[f],
      ColumnSpot(:final c) => tableau[c],
    };
    pile.removeRange(pile.length - n, pile.length);
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

/// Where a dragged card comes from.
sealed class CardSpot {
  const CardSpot();
}

class WasteSpot extends CardSpot {
  const WasteSpot();
}

class FoundationSpot extends CardSpot {
  const FoundationSpot(this.f);
  final int f;
}

class ColumnSpot extends CardSpot {
  const ColumnSpot(this.c, this.i);
  final int c, i;
}

class SolitaireGame extends StatefulWidget {
  const SolitaireGame({super.key});

  @override
  State<SolitaireGame> createState() => _SolitaireGameState();
}

class _SolitaireGameState extends State<SolitaireGame> {
  Klondike _game = Klondike();

  @override
  void initState() {
    super.initState();
    Sfx.cardRiffle.play();
  }

  /// When this hand was dealt, and whether its win has been counted.
  DateTime _dealt = DateTime.now();
  bool _counted = false;

  void _redeal() {
    Sfx.cardRiffle.play();
    setState(() {
      _game = Klondike();
      _dealt = DateTime.now();
      _counted = false;
    });
  }

  // the drag under way: what's held, where it was picked up from, and where
  // the finger has it now (the held card's top left)
  CardSpot? _from;
  Offset _held = Offset.zero, _grab = Offset.zero;

  // this layout's targets (set as it's built)
  final _cards = <(Rect, CardSpot)>[];
  final _foundationRects = <Rect>[];
  final _columnRects = <Rect>[];

  void _dragStart(DragStartDetails d) {
    final p = d.localPosition;
    for (final (r, spot) in _cards.reversed) {
      if (r.contains(p) && _game.pickUp(spot).isNotEmpty) {
        setState(() {
          _from = spot;
          _grab = p - r.topLeft;
          _held = r.topLeft;
        });
        return;
      }
    }
  }

  void _dragUpdate(DragUpdateDetails d) {
    if (_from == null) return;
    setState(() => _held = d.localPosition - _grab);
  }

  void _dragEnd() {
    final from = _from;
    if (from == null) return;
    // where the held card mostly is: the target it overlaps most
    final held = _held & _cardSize;
    double overlap(Rect r) {
      final i = r.intersect(held);
      return i.width <= 0 || i.height <= 0 ? 0 : i.width * i.height;
    }

    var best = 0.0;
    int? f, c;
    for (var k = 0; k < _foundationRects.length; k++) {
      final o = overlap(_foundationRects[k]);
      if (o > best) (best, f, c) = (o, k, null);
    }
    for (var k = 0; k < _columnRects.length; k++) {
      final o = overlap(_columnRects[k]);
      if (o > best) (best, f, c) = (o, null, k);
    }
    _from = null;
    if (best <= 0) {
      setState(() {});
      return;
    }
    _act(() => _game.drop(from, f: f, c: c));
  }

  Size _cardSize = Size.zero;

  void _act(bool Function() move) {
    final ok = move();
    if (ok) {
      Sfx.cardSnap.play();
      if (_game.won && !_counted) {
        _counted = true;
        Sfx.gameWin.play();
        awardSkins(context, SkinStats.solWins);
        HighScores.count(context, HighScores.solitaireWins);
        HighScores.best(
          context,
          HighScores.solitaireTime,
          math.max(1, DateTime.now().difference(_dealt).inSeconds),
          lower: true,
        );
        if (DateTime.now().difference(_dealt) < const Duration(minutes: 5)) {
          awardSkins(context, SkinStats.solFast);
        }
      }
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
        _cardSize = Size(w, h);
        _cards.clear();
        _foundationRects
          ..clear()
          ..addAll([for (var f = 0; f < 4; f++) Rect.fromLTWH(x(3 + f), topY, w, h)]);
        _columnRects
          ..clear()
          ..addAll([for (var c = 0; c < 7; c++) Rect.fromLTRB(x(c), rowY, x(c) + w, box.maxHeight)]);
        final held = _from == null ? const <PlayingCard>[] : _game.pickUp(_from!);
        bool isHeld(PlayingCard k) => held.any((h) => identical(h, k));

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
          _cards.add((Rect.fromLTWH(x(1), topY, w, h), const WasteSpot()));
          // (the one under it shows while the top one's held)
          final shown = isHeld(_game.waste.last)
              ? (_game.waste.length > 1 ? _game.waste[_game.waste.length - 2] : null)
              : _game.waste.last;
          if (shown != null) {
            children.add(Positioned(left: x(1), top: topY, width: w, height: h, child: _CardFace(shown)));
          }
        }
        // Foundations.
        for (var f = 0; f < 4; f++) {
          children.add(slot(x(3 + f), topY));
          final pile = _game.foundations[f];
          if (pile.isNotEmpty) {
            _cards.add((Rect.fromLTWH(x(3 + f), topY, w, h), FoundationSpot(f)));
            final shown = isHeld(pile.last) ? (pile.length > 1 ? pile[pile.length - 2] : null) : pile.last;
            if (shown != null) {
              children.add(
                Positioned(left: x(3 + f), top: topY, width: w, height: h, child: _CardFace(shown)),
              );
            }
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
            final next = y + (card.up ? fan : 5);
            if (card.up) {
              // (grabbed by the strip that shows; the last one by all of it)
              _cards.add((Rect.fromLTWH(x(c), y, w, i == pile.length - 1 ? h : next - y), ColumnSpot(c, i)));
            }
            if (!isHeld(card)) {
              children.add(
                Positioned(
                  left: x(c),
                  top: y,
                  width: w,
                  height: h,
                  child: card.up ? _CardFace(card) : const _CardBack(),
                ),
              );
            }
            y = next;
          }
        }
        // what's held, under the finger, on top of everything (fanned)
        for (var k = 0; k < held.length; k++) {
          children.add(
            Positioned(
              left: _held.dx,
              top: _held.dy + k * h * 0.28,
              width: w,
              height: h,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: const [
                      BoxShadow(color: Color(0x66000000), blurRadius: 4, offset: Offset(2, 3)),
                    ],
                  ),
                  child: _CardFace(held[k]),
                ),
              ),
            ),
          );
        }
        if (_game.won) {
          children.add(
            Positioned.fill(
              child: GestureDetector(
                onTap: _redeal,
                child: Container(
                  color: Colors.black38,
                  alignment: Alignment.center,
                  child: Text(
                    'You won in ${_game.moves} moves!\nTap to play again.',
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
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: _dragStart,
                  onPanUpdate: _dragUpdate,
                  onPanEnd: (_) => _dragEnd(),
                  onPanCancel: _dragEnd,
                  child: Stack(children: children),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Win98Button(onPressed: _redeal, child: const Text('Restart')),
                const SizedBox(width: 4),
                Win98Button(
                  onPressed: () => showGameHelp(
                    context,
                    game: 'Solitaire',
                    icon: PixelIcon.cards,
                    howTo: const [
                      'Drag a face-up card onto another column, one lower and the other colour (red on black). '
                          'Drag a run of cards to move them together.',
                      'Only a King goes into an empty column.',
                      'Build each suit home in the top right, Ace to King.',
                      'Tap the deck for a new card; tap it empty to turn the pile over.',
                      'Win by getting all 52 cards home.',
                    ],
                  ),
                  child: const Text('Help'),
                ),
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
