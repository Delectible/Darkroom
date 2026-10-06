import 'dart:math' as math;
import 'dart:typed_data';

/// A 5x7 dot-matrix font, the kind burned in by date-back film cameras,
/// 2000s digicams and camcorder OSDs. Pure Dart so the same glyphs are drawn
/// by the live preview overlay, the still renderer (in an isolate) and the
/// video OSD frame generator.
class PixelFont {
  const PixelFont._();

  static const int glyphWidth = 5;
  static const int glyphHeight = 7;
  static const int advance = 6; // 1 column spacing

  static const Map<String, List<String>> _glyphs = {
    '0': ['.###.', '#...#', '#..##', '#.#.#', '##..#', '#...#', '.###.'],
    '1': ['..#..', '.##..', '..#..', '..#..', '..#..', '..#..', '.###.'],
    '2': ['.###.', '#...#', '....#', '...#.', '..#..', '.#...', '#####'],
    '3': ['#####', '...#.', '..#..', '...#.', '....#', '#...#', '.###.'],
    '4': ['...#.', '..##.', '.#.#.', '#..#.', '#####', '...#.', '...#.'],
    '5': ['#####', '#....', '####.', '....#', '....#', '#...#', '.###.'],
    '6': ['..##.', '.#...', '#....', '####.', '#...#', '#...#', '.###.'],
    '7': ['#####', '....#', '...#.', '..#..', '.#...', '.#...', '.#...'],
    '8': ['.###.', '#...#', '#...#', '.###.', '#...#', '#...#', '.###.'],
    '9': ['.###.', '#...#', '#...#', '.####', '....#', '...#.', '.##..'],
    'A': ['.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
    'B': ['####.', '#...#', '#...#', '####.', '#...#', '#...#', '####.'],
    'C': ['.###.', '#...#', '#....', '#....', '#....', '#...#', '.###.'],
    'D': ['###..', '#..#.', '#...#', '#...#', '#...#', '#..#.', '###..'],
    'E': ['#####', '#....', '#....', '####.', '#....', '#....', '#####'],
    'F': ['#####', '#....', '#....', '####.', '#....', '#....', '#....'],
    'G': ['.###.', '#...#', '#....', '#.###', '#...#', '#...#', '.####'],
    'H': ['#...#', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
    'I': ['.###.', '..#..', '..#..', '..#..', '..#..', '..#..', '.###.'],
    'J': ['..###', '...#.', '...#.', '...#.', '...#.', '#..#.', '.##..'],
    'K': ['#...#', '#..#.', '#.#..', '##...', '#.#..', '#..#.', '#...#'],
    'L': ['#....', '#....', '#....', '#....', '#....', '#....', '#####'],
    'M': ['#...#', '##.##', '#.#.#', '#.#.#', '#...#', '#...#', '#...#'],
    'N': ['#...#', '#...#', '##..#', '#.#.#', '#..##', '#...#', '#...#'],
    'O': ['.###.', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
    'P': ['####.', '#...#', '#...#', '####.', '#....', '#....', '#....'],
    'Q': ['.###.', '#...#', '#...#', '#...#', '#.#.#', '#..#.', '.##.#'],
    'R': ['####.', '#...#', '#...#', '####.', '#.#..', '#..#.', '#...#'],
    'S': ['.####', '#....', '#....', '.###.', '....#', '....#', '####.'],
    'T': ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '..#..'],
    'U': ['#...#', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
    'V': ['#...#', '#...#', '#...#', '#...#', '#...#', '.#.#.', '..#..'],
    'W': ['#...#', '#...#', '#...#', '#.#.#', '#.#.#', '#.#.#', '.#.#.'],
    'X': ['#...#', '#...#', '.#.#.', '..#..', '.#.#.', '#...#', '#...#'],
    'Y': ['#...#', '#...#', '.#.#.', '..#..', '..#..', '..#..', '..#..'],
    'Z': ['#####', '....#', '...#.', '..#..', '.#...', '#....', '#####'],
    ':': ['.....', '..#..', '..#..', '.....', '..#..', '..#..', '.....'],
    '.': ['.....', '.....', '.....', '.....', '.....', '.##..', '.##..'],
    "'": ['..#..', '..#..', '.#...', '.....', '.....', '.....', '.....'],
    '/': ['.....', '....#', '...#.', '..#..', '.#...', '#....', '.....'],
    '-': ['.....', '.....', '.....', '#####', '.....', '.....', '.....'],
    '>': ['#....', '##...', '###..', '####.', '###..', '##...', '#....'],
    '*': ['.....', '.###.', '#####', '#####', '#####', '.###.', '.....'],
    ' ': ['.....', '.....', '.....', '.....', '.....', '.....', '.....'],
  };

  static final Map<String, List<int>> _bits = {
    for (final e in _glyphs.entries)
      e.key: [
        for (final row in e.value) row.split('').fold<int>(0, (acc, ch) => (acc << 1) | (ch == '#' ? 1 : 0)),
      ],
  };

  static List<int> glyph(String ch) => _bits[ch.toUpperCase()] ?? _bits[' ']!;

  static bool isSet(List<int> rows, int x, int y) => (rows[y] >> (glyphWidth - 1 - x)) & 1 == 1;

  /// Width in dots (without trailing spacing).
  static int measureDots(String text) => text.isEmpty ? 0 : text.length * advance - 1;

  /// Iterates every lit dot of [text] (in dot coordinates).
  static void forEachDot(String text, void Function(int x, int y) visit) {
    for (var i = 0; i < text.length; i++) {
      final rows = glyph(text[i]);
      for (var y = 0; y < glyphHeight; y++) {
        for (var x = 0; x < glyphWidth; x++) {
          if (isSet(rows, x, y)) visit(i * advance + x, y);
        }
      }
    }
  }

  /// Draws [text] into an interleaved 8-bit RGB(A) buffer.
  ///
  /// [dot] is the size of one font dot in pixels. [glow] adds a soft halo
  /// (LED date imprint); [shadow] draws a hard drop shadow (VHS OSD).
  static void drawToBuffer(
    Uint8List data, {
    required int width,
    required int height,
    required int channels,
    required String text,
    required int left,
    required int top,
    required int dot,
    required List<int> rgb,
    List<int>? shadow,
    List<int>? glow,
  }) {
    void blendBlock(int bx, int by, int size, List<int> c, double alpha) {
      final x0 = math.max(0, bx), y0 = math.max(0, by);
      final x1 = math.min(width, bx + size), y1 = math.min(height, by + size);
      for (var y = y0; y < y1; y++) {
        var i = (y * width + x0) * channels;
        for (var x = x0; x < x1; x++) {
          for (var k = 0; k < 3; k++) {
            data[i + k] = (data[i + k] + (c[k] - data[i + k]) * alpha).round().clamp(0, 255);
          }
          if (channels == 4) {
            data[i + 3] = math.max(data[i + 3], (alpha * 255).round());
          }
          i += channels;
        }
      }
    }

    if (glow != null) {
      final r = math.max(1, dot ~/ 2);
      forEachDot(text, (x, y) {
        blendBlock(left + x * dot - r, top + y * dot - r, dot + 2 * r, glow, 0.22);
      });
    }
    if (shadow != null) {
      final o = math.max(1, dot ~/ 2);
      forEachDot(text, (x, y) {
        blendBlock(left + x * dot + o, top + y * dot + o, dot, shadow, 1.0);
      });
    }
    forEachDot(text, (x, y) {
      blendBlock(left + x * dot, top + y * dot, dot, rgb, 1.0);
    });
  }
}

/// Formats the burned-in timestamps for each digital camera style.
class TimestampFormat {
  const TimestampFormat._();

  static const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

  static String _pad2(int v) => v.toString().padLeft(2, '0');

  /// Orange LED date imprint: `'26 10 05`.
  static String ledDate(DateTime t) => "'${_pad2(t.year % 100)} ${_pad2(t.month)} ${_pad2(t.day)}";

  /// Flip-phone style: `2026/10/05 14:32`.
  static String phone(DateTime t) =>
      '${t.year}/${_pad2(t.month)}/${_pad2(t.day)} ${_pad2(t.hour)}:${_pad2(t.minute)}';

  /// Camcorder OSD, two lines: time on top, date below.
  static List<String> camcorder(DateTime t) {
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    return [
      '$ampm ${h12.toString().padLeft(2)}:${_pad2(t.minute)}:${_pad2(t.second)}',
      '${_months[t.month - 1]} ${_pad2(t.day)} ${t.year}',
    ];
  }
}
