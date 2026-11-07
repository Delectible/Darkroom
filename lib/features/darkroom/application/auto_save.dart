import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/media_repository.dart';
import '../../../core/providers.dart';
import '../../settings/application/settings_controllers.dart';
import '../../viewer/presentation/media_actions.dart';

/// Settings > save to the phone's gallery automatically: each film print
/// once it has developed, each digital photo once it's ready (it moves to
/// C:, as saving it from the explorer does). Only what finished after the
/// setting went on; while the app is open (what finished meanwhile is
/// caught up on the next look).
final autoSaveProvider = Provider<void>((ref) {
  final busy = <String>{};

  Future<void> run() async {
    final since = ref.read(globalSettingsProvider).autoSaveSince;
    if (since == null) return;
    if (ref.read(appLifecycleProvider) != AppLifecycleState.resumed) return;
    final now = DateTime.now();
    final film = ref.read(filmItemsProvider).value ?? const <MediaItem>[];
    final sd = ref.read(sdCardItemsProvider).value ?? const <MediaItem>[];
    final jobs = <(MediaRepository, MediaItem, String, bool)>[
      for (final m in film)
        if (m.isDevelopedAt(now) && !m.isSaved && m.readyAt.isAfter(since))
          (ref.read(filmRepositoryProvider), m, filmAlbum, false),
      for (final m in sd)
        if (m.isReady && m.onSdCard && !m.isSaved && m.capturedAt.isAfter(since))
          (ref.read(sdCardRepositoryProvider), m, digitalAlbum, true),
    ];
    for (final (repo, m, album, toC) in jobs) {
      if (!busy.add(m.id)) continue;
      try {
        await keepMedia(repo, m, album: album, moveToC: toC);
      } catch (_) {
        // (left for the next look)
      } finally {
        busy.remove(m.id);
      }
    }
  }

  void kick() => unawaited(run());
  ref.listen(filmItemsProvider, (_, _) => kick());
  ref.listen(sdCardItemsProvider, (_, _) => kick());
  ref.listen(appLifecycleProvider, (_, s) {
    if (s == AppLifecycleState.resumed) kick();
  });
  // (a film print can be due before its row changes: look now and then)
  final timer = Timer.periodic(const Duration(seconds: 20), (_) => kick());
  ref.onDispose(timer.cancel);
});
