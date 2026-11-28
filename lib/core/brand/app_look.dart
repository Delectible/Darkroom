import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The app icons people can pick (the welcome tour's "Want a different
/// look?", then Darkroom 98 > User Profile).
enum AppLook {
  /// The original: the rabbit with X'd-out eyes.
  classic('Original', 'The rabbit, as it came'),

  /// The rabbit with no face.
  eyeless('Rabbit', 'The rabbit, no face'),

  /// A plain instant camera.
  instant('Instant', 'A plain instant camera'),

  /// A lens, head-on.
  lens('Lens', 'A plain camera lens');

  const AppLook(this.title, this.blurb);

  final String title, blurb;

  /// The picture of this icon shown in the picker. The original's shows
  /// its X'd-out eyes only to someone still using it (Look.eyes): anyone
  /// who left it sees the faceless rabbit in its place.
  String get preview =>
      'assets/artwork/looks/${this == AppLook.classic && !Look.eyes ? AppLook.eyeless.name : name}.png';

  /// What changes beyond the icon, in a line, for the pickers.
  static String get note {
    final where = defaultTargetPlatform == TargetPlatform.iOS
        ? 'Your iPhone shows a short note when the icon changes.'
        : 'The home screen icon changes once you leave the app. Some phones take it off the home '
              'screen: add it back from the app list.';
    return 'Any icon but the original also takes the eyes off the rabbit everywhere in the app. $where';
  }
}

/// The icon picked, and what it means everywhere else.
///
/// Promise: once someone picks anything but [AppLook.classic], they never
/// see the original rabbit (X'd-out eyes) again: not the home-screen icon,
/// not the launch screens, not the notification icon, not a single rabbit
/// in the app. The rabbit stays (it's the app's motif) but with no face.
/// So every rabbit in the app asks [eyes] (test/app_look_test.dart checks
/// none skips it), and the pick outlives updates and, where the phone
/// allows, a reinstall: it's kept natively (Android: a backed-up
/// preferences file, Looks.kt; iPhone: the keychain, AppDelegate.swift),
/// with a copy in the app's files for the background isolate and in case
/// the native side can't be reached.
abstract final class Look {
  static const _channel = MethodChannel('darkroom/look');

  /// The current pick. Rabbits listen to it, so a change shows at once.
  static final notifier = ValueNotifier<AppLook>(AppLook.classic);

  static AppLook get current => notifier.value;

  /// Whether rabbits may have their X'd-out eyes: only with the original.
  static bool get eyes => notifier.value == AppLook.classic;

  /// The welcome tour's (and the dialogs') rabbit picture.
  static String get rabbitAsset =>
      eyes ? 'assets/artwork/rabbit_mark.png' : 'assets/artwork/rabbit_mark_eyeless.png';

  /// Stock artwork whose rendered logo shows the rabbit's eyes has a copy
  /// with them painted out (tool/icon/eyeless_artwork.py).
  static const eyelessArtwork = {
    'cinestill800t',
    'dslr08',
    'ektar100',
    'gold200',
    'hp5plus400',
    'polaroid600',
    'portra400',
    'super8',
    'superia400',
    'velvia50',
    'webcam05',
  };

  /// [path] (an assets/artwork picture), or its eyeless copy when the
  /// rabbit may not have eyes.
  static String artwork(String path) {
    if (eyes) return path;
    const dir = 'assets/artwork/';
    if (!path.startsWith(dir) || !path.endsWith('.webp')) return path;
    final name = path.substring(dir.length, path.length - 5);
    return eyelessArtwork.contains(name) ? '${dir}eyeless/$name.webp' : path;
  }

  /// Android's notification icon (res/drawable-*/ic_stat_*).
  static String get notificationIcon => switch (notifier.value) {
    AppLook.classic => '@drawable/ic_stat_darkroom',
    AppLook.eyeless => '@drawable/ic_stat_eyeless',
    AppLook.instant => '@drawable/ic_stat_instant',
    AppLook.lens => '@drawable/ic_stat_lens',
  };

  static File? _copy;

  static AppLook? _parse(String? s) {
    for (final l in AppLook.values) {
      if (l.name == s) return l;
    }
    return null;
  }

  /// Reads the pick before the first frame (so no rabbit is ever drawn with
  /// the wrong face). The native store wins; the copy in [supportDir]
  /// stands in if that can't be reached. Anything not the original found
  /// in either is kept: a pick is never lost to a hiccup.
  static Future<void> load(Directory supportDir) async {
    final copy = _copy = File('${supportDir.path}/app_look');
    AppLook? local;
    try {
      if (copy.existsSync()) local = _parse(copy.readAsStringSync().trim());
    } catch (_) {}
    AppLook? native;
    try {
      native = _parse(await _channel.invokeMethod<String>('get').timeout(const Duration(milliseconds: 800)));
    } catch (_) {}
    var look = native ?? local ?? AppLook.classic;
    // Never back to the original by accident: only a pick does that.
    if (look == AppLook.classic && local != null && local != AppLook.classic) look = local;
    notifier.value = look;
    if (native != look) unawaited(_saveNative(look));
    if (local != look) _saveCopy(look);
  }

  /// For the background isolate (no native channel there): the copy alone.
  static void loadCopy(Directory supportDir) {
    try {
      final copy = File('${supportDir.path}/app_look');
      if (copy.existsSync()) notifier.value = _parse(copy.readAsStringSync().trim()) ?? AppLook.classic;
    } catch (_) {}
  }

  /// Puts the saved pick on the home screen too, if it isn't (iPhone: after
  /// a reinstall brought the pick back from the keychain). Android does
  /// this itself (Looks.kt).
  static Future<void> ensureIcon() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<bool>('ensure');
    } catch (_) {}
  }

  /// Picks [look]: rabbits change at once; the home-screen icon on iPhone
  /// straight away (with iOS's own note), on Android once the app is out
  /// of sight.
  static Future<bool> choose(AppLook look) async {
    notifier.value = look;
    _saveCopy(look);
    return _saveNative(look);
  }

  static Future<bool> _saveNative(AppLook look) async {
    try {
      return await _channel.invokeMethod<bool>('set', look.name) ?? false;
    } catch (_) {
      return false;
    }
  }

  static void _saveCopy(AppLook look) {
    try {
      _copy?.writeAsStringSync(look.name, flush: true);
    } catch (_) {}
  }

  @visibleForTesting
  static void reset([AppLook look = AppLook.classic]) {
    notifier.value = look;
    _copy = null;
  }
}
