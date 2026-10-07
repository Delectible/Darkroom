import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/features/sd_card/presentation/win98/games/bricks.dart';
import 'package:darkroom/features/sd_card/presentation/win98/games/minesweeper.dart';
import 'package:darkroom/features/sd_card/presentation/win98/games/pinball.dart';
import 'package:darkroom/features/sd_card/presentation/win98/games/solitaire.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Run... games: Klondike's rules, and each game running for a few
/// seconds at phone size without errors. `SHOTS=dir` saves a frame of each.
void main() {
  final shots = Platform.environment['SHOTS'];

  group('Klondike', () {
    test('deals 28 cards to the columns, 24 to the deck', () {
      final k = Klondike(seed: 1);
      expect([for (final c in k.tableau) c.length], [1, 2, 3, 4, 5, 6, 7]);
      expect(k.tableau.every((c) => c.last.up && c.where((x) => x.up).length == 1), isTrue);
      expect(k.stock.length, 24);
    });

    test('deal turns one card; an empty deck takes the pile back', () {
      final k = Klondike(seed: 2);
      for (var i = 0; i < 24; i++) {
        k.deal();
      }
      expect((k.stock.length, k.waste.length), (0, 24));
      k.deal();
      expect((k.stock.length, k.waste.length), (24, 0));
    });

    test('aces go home, and a tapped card lands on a legal column', () {
      // Play the whole deck by tapping; every move it makes must be legal.
      for (var seed = 0; seed < 20; seed++) {
        final k = Klondike(seed: seed);
        for (var round = 0; round < 400; round++) {
          var moved = k.tapWaste();
          for (var c = 0; c < 7 && !moved; c++) {
            final col = k.tableau[c];
            final first = col.indexWhere((x) => x.up);
            if (first >= 0) moved = k.tapTableau(c, first) || k.tapTableau(c, col.length - 1);
          }
          if (!moved) k.deal();
        }
        for (final f in k.foundations) {
          for (var i = 0; i < f.length; i++) {
            expect(f[i].rank, i + 1);
            expect(f[i].suit, f.first.suit);
          }
        }
        for (final col in k.tableau) {
          final up = col.where((x) => x.up).toList();
          for (var i = 1; i < up.length; i++) {
            expect(up[i].rank, up[i - 1].rank - 1);
            expect(up[i].red, isNot(up[i - 1].red));
          }
        }
        expect(
          k.foundations.fold<int>(0, (n, f) => n + f.length) +
              k.stock.length +
              k.waste.length +
              k.tableau.fold<int>(0, (n, c) => n + c.length),
          52,
        );
      }
    });
  });

  group('Minesweeper', () {
    test('the first dig is safe and opens an area; the mines are all laid', () {
      for (var seed = 0; seed < 30; seed++) {
        final f = MineField(MineLevel.beginner, seed: seed);
        expect(f.dig(40), isTrue);
        expect(f.mine.where((m) => m).length, 10);
        expect(f.open[40], isTrue);
        for (final j in f.around(40)) {
          expect(f.mine[j], isFalse, reason: 'the squares round the first dig are clear');
        }
      }
    });

    test('digging every safe square wins; a mine loses', () {
      final f = MineField(MineLevel.beginner, seed: 3)..dig(0);
      for (var i = 0; i < f.cells; i++) {
        if (!f.mine[i]) f.dig(i);
      }
      expect(f.won, isTrue);
      final g = MineField(MineLevel.beginner, seed: 3)..dig(0);
      final mine = g.mine.indexOf(true);
      expect(g.dig(mine), isFalse);
      expect(g.lost, isTrue);
    });

    test('a number with its flags placed clears round it', () {
      final f = MineField(MineLevel.beginner, seed: 7)..dig(40);
      final n = List.generate(f.cells, (i) => i).firstWhere((i) => f.open[i] && f.count(i) > 0);
      for (final j in f.around(n)) {
        if (f.mine[j]) f.toggleFlag(j);
      }
      expect(f.chord(n), isTrue);
      expect(f.around(n).every((j) => f.open[j] || f.flag[j]), isTrue);
    });
  });

  testWidgets('pinball: a launched ball leaves the lane, plays, and drains', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: SizedBox(width: 280, child: PinballGame())),
      ),
    );
    final at = tester.getCenter(find.byType(PinballGame));
    final g = await tester.startGesture(at);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    var drained = false;
    for (var i = 0; i < 4000 && !drained; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      drained = find.textContaining('balls left').evaluate().isNotEmpty;
    }
    expect(drained, isTrue, reason: 'the ball should come down past the flippers eventually');
    expect(tester.takeException(), isNull);
  });

  for (final (name, game, height) in [
    ('solitaire', const SolitaireGame(), 430.0),
    ('bricks', const BricksGame(), 380.0),
    ('pinball', const PinballGame(), 560.0),
    ('minesweeper', const MinesweeperGame(), 420.0),
  ]) {
    testWidgets('$name runs', (tester) async {
      tester.view.physicalSize = const Size(1280, 2856);
      tester.view.devicePixelRatio = 3.1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox(width: 280, height: height, child: game),
              ),
            ),
          ),
        ),
      );
      final center = tester.getCenter(find.byWidget(game));
      // Serve / deal / pull and fire, then let it run.
      final g = await tester.startGesture(center + const Offset(0, 120));
      await tester.pump(const Duration(milliseconds: 600));
      await g.up();
      for (var i = 0; i < 180; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      if (name == 'pinball') {
        // Flip both flippers for a bit.
        final l = await tester.startGesture(center + const Offset(-80, 150));
        final r = await tester.startGesture(center + const Offset(80, 150));
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await l.up();
        await r.up();
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
      if (shots != null) {
        await tester.runAsync(() async {
          final ro = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await ro.toImage(pixelRatio: 2);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$shots/game_$name.png').writeAsBytes(png!.buffer.asUint8List());
        });
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
