import 'dart:async';
import 'dart:io';

/// A short log of camera session events (lifecycle, open, close, errors,
/// whether the viewfinder is getting frames), shown in Windows 98 under
/// Debug > Camera Log so a flaky camera can be diagnosed from a copy of it.
/// Newest last, capped at [_max]. Kept in a file, so a freeze that needed
/// the app killed is still there on the next launch.
class CameraLog {
  CameraLog._();

  static const _max = 150;
  static final List<String> _lines = [];
  static File? _file;
  static Timer? _save;

  static List<String> get lines => List.unmodifiable(_lines);

  /// For the copy: which system it ran on.
  static String get device => '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';

  /// Where it's kept; last run's lines come back first.
  static void init(Directory dir) {
    final f = File('${dir.path}/camera_log.txt');
    _file = f;
    try {
      if (f.existsSync()) {
        final old = f.readAsLinesSync().where((l) => l.isNotEmpty).toList();
        final now = List.of(_lines);
        _lines
          ..clear()
          ..addAll(old)
          ..add('---------- launch ${_date(DateTime.now())}')
          ..addAll(now);
        _trim();
      }
    } catch (_) {
      // (unreadable: start afresh)
    }
  }

  static void add(String event) {
    final t = DateTime.now();
    _lines.add('${_time(t)}  $event');
    _trim();
    // Leaving the app may be the last chance: kept at once then.
    if (event.startsWith('app ') && event != 'app resumed' && event != 'app inactive') {
      flush();
    } else {
      _save ??= Timer(const Duration(seconds: 1), flush);
    }
  }

  static void flush() {
    _save?.cancel();
    _save = null;
    final f = _file;
    if (f == null) return;
    try {
      f.writeAsStringSync('${_lines.join('\n')}\n');
    } catch (_) {}
  }

  static void clear() {
    _lines.clear();
    flush();
  }

  static void _trim() {
    if (_lines.length > _max) _lines.removeRange(0, _lines.length - _max);
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String _time(DateTime t) =>
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}.${_two(t.millisecond ~/ 10)}';
  static String _date(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)} ${_time(t)}';
}
