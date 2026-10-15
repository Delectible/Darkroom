import 'package:darkroom/core/monetization/allowance.dart';
import 'package:darkroom/features/cameras/domain/camera_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

/// The free version's daily film roll and digital battery.
void main() {
  final portra = CameraCatalog.byId('portra400');
  final ektar = CameraCatalog.byId('ektar100');
  final instant = CameraCatalog.byId('polaroid600');
  final super8 = CameraCatalog.byId('super8');
  final floppy = CameraCatalog.byId('floppy99');
  final camcorder = CameraCatalog.byId('camcorder90');
  final morning = DateTime(2026, 10, 15, 9);
  final fresh = Allowance(day: Allowance.dayOf(morning));

  test('a new day starts at 5am', () {
    expect(Allowance.dayOf(DateTime(2026, 10, 16, 4, 59)), Allowance.dayOf(morning));
    expect(Allowance.dayOf(DateTime(2026, 10, 16, 5)), isNot(Allowance.dayOf(morning)));
  });

  test('roll sizes: 24 frames of 35mm, the instant pack, a minute of Super 8', () {
    expect(Allowance.sizeOf(portra), 24);
    expect(Allowance.sizeOf(instant), instant.roll.frames);
    expect(Allowance.sizeOf(super8), 60);
  });

  test('one roll a day, fixed to its stock once the first frame is shot', () {
    var a = fresh;
    expect(a.check(ektar), isNull, reason: 'any stock until the roll is loaded');
    a = a.usePhoto(portra);
    expect(a.left(portra), 23);
    expect(a.check(ektar), Blocked.otherRoll);
    for (var i = 0; i < 23; i++) {
      a = a.usePhoto(portra);
    }
    expect(a.check(portra), Blocked.outOfFilm);
    expect(a.check(ektar), Blocked.outOfFilm, reason: 'one roll a day, whatever the stock');
    expect(a.at(DateTime(2026, 10, 16, 6)).check(ektar), isNull, reason: 'a fresh roll next morning');
  });

  test('Super 8 counts seconds of film', () {
    var a = fresh.useVideo(super8, 45);
    expect(a.videoSecondsLeft(super8), 15);
    a = a.useVideo(super8, 15);
    expect(a.check(super8), Blocked.outOfFilm);
  });

  test('digital cameras share one battery: 10 shots, 3 s of video a unit', () {
    var a = fresh;
    for (var i = 0; i < 9; i++) {
      a = a.usePhoto(floppy);
    }
    expect(a.left(camcorder), 1);
    expect(a.videoSecondsLeft(camcorder), 3);
    a = a.useVideo(camcorder, 2);
    expect(a.check(floppy), Blocked.flatBattery);
    expect(a.check(portra), isNull, reason: 'film is separate');
  });

  test('survives a round trip through prefs', () {
    final a = fresh.usePhoto(instant).usePhoto(floppy);
    final b = Allowance.fromJson(a.toJson());
    expect(b.stock, 'polaroid600');
    expect(b.left(instant), instant.roll.frames - 1);
    expect(b.left(floppy), Allowance.battery - 1);
  });
}
