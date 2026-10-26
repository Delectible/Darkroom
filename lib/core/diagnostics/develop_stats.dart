import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One film shot that came out of the darkroom queue.
class DevelopSample {
  const DevelopSample({
    required this.capturedAt,
    required this.readyAt,
    required this.started,
    required this.finished,
    required this.queued,
  });

  final DateTime capturedAt;

  /// When the darkroom timer said it would be ready (the cutoff).
  final DateTime readyAt;

  /// When this phone started and finished processing it.
  final DateTime started, finished;

  /// Shots still waiting when it finished.
  final int queued;

  /// Finished after its timer ran out (a second's grace).
  bool get late => finished.isAfter(readyAt.add(const Duration(seconds: 1)));
}

/// Running totals for a stretch of development.
class DevelopTally {
  DevelopTally({
    this.shots = 0,
    this.late = 0,
    this.workMs = 0,
    this.totalMs = 0,
    this.lateMs = 0,
    this.maxQueue = 0,
    DateTime? since,
  }) : since = since ?? DateTime.now();

  factory DevelopTally.fromJson(Map<String, Object?> j) => DevelopTally(
    shots: (j['n'] as num?)?.toInt() ?? 0,
    late: (j['late'] as num?)?.toInt() ?? 0,
    workMs: (j['work'] as num?)?.toInt() ?? 0,
    totalMs: (j['total'] as num?)?.toInt() ?? 0,
    lateMs: (j['lateMs'] as num?)?.toInt() ?? 0,
    maxQueue: (j['maxQ'] as num?)?.toInt() ?? 0,
    since: DateTime.fromMillisecondsSinceEpoch((j['since'] as num?)?.toInt() ?? 0),
  );

  int shots, late, workMs, totalMs, lateMs, maxQueue;
  final DateTime since;

  Map<String, Object?> toJson() => {
    'n': shots,
    'late': late,
    'work': workMs,
    'total': totalMs,
    'lateMs': lateMs,
    'maxQ': maxQueue,
    'since': since.millisecondsSinceEpoch,
  };

  void add(DevelopSample s) {
    shots++;
    workMs += s.finished.difference(s.started).inMilliseconds;
    totalMs += s.finished.difference(s.capturedAt).inMilliseconds;
    if (s.late) {
      late++;
      lateMs += s.finished.difference(s.readyAt).inMilliseconds;
    }
    if (s.queued > maxQueue) maxQueue = s.queued;
  }

  double get lateShare => shots == 0 ? 0 : late / shots;
}

/// Watches the darkroom queue: how long film shots take on this phone and
/// how many miss their timer. Kept in prefs: all time, plus a stretch the
/// Debug window can reset. Shots resumed after the app was killed don't
/// count (they waited on the app, not the phone).
class DevelopStats {
  DevelopStats(this._prefs);

  final SharedPreferencesWithCache _prefs;

  static const key = 'stats.develop';

  /// Share of late prints that earns the "your phone is the bottleneck"
  /// note, once there are [minShots] to go on.
  static const warnShare = 0.2;
  static const minShots = 10;

  DevelopTally get allTime => _read('all');
  DevelopTally get recent => _read('recent');
  bool get told => _json['told'] == true;

  Map<String, Object?> get _json {
    final raw = _prefs.getString(key);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map).cast<String, Object?>();
    } on FormatException {
      return {};
    }
  }

  DevelopTally _read(String k) {
    final j = _json[k];
    return j is Map ? DevelopTally.fromJson(j.cast<String, Object?>()) : DevelopTally();
  }

  Future<void> _write(Map<String, Object?> j) => _prefs.setString(key, jsonEncode(j));

  Future<void> add(DevelopSample s) {
    final j = _json;
    final all = allTime..add(s);
    final recent = this.recent..add(s);
    return _write({...j, 'all': all.toJson(), 'recent': recent.toJson()});
  }

  Future<void> clearRecent() => _write({..._json, 'recent': DevelopTally().toJson()});

  /// True once, when this phone keeps missing the timers.
  bool get shouldWarn {
    if (told) return false;
    final a = allTime;
    return a.shots >= minShots && a.lateShare > warnShare;
  }

  Future<void> markTold() => _write({..._json, 'told': true});
}
