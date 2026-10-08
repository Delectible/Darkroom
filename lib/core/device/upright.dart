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

/// Screens that turn to landscape with the phone (corkboard, Win98...):
/// give their route `settings: UprightApp.landscape`. The activity stays
/// portrait-locked; [UprightApp] turns the whole UI (dialogs and menus
/// included) while such a screen is the top page.
class UprightApp extends ConsumerStatefulWidget {
  const UprightApp({super.key, required this.child});

  static const landscape = RouteSettings(name: 'upright-landscape');

  /// Tracks the top page for [UprightApp]; add to MaterialApp's observers.
  static final observer = _UprightObserver();

  final Widget child;

  @override
  ConsumerState<UprightApp> createState() => _UprightAppState();
}

class _UprightObserver extends NavigatorObserver {
  final allowed = ValueNotifier<bool>(false);
  final _stack = <Route<dynamic>>[];

  void _update() {
    final top = _stack.lastWhere(
      (r) => r is PageRoute,
      orElse: () => _stack.isEmpty ? _NoRoute() : _stack.first,
    );
    final ok = top.settings.name == UprightApp.landscape.name;
    if (!ok) {
      allowed.value = false;
      return;
    }
    // Turn once the screen has finished arriving (it slides in upright).
    final a = top is ModalRoute ? top.animation : null;
    if (a == null || a.isCompleted) {
      allowed.value = true;
    } else {
      void done(AnimationStatus s) {
        if (s == AnimationStatus.completed) {
          a.removeStatusListener(done);
          if (_stack.isNotEmpty &&
              identical(_stack.lastWhere((r) => r is PageRoute, orElse: () => top), top)) {
            allowed.value = true;
          }
        }
      }

      a.addStatusListener(done);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    _update();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _update();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _update();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (i >= 0 && newRoute != null) {
      _stack[i] = newRoute;
    } else if (newRoute != null) {
      _stack.add(newRoute);
    }
    _update();
  }
}

class _NoRoute extends Route<void> {}

class _UprightAppState extends ConsumerState<UprightApp> with SingleTickerProviderStateMixin {
  late final _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 150), value: 1);
  int _shown = 0;
  int _want = 0;

  @override
  void initState() {
    super.initState();
    UprightApp.observer.allowed.addListener(_retarget);
  }

  @override
  void dispose() {
    UprightApp.observer.allowed.removeListener(_retarget);
    _fade.dispose();
    super.dispose();
  }

  int _target() {
    if (!UprightApp.observer.allowed.value) return 0;
    return switch (uprightQuarterTurns(ref.read(physicalOrientationProvider))) {
      1 => 1,
      3 => 3,
      _ => 0, // upside down stays as it is
    };
  }

  /// Fades out, swaps the layout, fades back in (a quick turn, like an OS).
  Future<void> _retarget() async {
    final t = _target();
    if (t == _want) return;
    _want = t;
    await _fade.reverse();
    if (!mounted) return;
    setState(() => _shown = _want);
    await _fade.forward();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(physicalOrientationProvider, (_, _) => _retarget());
    final q = _shown;
    final mq = MediaQuery.of(context);
    EdgeInsets turn(EdgeInsets e) => switch (q) {
      1 => EdgeInsets.fromLTRB(e.top, e.right, e.bottom, e.left),
      3 => EdgeInsets.fromLTRB(e.bottom, e.left, e.top, e.right),
      _ => e,
    };
    // Same widgets whether turned or not: the navigator below keeps its state.
    final child = RotatedBox(
      quarterTurns: q,
      child: MediaQuery(
        data: q == 0
            ? mq
            : mq.copyWith(
                size: mq.size.flipped,
                padding: turn(mq.padding),
                viewPadding: turn(mq.viewPadding),
                viewInsets: turn(mq.viewInsets),
                systemGestureInsets: turn(mq.systemGestureInsets),
              ),
        child: widget.child,
      ),
    );
    return ColoredBox(
      color: Colors.black,
      child: FadeTransition(
        opacity: _fade,
        child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(_fade), child: child),
      ),
    );
  }
}
