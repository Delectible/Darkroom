import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
/// give their route `settings: UprightApp.landscape`. The app is portrait
/// otherwise; while such a screen is the top page (once it has slid in) and
/// the phone is held sideways, [UprightApp] really rotates the app, so the
/// status bar, the back gesture and the home bar are on the right edges.
/// It goes back to portrait as the screen slides out. The camera screen
/// below keeps its portrait layout ([PortraitLock]).
class UprightApp extends ConsumerStatefulWidget {
  const UprightApp({super.key, required this.child});

  static const landscape = RouteSettings(name: 'upright-landscape');

  /// Tracks the top page for [UprightApp]; add to MaterialApp's observers.
  static final observer = _UprightObserver();

  /// The way the app was last turned to landscape.
  static DeviceOrientation lastLandscape = DeviceOrientation.landscapeLeft;

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
        // While heroes are measured on push, the route is briefly
        // offstage and its animation reads "completed": not arrived yet.
        if (s == AnimationStatus.completed && !(top as ModalRoute).offstage) {
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

class _UprightAppState extends ConsumerState<UprightApp> {
  DeviceOrientation _asked = DeviceOrientation.portraitUp;

  @override
  void initState() {
    super.initState();
    UprightApp.observer.allowed.addListener(_apply);
  }

  @override
  void dispose() {
    UprightApp.observer.allowed.removeListener(_apply);
    super.dispose();
  }

  void _apply() {
    final o = ref.read(physicalOrientationProvider);
    final want = UprightApp.observer.allowed.value && isLandscape(o) ? o : DeviceOrientation.portraitUp;
    if (want == _asked) return;
    _asked = want;
    if (want != DeviceOrientation.portraitUp) UprightApp.lastLandscape = want;
    unawaited(SystemChrome.setPreferredOrientations([want]));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(physicalOrientationProvider, (_, _) => _apply());
    return widget.child;
  }
}

/// Keeps a portrait-only screen (the camera) laid out upright while the app
/// is turned to landscape for a screen above it: it sits turned back, as if
/// the app were still portrait. The same widgets either way, so it keeps
/// its state.
class PortraitLock extends StatelessWidget {
  const PortraitLock({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final land = mq.size.width > mq.size.height;
    final q = !land ? 0 : (UprightApp.lastLandscape == DeviceOrientation.landscapeRight ? 1 : 3);
    EdgeInsets turn(EdgeInsets e) => switch (q) {
      1 => EdgeInsets.fromLTRB(e.top, e.right, e.bottom, e.left),
      3 => EdgeInsets.fromLTRB(e.bottom, e.left, e.top, e.right),
      _ => e,
    };
    return RotatedBox(
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
        child: child,
      ),
    );
  }
}
