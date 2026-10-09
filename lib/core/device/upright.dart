import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'physical_orientation.dart';

/// How the UI should treat the phone's orientation: the way it's held, but
/// always portrait while the phone's auto-rotate is off (Android), so
/// nothing on screen turns with it. The pictures themselves still follow
/// [physicalOrientationProvider] (saved upright, like the system camera).
final uprightOrientationProvider = Provider<DeviceOrientation>((ref) {
  final o = ref.watch(physicalOrientationProvider);
  return ref.watch(_autoRotateProvider) == false ? DeviceOrientation.portraitUp : o;
});

final _autoRotateProvider = NotifierProvider<_AutoRotateNotifier, bool?>(_AutoRotateNotifier.new);

class _AutoRotateNotifier extends Notifier<bool?> {
  @override
  bool? build() {
    void changed() => state = AutoRotate.value.value;
    AutoRotate.value.addListener(changed);
    ref.onDispose(() => AutoRotate.value.removeListener(changed));
    return AutoRotate.value.value;
  }
}

/// Keeps [child] upright for the user while the (portrait-locked) layout
/// stays put: turn the phone sideways and icons rotate in place, like the
/// system camera's.
class Upright extends ConsumerWidget {
  const Upright({super.key, required this.child, this.duration = const Duration(milliseconds: 320)});

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = ref.watch(uprightOrientationProvider);
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
    final q = uprightQuarterTurns(ref.watch(uprightOrientationProvider));
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
  final turns = uprightQuarterTurns(ProviderScope.containerOf(context).read(uprightOrientationProvider));
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

  /// While a landscape page fades out before the app turns: the
  /// orientation it keeps its layout for ([UprightPage]); null otherwise.
  static final held = ValueNotifier<DeviceOrientation?>(null);

  /// The landscape pages' opacity: turning the phone while one is up fades
  /// it out, turns the app, and fades it back in (no resize glitch).
  static final veil = ValueNotifier<double>(1);

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

class _UprightAppState extends ConsumerState<UprightApp> with WidgetsBindingObserver {
  List<DeviceOrientation> _asked = const [DeviceOrientation.portraitUp];

  /// A fade-turn-fade in progress ([_turn]).
  bool _turning = false;
  Timer? _settle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    UprightApp.observer.allowed.addListener(_apply);
    AutoRotate.value.addListener(_apply);
    unawaited(AutoRotate.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    UprightApp.observer.allowed.removeListener(_apply);
    AutoRotate.value.removeListener(_apply);
    _settle?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(AutoRotate.refresh());
  }

  @override
  void didChangeMetrics() {
    // The app has turned: fade back in once the size stops changing.
    if (!_turning) return;
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 90), _reveal);
  }

  void _reveal() {
    _settle?.cancel();
    UprightApp.veil.value = 1;
    _turning = false;
    // Turned again meanwhile?
    _apply(turned: true);
  }

  /// [turned]: the phone has just turned (else a page arrived or left, or
  /// auto-rotate changed).
  void _apply({bool turned = false}) {
    if (_turning) return;
    final o = ref.read(physicalOrientationProvider);
    final auto = AutoRotate.value.value;
    final List<DeviceOrientation> want;
    if (!UprightApp.observer.allowed.value || auto == false) {
      want = const [DeviceOrientation.portraitUp];
    } else if (auto == null) {
      // iOS: the system turns it (and keeps to the rotation lock).
      want = const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ];
    } else {
      want = [isLandscape(o) ? o : DeviceOrientation.portraitUp];
    }
    if (listEquals(want, _asked)) return;
    // A landscape page is up and the phone turned under it: it keeps its
    // layout while it fades out, then the app turns and it fades back in
    // (didChangeMetrics). Arriving already laid out turned, it just cuts.
    final from = _asked.length == 1 ? _asked.first : DeviceOrientation.portraitUp;
    if (turned && UprightApp.observer.allowed.value && auto == true && isLandscape(from) != isLandscape(o)) {
      _turning = true;
      UprightApp.held.value = from;
      UprightApp.veil.value = 0;
      Timer(UprightPage.fade, () {
        if (!mounted) return;
        UprightApp.held.value = null;
        _commit(want);
        // No metrics change (already that way round): don't stay dark.
        _settle?.cancel();
        _settle = Timer(const Duration(milliseconds: 600), _reveal);
      });
      return;
    }
    _commit(want);
  }

  void _commit(List<DeviceOrientation> want) {
    _asked = want;
    if (want.length == 1 && want.first != DeviceOrientation.portraitUp) UprightApp.lastLandscape = want.first;
    unawaited(SystemChrome.setPreferredOrientations(want));
    // Turned, the screens get the whole display: the status and nav bars
    // hide (a swipe from the edge brings them back for a moment).
    final turned = want.length > 1 || want.first != DeviceOrientation.portraitUp;
    unawaited(
      SystemChrome.setEnabledSystemUIMode(turned ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(physicalOrientationProvider, (_, _) => _apply(turned: true));
    return widget.child;
  }
}

/// Whether the phone's auto-rotate is on (Android, `darkroom/rotation`);
/// null where the system keeps that to itself (iOS turns the app, within
/// its rotation lock, on its own).
class AutoRotate {
  AutoRotate._();

  static const _channel = MethodChannel('darkroom/rotation');
  static final value = ValueNotifier<bool?>(null);
  static bool _listening = false;

  static Future<void> refresh() async {
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'autoRotate') value.value = call.arguments == true;
      });
    }
    try {
      value.value = await _channel.invokeMethod<bool>('autoRotate');
    } catch (_) {
      value.value = null; // no channel (iOS, tests)
    }
  }
}

/// A screen that turns to landscape (its route has [UprightApp.landscape]).
/// It slides in while the app is still portrait, then Android cuts straight
/// to landscape (no rotate animation, see MainActivity): so it doesn't pop,
/// it lays itself out in landscape, turned, from the start whenever the
/// phone is held sideways (and auto-rotate is on), and again as it slides
/// out. The same widgets either way, so it keeps its state.
class UprightPage extends ConsumerWidget {
  const UprightPage({super.key, required this.child});

  final Widget child;

  /// How long the page takes to fade out (and back in) as the phone turns.
  static const fade = Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final physical = ref.watch(physicalOrientationProvider);
    return ValueListenableBuilder<double>(
      valueListenable: UprightApp.veil,
      builder: (context, veil, child) => AnimatedOpacity(
        opacity: veil,
        duration: veil == 0 ? fade : fade * 1.6,
        curve: Curves.easeOut,
        child: child,
      ),
      child: ListenableBuilder(
        listenable: Listenable.merge([AutoRotate.value, UprightApp.held]),
        builder: (context, _) {
          final o = UprightApp.held.value ?? physical;
          final mq = MediaQuery.of(context);
          final portraitNow = mq.size.height >= mq.size.width;
          final q = AutoRotate.value.value == true && portraitNow && isLandscape(o)
              ? uprightQuarterTurns(o)
              : 0;
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
                      // as it will be, turned: no status / nav bars
                      padding: turn(mq.padding.copyWith(top: 0, bottom: 0)),
                      viewPadding: turn(mq.viewPadding.copyWith(top: 0, bottom: 0)),
                      viewInsets: turn(mq.viewInsets),
                      systemGestureInsets: turn(mq.systemGestureInsets),
                    ),
              child: child,
            ),
          );
        },
      ),
    );
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
