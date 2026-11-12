import 'dart:async';

import 'package:flutter/material.dart';

import '../navigation.dart';

/// The app's one look for a passing message: a dark box with light text
/// (as the camera's "Loading film…"), and at most one action in it.
class NoteBox extends StatelessWidget {
  const NoteBox({super.key, required this.text, this.action, this.onAction, this.onTap, this.onClose});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  /// A tap on the message itself (Notes: closes it).
  final VoidCallback? onTap;

  /// A small × after the action, to wave it off (a note that waits for an
  /// answer: it needn't be waited out).
  final VoidCallback? onClose;

  static const fill = Color(0xE6121214);
  static const edge = Color(0x38FFFFFF);
  static const ink = Color(0xFFF1ECE2);
  static const accent = Color(0xFFF2C46D);

  static const style = TextStyle(
    color: ink,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
    height: 1.3,
    decoration: TextDecoration.none,
  );

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    return DefaultTextStyle(style: base.merge(style), child: _box());
  }

  Widget _box() {
    final label = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Text(text, textAlign: action == null ? TextAlign.center : TextAlign.start, style: style),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: edge),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 3))],
      ),
      child: action == null
          ? Padding(padding: const EdgeInsets.fromLTRB(18, 11, 18, 12), child: label)
          : IntrinsicHeight(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Padding(padding: const EdgeInsets.fromLTRB(18, 11, 14, 12), child: label),
                  ),
                  const VerticalDivider(width: 1, thickness: 1, color: edge),
                  Semantics(
                    button: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onAction,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Center(
                          child: Text(
                            action!.toUpperCase(),
                            style: style.copyWith(color: accent, fontSize: 13, letterSpacing: 1.2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (onClose != null)
                    Semantics(
                      button: true,
                      label: 'Close',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onClose,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 12, 0),
                          child: Center(
                            child: Text(
                              '×',
                              style: style.copyWith(color: ink.withValues(alpha: 0.6), fontSize: 20),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// Passing messages anywhere in the app (saved, couldn't, undo): a
/// [NoteBox] at the foot of the screen over whatever is there, fading in
/// and away. One at a time; a new one replaces it.
class Notes {
  Notes._();

  static final _now = ValueNotifier<_Note?>(null);
  static OverlayEntry? _entry;
  static int _serial = 0;

  /// Shows [text] (with [action], it stays longer and the action closes
  /// it). A tap on it closes it; [onClosed] hears how it went (true: the
  /// user closed it; false: timed out, its action, or another came).
  ///
  /// [context]: the screen it's about. It goes when that screen does (slid
  /// away back to the camera, say), not left over whatever comes next.
  static int show(
    String text, {
    String? action,
    VoidCallback? onAction,
    Duration? duration,
    void Function(bool byUser)? onClosed,
    BuildContext? context,
  }) {
    final overlay = appNavigatorKey.currentState?.overlay;
    if (overlay == null) return -1;
    if (_entry == null || !_entry!.mounted) {
      _entry = OverlayEntry(builder: (_) => const _NotesView());
      overlay.insert(_entry!);
    }
    final me = ++_serial;
    final was = _now.value;
    was?.onClosed?.call(false);
    was?.release?.call();
    VoidCallback? release;
    final route = context == null ? null : ModalRoute.of(context);
    final leaving = route?.animation;
    if (leaving != null) {
      void watch(AnimationStatus s) {
        if (s == AnimationStatus.reverse || s == AnimationStatus.dismissed) hide(me);
      }

      leaving.addStatusListener(watch);
      release = () => leaving.removeStatusListener(watch);
    }
    _now.value = _Note(text, action, onAction, me, onClosed, release);
    final shown =
        duration ??
        (action != null
            ? const Duration(seconds: 6)
            : Duration(milliseconds: (1800 + text.length * 45).clamp(1800, 5000)));
    Timer(shown, () => hide(me));
    return me;
  }

  /// A message is up (not fading out).
  static bool get showing => _now.value != null;

  /// Hides the message showing (only if it's still [serial], when given).
  static void hide([int? serial, bool byUser = false]) {
    final n = _now.value;
    if (n == null || (serial != null && n.serial != serial)) return;
    _now.value = null;
    n.release?.call();
    n.onClosed?.call(byUser);
  }
}

class _Note {
  const _Note(this.text, this.action, this.onAction, this.serial, this.onClosed, this.release);

  /// Stops watching the screen it belongs to.
  final VoidCallback? release;

  final String text;
  final String? action;
  final VoidCallback? onAction;
  final int serial;
  final void Function(bool byUser)? onClosed;
}

class _NotesView extends StatefulWidget {
  const _NotesView();

  @override
  State<_NotesView> createState() => _NotesViewState();
}

class _NotesViewState extends State<_NotesView> {
  /// Kept while it fades out.
  _Note? _last;

  /// The one swiped away (gone at once: no fade to keep it for).
  int? _swiped;

  @override
  Widget build(BuildContext context) {
    // (low on the screen, clear of the buttons most screens keep at the foot)
    final mq = MediaQuery.of(context);
    final bottom = mq.padding.bottom + mq.size.height * 0.15;
    return ValueListenableBuilder<_Note?>(
      valueListenable: Notes._now,
      builder: (context, note, _) {
        if (note != null) _last = note;
        final last = _last;
        if (last == null || last.serial == _swiped) return const SizedBox.shrink();
        final on = note != null;
        return Positioned(
          // (well inside the viewfinder's width, clear of the tabs at the
          // screen's sides)
          left: 64,
          right: 64,
          bottom: bottom,
          child: IgnorePointer(
            ignoring: !on,
            child: AnimatedSlide(
              offset: on ? Offset.zero : const Offset(0, 0.25),
              duration: Duration(milliseconds: on ? 220 : 420),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: on ? 1 : 0,
                duration: Duration(milliseconds: on ? 180 : 420),
                curve: Curves.easeOut,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    // (over any screen: the app's own text style under it)
                    // (swiped away, sideways or down: closed by the user)
                    child: Dismissible(
                      key: ValueKey(last.serial),
                      direction: DismissDirection.horizontal,
                      onDismissed: (_) {
                        setState(() => _swiped = last.serial);
                        Notes.hide(last.serial, true);
                      },
                      child: NoteBox(
                        text: last.text,
                        action: last.action,
                        onAction: () {
                          Notes.hide(last.serial);
                          last.onAction?.call();
                        },
                        onTap: () => Notes.hide(last.serial, true),
                        onClose: last.action == null ? null : () => Notes.hide(last.serial, true),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
