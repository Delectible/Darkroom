import 'package:shared_preferences/shared_preferences.dart';

/// How long each step of a launch took, from the start of Dart's main
/// (Win98 Help > Debug > Launch Timing). The engine's own start, before
/// main, isn't in it. The last few launches are kept in prefs.
class LaunchTimer {
  LaunchTimer._();

  static final Stopwatch _clock = Stopwatch();
  static final List<(String, int)> _marks = [];
  static bool _done = false;

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
    var last = 0;
    for (final (label, ms) in _marks) {
      b.writeln('${_ms(ms).padLeft(7)}  (+${ms - last} ms)  $label');
      last = ms;
    }
    return b.toString();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _ms(int ms) => '${(ms / 1000).toStringAsFixed(2)} s';

  /// This launch (so far) and the ones before it, newest first.
  static String report() {
    final saved = prefs?.getStringList(_key) ?? const <String>[];
    final now = _done ? <String>[] : ['${_current()}(still launching)\n'];
    final all = [...now, ...saved];
    if (all.isEmpty) return 'No launches timed yet.';
    return 'Times from the start of the app\'s code (the phone\'s own start-up before it isn\'t counted).\n\n'
        '${all.join('\n')}';
  }
}
