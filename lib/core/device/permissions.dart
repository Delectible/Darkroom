import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';

import '../providers.dart';

/// The permissions the camera needs (notifications are optional, so not
/// here). Camera: nothing works without it. Microphone: videos are silent.
/// Photos: Save / Transfer can't reach the phone's photos.
enum Perm { camera, microphone, photos }

/// Camera / microphone through channel `darkroom/permissions` (MainActivity,
/// AppDelegate); photos through the gallery plugin.
class Permissions {
  Permissions._();

  static const _channel = MethodChannel('darkroom/permissions');

  static Future<bool> granted(Perm p) async {
    try {
      if (p == Perm.photos) return await Gal.hasAccess(toAlbum: true);
      return await _channel.invokeMethod<bool>('granted', {'kind': p.name}) ?? true;
    } catch (_) {
      return true; // can't tell (no channel): don't nag
    }
  }

  /// Asks for [p] (only while the phone still shows its prompt).
  static Future<bool> request(Perm p) async {
    try {
      if (p == Perm.photos) return await Gal.requestAccess(toAlbum: true);
      return await _channel.invokeMethod<bool>('request', {'kind': p.name}) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// The app's own page in the phone's settings.
  static Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<bool>('openSettings');
    } catch (_) {}
  }

  /// Asks for [p]; once the phone won't ask any more, opens the app's page
  /// in Settings instead (no digging). True when it's granted now.
  static Future<bool> fix(Perm p) async {
    if (await request(p)) return true;
    await openSettings();
    return false;
  }
}

/// The permissions still missing, rechecked whenever the app comes back to
/// the front (e.g. from Settings).
class MissingPermissionsNotifier extends Notifier<Set<Perm>> {
  @override
  Set<Perm> build() {
    ref.listen<AppLifecycleState>(appLifecycleProvider, (_, next) {
      if (next == AppLifecycleState.resumed) unawaited(refresh());
    });
    Future.microtask(refresh);
    return const {};
  }

  Future<void> refresh() async {
    final missing = <Perm>{
      for (final p in Perm.values)
        if (!await Permissions.granted(p)) p,
    };
    if (ref.mounted) state = missing;
  }

  /// Fixes [p] (asks, or opens Settings) and rechecks.
  Future<bool> fix(Perm p) async {
    final ok = await Permissions.fix(p);
    await refresh();
    return ok;
  }
}

final missingPermissionsProvider = NotifierProvider<MissingPermissionsNotifier, Set<Perm>>(
  MissingPermissionsNotifier.new,
);
