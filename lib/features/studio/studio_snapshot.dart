import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/device/haptics.dart';
import 'studio_store.dart';

/// A maker's page: slides in like any page, but closes at once (under the
/// snapshot's white flash, see [popWithFlash]).
Route<T> makerRoute<T>(Widget page) => PageRouteBuilder<T>(
  transitionDuration: const Duration(milliseconds: 300),
  reverseTransitionDuration: Duration.zero,
  pageBuilder: (_, _, _) => page,
  transitionsBuilder: (_, a, _, child) => SlideTransition(
    position: Tween(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
    child: FadeTransition(opacity: a, child: child),
  ),
);

/// The "snapshot": the screen flashes white, then the maker closes with
/// [work] (the Studio picks the flash up and drops the piece on the table,
/// see [showSnapshotDrop]).
Future<void> popWithFlash(BuildContext context, StudioWork work) async {
  final overlay = Overlay.of(context, rootOverlay: true);
  final white = ValueNotifier(0.0);
  final entry = OverlayEntry(
    builder: (_) => IgnorePointer(
      child: ValueListenableBuilder(
        valueListenable: white,
        builder: (_, v, _) => ColoredBox(color: Color.fromRGBO(255, 255, 255, v)),
      ),
    ),
  );
  overlay.insert(entry);
  unawaited(Haptics.lightImpact());
  const steps = 7;
  for (var i = 1; i <= steps; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    white.value = i / steps;
  }
  if (context.mounted) Navigator.of(context).pop(work);
  // (the Studio's own white takes over from here)
  await Future<void>.delayed(const Duration(milliseconds: 60));
  entry.remove();
  white.dispose();
}

/// The new piece, just made: out of the white flash, held up big, then
/// dropped onto the table, where it lands, settles, and fades away.
Future<void> showSnapshotDrop(BuildContext context, StudioWork work) => Navigator.of(context).push(
  PageRouteBuilder<void>(
    opaque: false,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (_, _, _) => _SnapshotDrop(work: work),
  ),
);

class _SnapshotDrop extends StatefulWidget {
  const _SnapshotDrop({required this.work});

  final StudioWork work;

  @override
  State<_SnapshotDrop> createState() => _SnapshotDropState();
}

class _SnapshotDropState extends State<_SnapshotDrop> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  bool _landed = false;

  // the moments, as fractions of the whole
  static const _held = 0.22, _land = 0.5, _settled = 0.64, _fade = 0.84;

  @override
  void initState() {
    super.initState();
    _t.addListener(() {
      if (!_landed && _t.value >= _land) {
        _landed = true;
        unawaited(Haptics.mediumImpact());
      }
      setState(() {});
    });
    unawaited(
      _t.forward().whenComplete(() {
        if (mounted) Navigator.of(context).pop();
      }),
    );
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  double _span(double a, double b, [Curve curve = Curves.linear]) =>
      curve.transform(((_t.value - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final path = widget.work.cover ?? widget.work.path;
    // out of the white
    final white = 1 - _span(0, 0.14, Curves.easeOut);
    // the drop: from held up (big, high shadow) to on the table
    final drop = _span(_held, _land, Curves.easeInCubic);
    // a little bounce and turn as it settles
    final settle = _span(_land, _settled);
    final bounce = math.sin(settle * math.pi) * (1 - settle) * 0.035;
    final scale = 1 - 0.36 * drop + bounce;
    final turn = -0.07 * drop + 0.025 * math.sin(settle * math.pi * 1.5) * (1 - settle);
    final lift = 1 - drop; // 1 held up, 0 on the table
    final fade = 1 - _span(_fade, 1, Curves.easeIn);
    final dim = 0.45 * (1 - _span(_land, 1)) * fade;
    final size = MediaQuery.sizeOf(context);
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Color.fromRGBO(0, 0, 0, dim)),
          Opacity(
            opacity: fade,
            child: Center(
              child: Transform.translate(
                offset: Offset(0, size.height * 0.06 * drop),
                child: Transform.rotate(
                  angle: turn,
                  child: Transform.scale(
                    scale: scale,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: size.width * 0.78, maxHeight: size.height * 0.6),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Color.fromRGBO(0, 0, 0, 0.35 + 0.2 * (1 - lift)),
                              blurRadius: 6 + 34 * lift,
                              offset: Offset(2 + 10 * lift, 4 + 36 * lift),
                            ),
                          ],
                        ),
                        child: Image.file(File(path), fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (white > 0) ColoredBox(color: Color.fromRGBO(255, 255, 255, white)),
        ],
      ),
    );
  }
}
