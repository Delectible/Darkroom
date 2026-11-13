import 'package:material_ui/material_ui.dart';

import '../pixel_icons.dart';
import '../win98_widgets.dart';
import 'bricks.dart';
import 'high_scores.dart';
import 'minesweeper.dart';
import 'pinball.dart';
import 'solitaire.dart';

/// The desktop's Games folder: every game, and High Scores, as big icons
/// in a folder window. A tap opens one (the folder stays open under it).
Future<void> showGamesFolder(BuildContext context) => showWin98Window<void>(
  context,
  title: 'Games',
  width: 300,
  icon: const PixelIconView(PixelIcon.joystick),
  builder: (context) => const _GamesFolder(),
);

class _GamesFolder extends StatelessWidget {
  const _GamesFolder();

  @override
  Widget build(BuildContext context) {
    final items = <(PixelIcon, String, Future<void> Function(BuildContext))>[
      (PixelIcon.cards, 'Solitaire', showSolitaire),
      (PixelIcon.mine, 'Minefield', showMinesweeper),
      (PixelIcon.bricks, 'Bricks', showBricks),
      (PixelIcon.pinball, 'Pinball', showPinball),
      (PixelIcon.trophy, 'High Scores', showHighScores),
    ];
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Win98Bevel(
            style: BevelStyle.sunken,
            color: W98.window,
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
            child: Wrap(
              spacing: 4,
              runSpacing: 10,
              children: [
                for (final (icon, name, open) in items)
                  DesktopIcon(icon: icon, label: name, ink: W98.windowInk, onOpen: () => open(context)),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Win98Bevel(
            style: BevelStyle.shallow,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text('${items.length} object(s)'),
          ),
        ],
      ),
    );
  }
}

/// A 32 px icon with its name under it, opened with a tap (a desktop's,
/// or a folder's in large icons).
class DesktopIcon extends StatelessWidget {
  const DesktopIcon({super.key, required this.icon, required this.label, required this.onOpen, this.ink});

  final PixelIcon icon;
  final String label;
  final VoidCallback onOpen;

  /// The label's colour (default: white, for the desktop).
  final Color? ink;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PixelIconView(icon, size: 32),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: W98.text.copyWith(color: ink ?? W98.selectInk),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Each game's best so far.
Future<void> showHighScores(BuildContext context) => showWin98Window<void>(
  context,
  title: 'High Scores',
  width: 280,
  icon: const PixelIconView(PixelIcon.trophy),
  builder: (context) {
    final rows = HighScores.table(context);
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Win98Bevel(
            style: BevelStyle.sunken,
            color: W98.window,
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, (game, what, value)) in rows.indexed) ...[
                  if (i > 0 && rows[i - 1].$1 != game) const SizedBox(height: 6),
                  Row(
                    children: [
                      SizedBox(
                        width: 76,
                        child: Text(
                          i == 0 || rows[i - 1].$1 != game ? game : '',
                          style: W98.text.copyWith(color: W98.windowInk, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Expanded(
                        child: Text(what, style: W98.text.copyWith(color: W98.windowInk)),
                      ),
                      Text(value, style: W98.text.copyWith(color: W98.windowInk)),
                    ],
                  ),
                ],
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
