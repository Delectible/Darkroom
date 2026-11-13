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
            child: _FolderInk(
              ink: W98.windowInk,
              child: IconGroup(
                items: [for (final (icon, name, open) in items) (icon, name, () => open(context))],
                builder: (icons) => Wrap(spacing: 4, runSpacing: 10, children: icons),
              ),
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

/// A 32 px icon with its name under it, as on the 9x desktop or a folder
/// in large icons: a tap selects it (the name in the highlight, the icon
/// dimmed), a second tap or a double tap opens it.
class DesktopIcon extends StatelessWidget {
  const DesktopIcon({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
    this.ink,
  });

  final PixelIcon icon;
  final String label;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onOpen;

  /// The label's colour unselected (default: white, for the desktop).
  final Color? ink;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: selected ? onOpen : onSelect,
      onDoubleTap: onOpen,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // (selected: the 9x blue wash over the icon)
            ColorFiltered(
              colorFilter: selected
                  ? ColorFilter.mode(W98.navy.withValues(alpha: 0.5), BlendMode.srcATop)
                  : const ColorFilter.mode(Color(0x00000000), BlendMode.dst),
              child: PixelIconView(icon, size: 32),
            ),
            const SizedBox(height: 3),
            DecoratedBox(
              decoration: selected
                  ? BoxDecoration(
                      color: W98.navy,
                      border: Border.all(color: const Color(0xFFFFFF80), width: 0.5),
                    )
                  : const BoxDecoration(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: W98.text.copyWith(color: selected ? W98.selectInk : (ink ?? W98.selectInk)),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Icons that select with a tap and open with another (or a double tap);
/// a tap on the empty space around them clears the selection.
class IconGroup extends StatefulWidget {
  const IconGroup({super.key, required this.items, required this.builder});

  /// (icon, name, open)
  final List<(PixelIcon, String, VoidCallback)> items;

  /// Lays out the icons (a desktop column, a folder's rows).
  final Widget Function(List<Widget> icons) builder;

  @override
  State<IconGroup> createState() => _IconGroupState();
}

class _IconGroupState extends State<IconGroup> {
  String? _selected;

  /// A label colour for the icons (null: the desktop's white).
  Color? get _ink => context.findAncestorWidgetOfExactType<_FolderInk>()?.ink;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onTap: () => setState(() => _selected = null),
    child: widget.builder([
      for (final (icon, name, open) in widget.items)
        DesktopIcon(
          icon: icon,
          label: name,
          ink: _ink,
          selected: _selected == name,
          onSelect: () => setState(() => _selected = name),
          onOpen: () {
            setState(() => _selected = null);
            open();
          },
        ),
    ]),
  );
}

/// The label colour for the icons under it (a folder's black on white).
class _FolderInk extends InheritedWidget {
  const _FolderInk({required this.ink, required super.child});

  final Color ink;

  @override
  bool updateShouldNotify(_FolderInk old) => old.ink != ink;
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
