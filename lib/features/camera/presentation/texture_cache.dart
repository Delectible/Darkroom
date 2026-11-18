import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart' as fs;

import '../../../core/diagnostics/perf_recorder.dart';

/// The 3D cameras' textures as transcoded for this phone's GPU, kept between
/// launches: the first launch transcodes them (workers, ~1.5 s), every one
/// after reads them back and uploads them as they are (no workers, so no
/// garbage-collection pauses either). Keyed by the texture's own bytes, so
/// a new model or skin makes new entries; the oldest go past [_maxBytes].
class TextureCache {
  TextureCache._();

  static const _maxBytes = 260 * 1024 * 1024;
  static Directory? _dir;
  static int hits = 0, misses = 0;

  /// Where they're kept (main.dart, before the 3D loads).
  static void init(Directory support) {
    final dir = _dir = Directory('${support.path}/textures');
    try {
      dir.createSync(recursive: true);
    } catch (_) {
      _dir = null;
      return;
    }
    fs.darkroomCacheRead = _read;
    fs.darkroomCacheWrite = _write;
    unawaited(_prune());
  }

  static File _file(String key) => File('${_dir!.path}/$key.tex');

  static Future<Uint8List?> _read(String key) async {
    final f = _file(key);
    try {
      final bytes = await f.readAsBytes();
      hits++;
      // (kept fresh: the oldest go first)
      unawaited(f.setLastModified(DateTime.now()).catchError((_) {}));
      return bytes;
    } catch (_) {
      misses++;
      return null;
    }
  }

  // one write at a time, after the launch's own work
  static Future<void> _writing = Future<void>.value();

  static void _write(String key, Uint8List bytes) {
    _writing = _writing.then((_) async {
      final f = _file(key), tmp = File('${f.path}.tmp');
      try {
        await tmp.writeAsBytes(bytes, flush: true);
        await tmp.rename(f.path);
        PerfRecorder.event('3D lib: texture kept (${bytes.length ~/ 1024} KB)');
      } catch (_) {
        try {
          if (tmp.existsSync()) tmp.deleteSync();
        } catch (_) {}
      }
    });
  }

  static Future<void> _prune() async {
    try {
      final files = <File, FileStat>{};
      await for (final e in _dir!.list()) {
        if (e is File) files[e] = await e.stat();
      }
      var total = files.values.fold<int>(0, (a, s) => a + s.size);
      final oldest = files.keys.toList()..sort((a, b) => files[a]!.modified.compareTo(files[b]!.modified));
      for (final f in oldest) {
        if (total <= _maxBytes && !f.path.endsWith('.tmp')) break;
        total -= files[f]!.size;
        await f.delete();
      }
    } catch (_) {}
  }
}
