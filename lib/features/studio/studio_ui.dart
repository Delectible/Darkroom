import 'package:material_ui/material_ui.dart';

import 'studio_screen.dart';

/// The Studio's own lettering and controls, so nothing in it looks like a
/// stock phone screen: spaced capitals for titles (THE STUDIO, FLIP BOOK),
/// small spaced labels for options, pill choices in brass, warm dialogs.

/// A section label over options: small spaced capitals.
class StudioLabel extends StatelessWidget {
  const StudioLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      color: StudioInk.muted,
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.6,
    ),
  );
}

/// The title bar of a Studio page: back, a title in spaced capitals (or,
/// for the scrapbook, handwriting), a line under it, and actions.
class StudioTitleBar extends StatelessWidget implements PreferredSizeWidget {
  const StudioTitleBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.handwritten = false,
    this.background = StudioInk.tableDark,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// The title in handwriting, a touch tilted (the scrapbook).
  final bool handwritten;
  final Color background;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final Widget heading = handwritten
        ? Transform.rotate(
            angle: -0.03,
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              style: const TextStyle(
                fontFamily: 'Caveat',
                fontWeight: FontWeight.w600,
                fontSize: 32,
                height: 1,
                color: StudioInk.paper,
              ),
            ),
          )
        : Text(
            title.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: StudioInk.label,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              fontSize: 16,
            ),
          );
    return Material(
      color: background,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: preferredSize.height,
          child: Row(
            children: [
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: StudioInk.ink),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    heading,
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: StudioInk.muted, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              ...actions,
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// A choice as a pill: brass when picked, an outline when not.
class StudioChip extends StatelessWidget {
  const StudioChip({super.key, required this.label, required this.selected, required this.onTap, this.style});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// The label's own lettering (the scrapbook's fonts show themselves).
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? StudioInk.brass : const Color(0x1AF3E9D8),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: selected ? StudioInk.brass : const Color(0x55C9A57A), width: 1.2),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? const Color(0xFF22150B) : StudioInk.ink,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 13,
            letterSpacing: 0.3,
          ).merge(style),
        ),
      ),
    ),
  );
}

ThemeData _dialogTheme(BuildContext context) => Theme.of(context).copyWith(
  dialogTheme: DialogThemeData(
    backgroundColor: const Color(0xFF2A1F17),
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0x33D9A35B)),
    ),
    titleTextStyle: const TextStyle(
      color: StudioInk.label,
      fontWeight: FontWeight.w900,
      letterSpacing: 2,
      fontSize: 15,
      height: 1.3,
    ),
    contentTextStyle: const TextStyle(color: StudioInk.ink, fontSize: 14, height: 1.4),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: StudioInk.muted,
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: StudioInk.brass,
      foregroundColor: const Color(0xFF22150B),
      textStyle: const TextStyle(fontWeight: FontWeight.w800),
    ),
  ),
  textSelectionTheme: const TextSelectionThemeData(
    cursorColor: StudioInk.brass,
    selectionColor: Color(0x55D9A35B),
    selectionHandleColor: StudioInk.brass,
  ),
);

/// A question in the Studio's own dialog: true for [yes].
Future<bool?> studioAsk(
  BuildContext context, {
  required String title,
  required String message,
  required String yes,
  required String no,
}) => showDialog<bool>(
  context: context,
  builder: (context) => Theme(
    data: _dialogTheme(context),
    child: AlertDialog(
      title: Text(title.toUpperCase()),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(no)),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(yes)),
      ],
    ),
  ),
);

/// A line or two of writing in the Studio's dialog; null if cancelled.
Future<String?> studioWrite(BuildContext context, String title, String initial, {int max = 80}) =>
    showDialog<String>(
      context: context,
      builder: (context) {
        final c = TextEditingController(text: initial);
        return Theme(
          data: _dialogTheme(context),
          child: AlertDialog(
            title: Text(title.toUpperCase()),
            content: TextField(
              controller: c,
              autofocus: true,
              maxLength: max,
              maxLines: 3,
              minLines: 1,
              style: const TextStyle(color: StudioInk.paper, fontSize: 16),
              decoration: const InputDecoration(
                counterStyle: TextStyle(color: StudioInk.muted),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0x66C9A57A))),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: StudioInk.brass, width: 2)),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('OK')),
            ],
          ),
        );
      },
    );

/// A short note at the foot of a Studio page, in its colours.
void studioNote(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: const Color(0xFF2A1F17),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: Color(0x33D9A35B)),
    ),
    content: Text(
      text,
      style: const TextStyle(color: StudioInk.ink, fontWeight: FontWeight.w600),
    ),
  ),
);
