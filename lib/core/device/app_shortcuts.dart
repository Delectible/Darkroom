import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quick_actions/quick_actions.dart';

import '../../features/camera/application/camera_ui_state.dart' show selectedCameraProvider;
import '../../features/cameras/domain/camera_catalog.dart';
import '../../features/cameras/domain/camera_spec.dart';
import '../providers.dart' show pendingRouteProvider;

/// Long-press shortcuts on the app icon: Corkboard, Darkroom 98, and the
/// last film and digital camera used (named after them, kept up to date).
/// A tap becomes a [pendingRouteProvider] route the camera screen follows.
abstract final class AppShortcuts {
  static const corkboard = 'corkboard';
  static const explorer = 'explorer';
  static const film = 'film';
  static const digital = 'digital';

  static void start(ProviderContainer container) {
    if (kIsWeb ||
        !(defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      return;
    }
    const actions = QuickActions();
    try {
      unawaited(actions.initialize((type) => container.read(pendingRouteProvider.notifier).request(type)));
    } catch (e) {
      debugPrint('Shortcuts unavailable: $e');
      return;
    }
    void publish(Map<AppMode, String> cams) {
      String name(AppMode m) => CameraCatalog.byId(cams[m]!).name;
      unawaited(
        actions
            .setShortcutItems([
              const ShortcutItem(type: corkboard, localizedTitle: 'Corkboard'),
              const ShortcutItem(type: explorer, localizedTitle: 'Darkroom 98'),
              ShortcutItem(type: film, localizedTitle: name(AppMode.film)),
              ShortcutItem(type: digital, localizedTitle: name(AppMode.digital)),
            ])
            .catchError((Object e) => debugPrint('Shortcuts unavailable: $e')),
      );
    }

    publish(container.read(selectedCameraProvider));
    container.listen(selectedCameraProvider, (_, next) => publish(next));
  }
}
