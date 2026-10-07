import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Crash reports kept on the phone (nothing is sent anywhere): uncaught
/// Dart / Flutter errors as they happen, plus, on Android 11+, the crashes
/// and freezes Android itself recorded for the app (native crashes and
/// "app not responding" included), picked up on the next launch. Shown in
/// the Win98 explorer under Help > Crash Reports, with a Copy button.
class CrashLog {
  CrashLog._();

  static const _channel = MethodChannel('darkroom/crash');
  static const _keep = 20;
  static File? _file;

  /// Starts catching errors. Call once, early in main().
  static Future<void> install(Directory dir) async {
    _file = File('${dir.path}/crash_reports.json');
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      _add('Flutter error', details.exceptionAsString(), details.stack);
      previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      _add('Uncaught error', '$error', stack);
      return false; // still let it be reported as usual
    };
    if (Platform.isAndroid) await _collectSystemExits();
  }

  static List<CrashReport> get reports {
    final f = _file;
    if (f == null || !f.existsSync()) return const [];
    try {
      final list = jsonDecode(f.readAsStringSync()) as List<dynamic>;
      return [for (final m in list) CrashReport.fromJson(m as Map<String, dynamic>)];
    } catch (_) {
      return const [];
    }
  }

  static void clear() {
    final f = _file;
    if (f != null && f.existsSync()) f.deleteSync();
  }

  static void _add(String kind, String message, StackTrace? stack, {DateTime? at, String? key}) {
    final f = _file;
    if (f == null) return;
    try {
      final all = reports;
      if (key != null && all.any((r) => r.key == key)) return; // seen it already
      final r = CrashReport(
        at: at ?? DateTime.now(),
        kind: kind,
        message: message,
        stack: stack?.toString() ?? '',
        key: key,
      );
      final kept = [r, ...all].take(_keep).map((r) => r.toJson()).toList();
      f.writeAsStringSync(jsonEncode(kept));
    } catch (_) {
      // A broken crash log must never crash the app.
    }
  }

  /// Android's ApplicationExitInfo: what killed the app last time(s).
  static Future<void> _collectSystemExits() async {
    try {
      final exits = await _channel.invokeListMethod<Map<dynamic, dynamic>>('exits') ?? const [];
      for (final e in exits.reversed) {
        _add(
          '${e['reason']}',
          '${e['description'] ?? ''}',
          null,
          at: DateTime.fromMillisecondsSinceEpoch((e['time'] as num).toInt()),
          key: 'exit:${e['time']}:${e['pid']}',
        );
        final trace = e['trace'];
        if (trace is String && trace.isNotEmpty) {
          // Fold the trace into the report just added.
          final all = reports;
          if (all.isNotEmpty && all.first.key == 'exit:${e['time']}:${e['pid']}' && all.first.stack.isEmpty) {
            final kept = [all.first.copyWithStack(trace), ...all.skip(1)].map((r) => r.toJson()).toList();
            _file!.writeAsStringSync(jsonEncode(kept));
          }
        }
      }
    } catch (_) {}
  }
}

@immutable
class CrashReport {
  const CrashReport({
    required this.at,
    required this.kind,
    required this.message,
    required this.stack,
    this.key,
  });

  factory CrashReport.fromJson(Map<String, dynamic> j) => CrashReport(
    at: DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
    kind: j['kind'] as String,
    message: j['message'] as String,
    stack: j['stack'] as String? ?? '',
    key: j['key'] as String?,
  );

  final DateTime at;
  final String kind;
  final String message;
  final String stack;
  final String? key;

  CrashReport copyWithStack(String s) =>
      CrashReport(at: at, kind: kind, message: message, stack: s, key: key);

  Map<String, dynamic> toJson() => {
    'at': at.millisecondsSinceEpoch,
    'kind': kind,
    'message': message,
    'stack': stack,
    if (key != null) 'key': key,
  };

  /// Plain text for pasting into a message.
  String get text {
    final s = stack.length > 6000 ? '${stack.substring(0, 6000)}\n...' : stack;
    return '$kind  ${at.toIso8601String()}\n$message${s.isEmpty ? '' : '\n$s'}';
  }
}
