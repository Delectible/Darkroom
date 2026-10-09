import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'core/background/background_worker.dart';
import 'core/db/app_database.dart';
import 'core/diagnostics/crash_log.dart';
import 'core/notifications/notification_service.dart';
import 'core/paths/app_paths.dart';
import 'core/providers.dart';
import 'core/settings/settings_repository.dart';
import 'features/camera/application/camera_ui_state.dart';
import 'features/camera/presentation/whole_body.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Bundled fonts (instant-print notes, Win98 pixel text) ship under the SIL OFL.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Caveat',
      'DotGothic16',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
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

  // Crash reports stay on the phone (Win98 Help > Crash Reports).
  await CrashLog.install(paths.supportDir);

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
  // The launch screen stays up until the 3D camera bodies have loaded, so
  // the camera never comes up half drawn.
  if (global.controls3d) await _warmBodies(container);
  runApp(UncontrolledProviderScope(container: container, child: const DarkroomApp()));
  if (launchPayload != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => route(launchPayload));
  }
}

Future<void> _warmBodies(ProviderContainer container) async {
  try {
    // The 3D models and their studio: loaded once, kept for the session.
    await container.read(wholeArtProvider.future).timeout(const Duration(seconds: 8));
  } catch (_) {
    // too slow: the camera comes up with the classic body until they land
  }
}
