import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'core/background/background_worker.dart';
import 'core/db/app_database.dart';
import 'core/notifications/notification_service.dart';
import 'core/paths/app_paths.dart';
import 'core/providers.dart';
import 'core/settings/settings_repository.dart';
import 'features/camera/application/camera_ui_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The camera UI is portrait-locked; landscape shots are still captured in
  // landscape (EXIF orientation follows the physical device).
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final (paths, db, prefs) = await (
    AppPaths.resolve(),
    AppDatabase.open(),
    SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(allowList: PrefKeys.all),
    ),
  ).wait;

  final settingsRepo = SettingsRepository(db);
  final (global, cameraSettings) = await (settingsRepo.loadGlobal(), settingsRepo.loadCameraSettings()).wait;

  final notifications = NotificationService(FlutterLocalNotificationsPlugin());

  final container = ProviderContainer(
    overrides: [
      appPathsProvider.overrideWithValue(paths),
      appDatabaseProvider.overrideWithValue(db),
      sharedPrefsProvider.overrideWithValue(prefs),
      notificationServiceProvider.overrideWithValue(notifications),
      initialGlobalSettingsProvider.overrideWithValue(global),
      initialCameraSettingsProvider.overrideWithValue(cameraSettings),
    ],
  );

  void route(String? payload) {
    if (payload == NotificationService.corkboardPayload) {
      container.read(pendingRouteProvider.notifier).request('corkboard');
    }
  }

  await notifications.init(onTap: route);
  if (Platform.isAndroid) {
    await Workmanager().initialize(backgroundDispatcher);
  }

  // Startup maintenance, off the critical path:
  //  * resume captures interrupted by a kill,
  //  * purge orphaned un-filtered files from the capture cache,
  //  * re-arm the darkroom wake-ups (covers reboots on iOS too).
  unawaited(() async {
    final processor = container.read(captureProcessorProvider);
    await processor.recover();
    await processor.sweepOrphans();
    await container.read(darkroomEngineProvider).reschedule();
  }());

  final launchPayload = await notifications.launchPayload();
  runApp(UncontrolledProviderScope(container: container, child: const DarkroomApp()));
  if (launchPayload != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => route(launchPayload));
  }
}
