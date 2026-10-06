import 'package:flutter/material.dart';
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

/// A bottom sheet that respects how the phone is held: the usual sheet in
/// portrait; held sideways (the activity stays portrait-locked) a panel laid
/// out in the user's landscape frame, so it reads the right way up.
Future<T?> showUprightSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext context, {required bool landscape}) builder,
  Color? backgroundColor,
  double maxWidth = 560,
}) {
  final turns = uprightQuarterTurns(ProviderScope.containerOf(context).read(physicalOrientationProvider));
  const shape = RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16)));
  if (turns.isEven) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: backgroundColor,
      shape: shape,
      builder: (context) => builder(context, landscape: false),
    );
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'sheet',
    barrierColor: const Color(0x88000000),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => UprightBox(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Material(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: builder(context, landscape: true),
            ),
          ),
        ),
      ),
    ),
  );
}
