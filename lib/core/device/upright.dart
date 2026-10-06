import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'physical_orientation.dart';

/// Keeps [child] upright for the user while the (portrait-locked) layout
/// stays put: turn the phone sideways and icons rotate in place, like the
/// system camera's.
class Upright extends ConsumerWidget {
  const Upright({super.key, required this.child, this.duration = const Duration(milliseconds: 320)});

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = ref.watch(physicalOrientationProvider);
    return AnimatedRotation(
      turns: uprightTurns(o),
      duration: duration,
      curve: Curves.easeOutBack,
      child: child,
    );
  }
}

/// Lays [child] out in the user's frame of reference: a landscape box when
/// the phone is held sideways (fades between layouts on rotation).
class UprightBox extends ConsumerWidget {
  const UprightBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = uprightQuarterTurns(ref.watch(physicalOrientationProvider));
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: RotatedBox(key: ValueKey(q), quarterTurns: q, child: child),
    );
  }
}
