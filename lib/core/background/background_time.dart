import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOS suspends an app a few seconds after it leaves the screen, which would
/// pause a shot that is still being processed until the next launch. While
/// [pending] is above zero this holds an iOS background task (about 30 s of
/// extra time), so a shot taken just before leaving still gets finished.
/// Development itself needs no background time: prints store an absolute
/// `ready_at` and the notifications are scheduled ahead. No-op elsewhere
/// (Android keeps the process running).
class BackgroundTime {
  BackgroundTime(this.pending, {MethodChannel? channel, bool? enabled})
    : _channel = channel ?? const MethodChannel('darkroom/background'),
      _enabled = enabled ?? Platform.isIOS {
    if (_enabled) {
      pending.addListener(_sync);
      _sync();
    }
  }

  final ValueListenable<int> pending;
  final MethodChannel _channel;
  final bool _enabled;
  bool _held = false;

  void _sync() {
    final want = pending.value > 0;
    if (want == _held) return;
    _held = want;
    _channel.invokeMethod<void>(want ? 'begin' : 'end').catchError((Object _) {});
  }

  void dispose() {
    if (!_enabled) return;
    pending.removeListener(_sync);
    if (_held) _channel.invokeMethod<void>('end').catchError((Object _) {});
  }
}
