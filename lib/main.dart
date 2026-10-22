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
import 'core/device/upright.dart';
import 'core/diagnostics/crash_log.dart';
import 'core/monetization/pro.dart';
import 'core/notifications/notification_service.dart';
import 'core/paths/app_paths.dart';
import 'core/providers.dart';
import 'core/settings/settings_repository.dart';
import 'features/camera/application/camera_ui_state.dart';
import 'features/camera/presentation/whole_body.dart';

/// The start-up step under way, shown if launching fails or hangs.
String _stage = 'starting';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A hang or a throw before the first frame used to leave the launch screen
  // up for good: show what got stuck instead (if the start finishes late,
  // the app replaces this screen).
  try {
    await _start().timeout(const Duration(seconds: 25));
  } catch (e, s) {
    runApp(_StartupFailed(stage: _stage, error: '$e', stack: '$s'));
  }
}

Future<void> _start() async {
  // Bundled fonts (instant-print notes, Win98 pixel text) ship under the SIL OFL.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Caveat',
      'DotGothic16',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  // The camera UI is portrait-locked; landscape shots are still captured in
  // landscape (EXIF orientation follows the physical device).
  _stage = 'orientation';
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(UprightApp.systemUi(turned: false));

  _stage = 'storage';
  final (paths, db, prefs) = await (
    AppPaths.resolve(),
    AppDatabase.open(),
    SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(allowList: PrefKeys.all),
    ),
  ).wait;

  // Crash reports stay on the phone (Win98 Help > Crash Reports).
  _stage = 'crash log';
  await CrashLog.install(paths.supportDir);

  final settingsRepo = SettingsRepository(db);
  _stage = 'settings';
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

  _stage = 'notifications';
  await notifications.init(onTap: route);
  _stage = 'background worker';
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

  _stage = 'launch payload';
  final launchPayload = await notifications.launchPayload();
  // The launch screen stays up until the 3D camera bodies have loaded, so
  // the camera never comes up half drawn.
  _stage = '3D cameras';
  if (global.controls3d) await _warmBodies(container);
  // Store: listen for purchases and quietly restore an earlier Pro.
  unawaited(container.read(proStoreProvider).start());
  _stage = 'first frame';
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

/// Launch failed or hung: say where, with a report to copy.
class _StartupFailed extends StatelessWidget {
  const _StartupFailed({required this.stage, required this.error, required this.stack});

  final String stage, error, stack;

  @override
  Widget build(BuildContext context) {
    final report = 'Darkroom failed to start at: $stage\n$error\n$stack';
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF111111),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The darkroom door is stuck.',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text('Stuck at: $stage', style: const TextStyle(color: Colors.white70, fontSize: 15)),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(error, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Clipboard.setData(ClipboardData(text: report)),
                  child: const Text('Copy error report'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
