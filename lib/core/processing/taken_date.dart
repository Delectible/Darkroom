import 'package:image/image.dart' as img;

/// When a shot was taken, written into the file the way a camera does, so
/// photo apps sort it by that (without it they fall back to the file's own
/// date, which the phone can refresh, floating old shots to the top).
abstract final class TakenDate {
  static String _two(int v) => v.toString().padLeft(2, '0');

  /// EXIF's "2026:10:30 14:05:09" (local time) and its UTC offset ("+10:00").
  static (String, String) exifOf(DateTime local) {
    final t = local.toLocal();
    final o = t.timeZoneOffset;
    final sign = o.isNegative ? '-' : '+';
    final m = o.inMinutes.abs();
    return (
      '${t.year}:${_two(t.month)}:${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}',
      '$sign${_two(m ~/ 60)}:${_two(m % 60)}',
    );
  }

  /// Stamps [exif] with the time taken.
  static void stamp(img.ExifData exif, DateTime taken) {
    final (at, offset) = exifOf(taken);
    exif.imageIfd['DateTime'] = at;
    exif.exifIfd['DateTimeOriginal'] = at;
    exif.exifIfd['DateTimeDigitized'] = at;
    exif.exifIfd['OffsetTimeOriginal'] = offset;
  }

  /// FFmpeg output options: the clip's creation time (UTC), which photo apps
  /// read as when it was filmed.
  static List<String> ffmpegArgs(DateTime taken) => [
    '-metadata',
    'creation_time=${taken.toUtc().toIso8601String()}',
  ];
}
