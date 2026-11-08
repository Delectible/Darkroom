import 'package:flutter/widgets.dart';

/// [child] turned by [quarterTurns] to read upright. When the phone is turned
/// the old way round fades out as the new one fades (and grows a touch) in,
/// so a readout that turns in place blends round instead of snapping.
class TurnFade extends StatelessWidget {
  const TurnFade({
    super.key,
    required this.quarterTurns,
    required this.child,
    this.alignment = Alignment.center,
  });

  final int quarterTurns;
  final Widget child;

  /// Where the two ways round meet: the corner the readout is pinned by.
  final AlignmentGeometry alignment;

  static const duration = Duration(milliseconds: 280);

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: duration,
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    // The box is the new way round's from the start, the old one fading out
    // over it (its own size, from the pinned corner): the box changing size
    // once the old one had gone made the readout jump.
    layoutBuilder: (current, previous) => Stack(
      alignment: alignment,
      clipBehavior: Clip.none,
      children: [
        for (final p in previous)
          Positioned.fill(
            child: IgnorePointer(
              child: OverflowBox(
                alignment: alignment,
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                child: p,
              ),
            ),
          ),
        ?current,
      ],
    ),
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween(begin: 0.88, end: 1.0).animate(animation),
        alignment: Alignment.center,
        child: child,
      ),
    ),
    child: RotatedBox(key: ValueKey(quarterTurns), quarterTurns: quarterTurns, child: child),
  );
}
