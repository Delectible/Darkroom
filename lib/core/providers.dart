import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/darkroom/application/darkroom_engine.dart';
import 'background/background_worker.dart';
import 'db/app_database.dart';
import 'db/media_repository.dart';
import 'notifications/notification_service.dart';
import 'paths/app_paths.dart';
import 'processing/capture_processor.dart';
import 'settings/settings_repository.dart';

// ---------------------------------------------------------------------------
// Infrastructure singletons. Created in main() (they need async init) and
// injected with ProviderScope overrides.
// ---------------------------------------------------------------------------

final appPathsProvider = Provider<AppPaths>((ref) => throw UnimplementedError('override in main'));
final appDatabaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('override in main'));
final sharedPrefsProvider = Provider<SharedPreferencesWithCache>(
  (ref) => throw UnimplementedError('override in main'),
);
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => throw UnimplementedError('override in main'),
);
final initialGlobalSettingsProvider = Provider<GlobalSettings>(
  (ref) => throw UnimplementedError('override in main'),
);
final initialCameraSettingsProvider = Provider<Map<String, CameraLocalSettings>>(
  (ref) => throw UnimplementedError('override in main'),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(appDatabaseProvider)),
);

final filmRepositoryProvider = Provider<MediaRepository>((ref) {
  final repo = MediaRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(appPathsProvider),
    table: AppDatabase.filmTable,
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final sdCardRepositoryProvider = Provider<MediaRepository>((ref) {
  final repo = MediaRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(appPathsProvider),
    table: AppDatabase.sdTable,
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final darkroomEngineProvider = Provider<DarkroomEngine>((ref) {
  return DarkroomEngine(
    film: ref.watch(filmRepositoryProvider),
    notifications: ref.watch(notificationServiceProvider),
    settings: ref.watch(settingsRepositoryProvider),
    scheduler: const WorkmanagerDevelopScheduler(),
  );
});

final captureProcessorProvider = Provider<CaptureProcessor>((ref) {
  final processor = CaptureProcessor(
    paths: ref.watch(appPathsProvider),
    db: ref.watch(appDatabaseProvider),
    film: ref.watch(filmRepositoryProvider),
    sdCard: ref.watch(sdCardRepositoryProvider),
    onFilmQueueChanged: () => ref.read(darkroomEngineProvider).reschedule(),
  );
  ref.onDispose(processor.pending.dispose);
  return processor;
});

// ---------------------------------------------------------------------------
// Live media lists
// ---------------------------------------------------------------------------

/// Emits the table now and after every change. Subscribes to the change feed
/// *before* the first query (no missed updates) and coalesces bursts so a
/// flurry of writes costs at most one extra query.
Stream<List<MediaItem>> _watch(MediaRepository repo) {
  late final StreamController<List<MediaItem>> out;
  StreamSubscription<void>? sub;
  var running = false, again = false;
  Future<void> refresh() async {
    if (running) {
      again = true;
      return;
    }
    running = true;
    try {
      do {
        again = false;
        final items = await repo.all();
        if (!out.isClosed) out.add(items);
      } while (again && !out.isClosed);
    } finally {
      running = false;
    }
  }

  out = StreamController<List<MediaItem>>(
    onListen: () {
      sub = repo.changes.listen((_) => unawaited(refresh()));
      unawaited(refresh());
    },
    onCancel: () async {
      await sub?.cancel();
      await out.close();
    },
  );
  return out.stream;
}

final filmItemsProvider = StreamProvider<List<MediaItem>>((ref) => _watch(ref.watch(filmRepositoryProvider)));

final sdCardItemsProvider = StreamProvider<List<MediaItem>>(
  (ref) => _watch(ref.watch(sdCardRepositoryProvider)),
);

/// 1 Hz clock for countdowns; only alive while a widget watches it.
final secondTickerProvider = StreamProvider.autoDispose<DateTime>((ref) {
  return Stream<DateTime>.periodic(const Duration(seconds: 1), (_) => DateTime.now());
});

// ---------------------------------------------------------------------------
// App lifecycle & routing hooks
// ---------------------------------------------------------------------------

class AppLifecycleNotifier extends Notifier<AppLifecycleState> {
  @override
  AppLifecycleState build() => WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;

  void set(AppLifecycleState s) {
    if (s != state) state = s;
  }
}

final appLifecycleProvider = NotifierProvider<AppLifecycleNotifier, AppLifecycleState>(
  AppLifecycleNotifier.new,
);

/// A route requested from outside the widget tree (notification tap).
class PendingRouteNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void request(String? route) => state = route;
  void consume() => state = null;
}

final pendingRouteProvider = NotifierProvider<PendingRouteNotifier, String?>(PendingRouteNotifier.new);

/// Fire-and-forget helper that logs instead of crashing the zone.
void runGuarded(Future<void> Function() f) {
  unawaited(
    f().catchError((Object e, StackTrace st) {
      debugPrint('Background op failed: $e\n$st');
    }),
  );
}
