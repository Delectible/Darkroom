/// A short in-memory log of camera session events (lifecycle, open, close,
/// errors), shown in Windows 98 under Help > Camera Log so a flaky camera
/// can be diagnosed from a screenshot. Newest last, capped at [_max].
class CameraLog {
  CameraLog._();

  static const _max = 60;
  static final List<String> _lines = [];

  static List<String> get lines => List.unmodifiable(_lines);

  static void add(String event) {
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final ms = (t.millisecond ~/ 10).toString().padLeft(2, '0');
    _lines.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)}.$ms  $event');
    if (_lines.length > _max) _lines.removeAt(0);
  }
}
