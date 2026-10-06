import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The phone's own gestures: back from the side edges, the notification
/// shade from the top, home from the bottom. Our drags must not start in
/// those strips, or a swipe meant for the phone also moves the camera.
class SystemGestureZones {
  const SystemGestureZones._();

  /// Width of the back-gesture strip on each side.
  static double side(MediaQueryData media) =>
      math.max(math.max(media.systemGestureInsets.left, media.systemGestureInsets.right), 24) + 8;

  /// Height of the notification-shade strip at the top.
  static double top(MediaQueryData media) => math.max(media.padding.top, media.systemGestureInsets.top) + 8;

  /// Height of the home-gesture strip at the bottom.
  static double bottom(MediaQueryData media) => math.max(56, media.systemGestureInsets.bottom + 32);

  /// Whether a touch at [global] began in the back or shade strip. [allowed]
  /// rects (e.g. where Android was asked to give the edge to us) don't count.
  static bool startsInEdge(BuildContext context, Offset global, {List<Rect> allowed = const []}) {
    final media = MediaQuery.of(context);
    if (allowed.any((r) => r.contains(global))) return false;
    final s = side(media);
    return global.dx < s || global.dx > media.size.width - s || global.dy < top(media);
  }
}

/// Asks Android (10+) to keep its back gesture off [rects] (logical pixels),
/// so they can be dragged from the very edge. Android honours at most 200dp
/// of each edge. No-op elsewhere.
class GestureExclusion {
  const GestureExclusion._();

  static const _channel = MethodChannel('darkroom/gestures');

  static Future<void> set(List<Rect> rects, double dpr) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('exclude', [
        for (final r in rects) ...[r.left, r.top, r.right, r.bottom].map((v) => (v * dpr).round()),
      ]);
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }

  static Future<void> clear() => set(const [], 1);
}
