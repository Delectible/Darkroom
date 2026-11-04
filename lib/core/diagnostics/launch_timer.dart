import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How long each step of a launch took, from the start of Dart's main
/// (Win98 Help > Debug > Performance Report). The engine's own start, before
/// main, isn't in it. The last few launches are kept in prefs.
class LaunchTimer {
  LaunchTimer._();

  static final Stopwatch _clock = Stopwatch();
  static final List<(String, int)> _marks = [];
  static bool _done = false;

  /// Time from Android starting the process to Dart's main (engine,
  /// plugins), once known; null on iPhone.
  static int? beforeMain;

  /// Asks Android how long ago the process started (main.dart, early).
  static Future<void> measureBeforeMain() async {
    if (!Platform.isAndroid) return;
    final at = _clock.elapsedMilliseconds;
    try {
      final since = await const MethodChannel('darkroom/display').invokeMethod<int>('sinceStart');
      if (since != null) beforeMain = since - at;
    } catch (_) {}
  }

  /// Where the report is kept (set once prefs are open).
  static SharedPreferencesWithCache? prefs;

  static const _key = 'debug.launchTimes';
  static const _keep = 5;

  /// First thing in main.
  static void begin() => _clock
    ..reset()
    ..start();

  /// [label] happened now (ignored once the launch is over).
  static void mark(String label) {
    if (_done || !_clock.isRunning) return;
    _marks.add((label, _clock.elapsedMilliseconds));
  }

  /// [label] happened now, unless it already did this launch.
  static void once(String label) {
    if (_marks.any((m) => m.$1 == label)) return;
    mark(label);
  }

  /// The curtain is up and the app is in hand: the launch is over.
  static void finish(String label) {
    if (_done) return;
    mark(label);
    _done = true;
    final p = prefs;
    if (p == null) return;
    final kept = [_current(), ...?p.getStringList(_key)];
    p.setStringList(_key, kept.take(_keep).toList());
  }

  static String _current() {
    final when = DateTime.now();
    final b = StringBuffer(
      'Launch ${when.year}-${_two(when.month)}-${_two(when.day)} ${_two(when.hour)}:${_two(when.minute)}\n',
    );
    if (beforeMain case final ms?) b.writeln('  (+$ms ms before the app\'s code: Android, engine, plugins)');
    var last = 0;
    for (final (label, ms) in _marks) {
      b.writeln('${_ms(ms).padLeft(7)}  (+${ms - last} ms)  $label');
      last = ms;
    }
    return b.toString();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _ms(int ms) => '${(ms / 1000).toStringAsFixed(2)} s';

  /// The last finished launch in one line: "1.10 s to the camera (3D 0.89,
  /// camera 0.62; 98 ms before the app's code)"; null before one is saved.
  static String? lastSummary() {
    final last = prefs?.getStringList(_key)?.firstOrNull;
    if (last == null) return null;
    String? at(String label) {
      for (final line in last.split('\n')) {
        if (line.trimRight().endsWith(label)) return line.trim().split(' ').first;
      }
      return null;
    }

    final before = RegExp(r'\+(\d+) ms before').firstMatch(last)?.group(1);
    final total = at('curtain lifts') ?? at('curtain lifts (gave up waiting)');
    return '${total ?? '?'} s to the camera (3D ${at('3D camera in') ?? '?'}, camera ${at('camera open') ?? '?'}'
        '${before == null ? '' : '; $before ms before the app\'s code'})';
  }

  /// This launch (so far) and the ones before it, newest first.
  static String report() {
    final saved = prefs?.getStringList(_key) ?? const <String>[];
    final now = _done ? <String>[] : ['${_current()}(still launching)\n'];
    final all = [...now, ...saved];
    if (all.isEmpty) return 'No launches timed yet.';
    return 'Times from the start of the app\'s code; on Android the time before it is on the first line.\n\n'
        '${all.join('\n')}';
  }
}
