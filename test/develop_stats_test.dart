import 'package:darkroom/core/diagnostics/develop_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DevelopSample shot({required int workS, required int readyS, required int doneS}) {
    final t0 = DateTime(2026, 10, 26, 12);
    return DevelopSample(
      capturedAt: t0,
      readyAt: t0.add(Duration(seconds: readyS)),
      started: t0.add(Duration(seconds: doneS - workS)),
      finished: t0.add(Duration(seconds: doneS)),
      queued: 2,
    );
  }

  test('counts on-time and late shots, averages, and survives JSON', () {
    final t = DevelopTally()
      ..add(shot(workS: 10, readyS: 40, doneS: 20))
      ..add(shot(workS: 30, readyS: 40, doneS: 70))
      ..add(shot(workS: 20, readyS: 300, doneS: 60));
    expect(t.shots, 3);
    expect(t.late, 1);
    expect(t.lateMs, 30000);
    expect(t.workMs, 60000);
    expect(t.lateShare, closeTo(1 / 3, 1e-9));
    final back = DevelopTally.fromJson(t.toJson());
    expect(back.late, 1);
    expect(back.totalMs, t.totalMs);
    expect(back.maxQueue, 2);
  });

  test('a second of grace is not late', () {
    expect(shot(workS: 5, readyS: 40, doneS: 41).late, isFalse);
    expect(shot(workS: 5, readyS: 40, doneS: 42).late, isTrue);
  });
}
