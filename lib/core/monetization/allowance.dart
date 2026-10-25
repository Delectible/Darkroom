import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/camera/application/camera_ui_state.dart' show PrefKeys;
import '../../features/cameras/domain/camera_spec.dart';
import 'pro.dart';

/// Why the shutter won't fire on the free version.
enum Blocked {
  /// Today's roll is finished.
  outOfFilm,

  /// Another stock's roll is loaded and not finished yet.
  otherRoll,

  /// The digital cameras' shared battery is flat for today.
  flatBattery,

  /// A Pro-only film or camera (CameraSpec.pro).
  proOnly,

  /// Today's roll is still in its box: the first shot loads it, so ask
  /// first (the stock can't change until it's finished).
  unloaded,

  /// A roll left unfinished yesterday is still in the camera and nobody has
  /// said yet whether to keep shooting it or rewind and swap.
  carriedOver,
}

/// The free version's daily allowance: one roll of film (any stock, fixed
/// once its first frame is shot) and one charge of a battery the digital
/// cameras share. Both come back every morning ([refillHour] local time).
/// A roll that isn't finished stays in the camera overnight ([carried]):
/// the first film shot asks to keep it or rewind and swap (the rest is
/// lost); finishing it brings today's fresh roll. Darkroom Pro ignores all
/// of it.
class Allowance {
  const Allowance({
    required this.day,
    this.stock,
    this.rollSize = 0,
    this.filmUsed = 0,
    this.batteryUsed = 0,
    this.carried = false,
    this.asked = false,
  });

  /// Local day of the last refill (see [dayOf]).
  final String day;

  /// The stock loaded today; null while today's roll is still in its box.
  final String? stock;

  /// Size of the loaded roll ([sizeOf] its stock).
  final int rollSize;

  /// Frames shot on today's roll (seconds of film for Super 8).
  final int filmUsed;

  /// Battery units used today: a photo is one, video [videoSecondsPerUnit]
  /// seconds a unit.
  final int batteryUsed;

  /// The loaded roll was left unfinished on an earlier day.
  final bool carried;

  /// Today's keep-or-swap question about a [carried] roll was answered.
  final bool asked;

  static const refillHour = 5;
  static const frames35 = 24;
  static const super8Seconds = 60;
  static const battery = 10;
  static const videoSecondsPerUnit = 3;

  /// The day a moment belongs to: a new one starts at [refillHour].
  static String dayOf(DateTime t) {
    final d = t.subtract(const Duration(hours: refillHour));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// A roll of [spec] on the free version: 24 frames of 35mm, the usual pack
  /// for instant, a one-minute cartridge for Super 8.
  static int sizeOf(CameraSpec spec) {
    if (spec.recordsVideo) return super8Seconds;
    if (spec.printStyle == PrintStyle.instant) return spec.roll.frames;
    return frames35;
  }

  /// Today's state at [now]: a new morning brings a full battery, and a
  /// fresh roll unless one is still unfinished in the camera.
  /// A clock set back to an earlier day changes nothing (no free refill).
  Allowance at(DateTime now) {
    if (dayOf(now).compareTo(day) <= 0) return this;
    if (stock != null && filmUsed < rollSize) {
      return Allowance(day: dayOf(now), stock: stock, rollSize: rollSize, filmUsed: filmUsed, carried: true);
    }
    return Allowance(day: dayOf(now));
  }

  /// What's left for [spec]: frames (seconds for Super 8) of film, or battery
  /// units for digital bodies.
  int left(CameraSpec spec) {
    if (spec.mode == AppMode.digital) return (battery - batteryUsed).clamp(0, battery);
    if (stock == null) return sizeOf(spec);
    if (stock != spec.id) return 0;
    return (rollSize - filmUsed).clamp(0, rollSize);
  }

  /// Null when [spec] may shoot.
  Blocked? check(CameraSpec spec) {
    if (spec.pro) return Blocked.proOnly;
    if (spec.mode == AppMode.digital) return left(spec) > 0 ? null : Blocked.flatBattery;
    if (carried && !asked) return Blocked.carriedOver;
    if (stock != null && filmUsed >= rollSize) return Blocked.outOfFilm;
    if (stock != null && stock != spec.id) return Blocked.otherRoll;
    if (stock == null) return Blocked.unloaded;
    return null;
  }

  /// Today's roll, loaded with [spec] (nothing shot yet).
  Allowance load(CameraSpec spec) => _load(spec);

  /// Keep shooting yesterday's roll.
  Allowance keep() => copy(asked: true);

  /// Rewind yesterday's roll (the rest is lost): today's fresh roll waits.
  Allowance rewind() => Allowance(day: day, batteryUsed: batteryUsed);

  /// After a still on [spec].
  Allowance usePhoto(CameraSpec spec) => spec.mode == AppMode.digital
      ? copy(batteryUsed: batteryUsed + 1)
      : _load(spec).copy(filmUsed: _load(spec).filmUsed + 1)._finishCarried();

  /// After a clip of [seconds] on [spec].
  Allowance useVideo(CameraSpec spec, int seconds) {
    if (spec.mode == AppMode.digital) {
      return copy(batteryUsed: batteryUsed + (seconds / videoSecondsPerUnit).ceil().clamp(1, battery));
    }
    final r = _load(spec);
    return r.copy(filmUsed: r.filmUsed + seconds.clamp(1, super8Seconds))._finishCarried();
  }

  /// A carried-over roll just finished: today's own roll is next.
  Allowance _finishCarried() => carried && filmUsed >= rollSize ? rewind() : this;

  /// Today's roll, loaded with [spec] if it's still in its box.
  Allowance _load(CameraSpec spec) => stock == spec.id
      ? this
      : Allowance(day: day, stock: spec.id, rollSize: sizeOf(spec), batteryUsed: batteryUsed);

  /// Longest clip [spec] may still record, in seconds.
  int videoSecondsLeft(CameraSpec spec) =>
      spec.mode == AppMode.digital ? left(spec) * videoSecondsPerUnit : left(spec);

  Allowance copy({int? filmUsed, int? batteryUsed, bool? asked}) => Allowance(
    day: day,
    stock: stock,
    rollSize: rollSize,
    filmUsed: filmUsed ?? this.filmUsed,
    batteryUsed: batteryUsed ?? this.batteryUsed,
    carried: carried,
    asked: asked ?? this.asked,
  );

  Map<String, Object?> toJson() => {
    'day': day,
    'stock': stock,
    'size': rollSize,
    'film': filmUsed,
    'battery': batteryUsed,
    'carried': carried,
    'asked': asked,
  };

  static Allowance fromJson(Map<String, Object?> j) => Allowance(
    day: j['day'] as String? ?? '',
    stock: j['stock'] as String?,
    rollSize: (j['size'] as num?)?.toInt() ?? 0,
    filmUsed: (j['film'] as num?)?.toInt() ?? 0,
    batteryUsed: (j['battery'] as num?)?.toInt() ?? 0,
    carried: j['carried'] == true,
    asked: j['asked'] == true,
  );
}

class AllowanceNotifier extends Notifier<Allowance> {
  /// The clock (tests move it).
  static DateTime Function() now = DateTime.now;

  @override
  Allowance build() {
    final raw = prefsOf(ref)?.getString(PrefKeys.allowance);
    Allowance a;
    try {
      a = raw == null
          ? Allowance(day: Allowance.dayOf(now()))
          : Allowance.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
    } catch (_) {
      a = Allowance(day: Allowance.dayOf(now()));
    }
    return a.at(now());
  }

  /// Today's allowance (a new morning refills it).
  Allowance get today {
    final t = state.at(now());
    if (!identical(t, state)) state = t;
    return t;
  }

  bool get _pro => ref.read(proProvider);

  /// Null when [spec] may shoot (always, on Pro).
  Blocked? check(CameraSpec spec) => _pro ? null : today.check(spec);

  /// Longest clip [spec] may record now; null = no limit.
  int? videoSecondsLeft(CameraSpec spec) => _pro ? null : today.videoSecondsLeft(spec);

  void usePhoto(CameraSpec spec) {
    if (!_pro) _save(today.usePhoto(spec));
  }

  void useVideo(CameraSpec spec, Duration length) {
    if (!_pro) _save(today.useVideo(spec, (length.inMilliseconds / 1000).ceil()));
  }

  /// Loads today's roll with [spec] (the user said yes).
  void load(CameraSpec spec) {
    if (!_pro) _save(today.load(spec));
  }

  /// Keep shooting yesterday's roll today.
  void keep() {
    if (!_pro) _save(today.keep());
  }

  /// Rewind yesterday's roll; today's fresh roll waits.
  void rewind() {
    if (!_pro) _save(today.rewind());
  }

  /// A fresh roll and a full battery now (Debug).
  void refill() => _save(Allowance(day: Allowance.dayOf(now())));

  void _save(Allowance a) {
    state = a;
    prefsOf(ref)?.setString(PrefKeys.allowance, jsonEncode(a.toJson()));
  }
}

final allowanceProvider = NotifierProvider<AllowanceNotifier, Allowance>(AllowanceNotifier.new);

/// The shutter was pressed with nothing left; the camera screen explains
/// (a counter, so the same reason twice still shows).
class LimitHitNotifier extends Notifier<(Blocked, int)?> {
  @override
  (Blocked, int)? build() => null;

  void hit(Blocked why) => state = (why, (state?.$2 ?? 0) + 1);
}

final limitHitProvider = NotifierProvider<LimitHitNotifier, (Blocked, int)?>(LimitHitNotifier.new);
