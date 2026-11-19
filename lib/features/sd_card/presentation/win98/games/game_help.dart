import 'package:material_ui/material_ui.dart';

import '../pixel_icons.dart';
import '../win98_widgets.dart';
import 'high_scores.dart';

/// A game's Help: how to play, in a few lines, and its best scores so far
/// ([game]: its name in the High Scores table).
Future<void> showGameHelp(
  BuildContext context, {
  required String game,
  required PixelIcon icon,
  required List<String> howTo,
}) => showWin98Window<void>(
  context,
  title: '$game Help',
  width: 290,
  icon: PixelIconView(icon),
  builder: (context) {
    final scores = [
      for (final r in HighScores.table(context))
        if (r.$1 == game) r,
    ];
    final ink = W98.text.copyWith(color: W98.windowInk);
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('How to play', style: W98.text.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Win98Bevel(
            style: BevelStyle.sunken,
            color: W98.window,
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, line) in howTo.indexed) ...[
                  if (i > 0) const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('•  ', style: ink),
                      Expanded(child: Text(line, style: ink)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text('High scores', style: W98.text.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Win98Bevel(
            style: BevelStyle.sunken,
            color: W98.window,
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (_, what, value) in scores)
                  Row(
                    children: [
                      Expanded(child: Text(what, style: ink)),
                      Text(value, style: ink),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Win98Button(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ),
        ],
      ),
    );
  },
);
