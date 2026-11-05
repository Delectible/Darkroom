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
import 'core/device/camera_control.dart';
import 'core/background/background_worker.dart';
import 'core/db/app_database.dart';
import 'core/device/app_shortcuts.dart';
import 'core/device/device_memory.dart';
import 'core/device/upright.dart';
import 'core/diagnostics/crash_log.dart';
import 'core/diagnostics/launch_timer.dart';
import 'core/diagnostics/perf_recorder.dart';
import 'core/monetization/pro.dart';
import 'core/notifications/notification_service.dart';
import 'core/performance/quality.dart';
import 'core/paths/app_paths.dart';
import 'core/providers.dart';
import 'core/review/review_prompt.dart';
import 'core/settings/settings_repository.dart';
import 'core/shaders/shader_library.dart';
import 'core/startup/launch_curtain.dart';
import 'features/corkboard/presentation/print_frames.dart';
import 'features/camera/application/camera_session_controller.dart';
import 'features/camera/application/camera_ui_state.dart';
import 'features/camera/presentation/launch_picture.dart';
import 'features/camera/presentation/whole_body.dart';
import 'features/settings/application/settings_controllers.dart';

/// The start-up step under way, shown if launching fails or hangs.
String _stage = 'starting';

Future<void> main() async {
  LaunchTimer.begin();
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(LaunchTimer.measureBeforeMain());
  // Debug > Performance Report: frame timings are always kept (cheap).
  PerfRecorder.start();
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
  // (sent, not waited on: they land long before the first frame)
  unawaited(SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]));
  unawaited(UprightApp.applySystemUi(turned: false));

  _stage = 'storage';
  final (paths, db, prefs) = await (
    AppPaths.resolve(),
    AppDatabase.open(),
    SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(allowList: PrefKeys.all),
    ),
  ).wait;

  LaunchTimer.prefs = prefs;
  // The phone's RAM sizes the work the app takes on (prints developing at
  // once, the picture cache): read alongside the rest of the start-up.
  // The quality manager: the steps saved last time (core/performance).
  Quality.start(prefs);
  PrintFrames.prefs = prefs;
  unawaited(CameraControl.read());
  unawaited(DeviceMemory.apply().then((_) => GlobalSettingsNotifier.reapply()));
  // The picture of the camera from last time (opens on it if it matches).
  LaunchPicture.init(paths.supportDir);
  // (it judges only once the launch curtain has gone)
  unawaited(LaunchCurtain.gone.then((_) => Quality.listening = true));
  LaunchTimer.mark('storage open');
  // Crash reports stay on the phone (Win98 Help > Crash Reports).
  _stage = 'crash log';
  await CrashLog.install(paths.supportDir);

  final settingsRepo = SettingsRepository(db);
  _stage = 'settings';
  final (global, cameraSettings) = await (settingsRepo.loadGlobal(), settingsRepo.loadCameraSettings()).wait;

  LaunchTimer.mark('settings read');
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
  LaunchTimer.mark('notifications ready');
  // WorkManager (the darkroom's wake-ups) after the first frame: anything
  // scheduled before then waits for it.
  if (Platform.isAndroid) {
    final worker = Completer<void>();
    WorkmanagerDevelopScheduler.ready = worker.future;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => worker.complete(Workmanager().initialize(backgroundDispatcher).catchError((Object _) {})),
    );
  }

  // Startup maintenance, once the launch curtain has gone (redeveloping an
  // interrupted shot fought the launch for the CPU):
  //  * resume captures interrupted by a kill,
  //  * purge orphaned un-filtered files from the capture cache,
  //  * re-arm the darkroom wake-ups (covers reboots on iOS too).
  unawaited(() async {
    await LaunchCurtain.gone;
    final processor = container.read(captureProcessorProvider);
    await processor.recover();
    await processor.sweepOrphans();
    await container.read(darkroomEngineProvider).reschedule();
  }());

  // The 3D camera bodies load alongside the camera opening (the launch
  // curtain waits for both, app.dart). On the very first run they wait
  // until the welcome tour is up (onboarding_screen.dart), so the app
  // opens straight away.
  final onboarded = prefs.getBool(PrefKeys.onboarded) == true;
  if (global.controls3d && onboarded) {
    unawaited(container.read(wholeArtProvider.future).then((_) {}, onError: (Object _) {}));
  }
  // The camera list and the viewfinder's look (shaders, film LUT, grain)
  // start now too, not when the camera screen first builds.
  if (onboarded) {
    CameraSessionController.prefetch();
    void warm(Future<Object?> f) => unawaited(f.then((_) {}, onError: (Object _) {}));
    warm(container.read(shaderProgramsProvider.future));
    final spec = container.read(activeSpecProvider);
    if (spec.film != null) {
      warm(container.read(filmLutImageProvider(spec.id).future));
      warm(container.read(grainImageProvider.future));
    }
  }
  // Store: listen for purchases and quietly restore an earlier Pro.
  unawaited(container.read(proStoreProvider).start());
  container.read(reviewPromptProvider).launched();
  _stage = 'first frame';
  LaunchTimer.mark('app starts');
  runApp(UncontrolledProviderScope(container: container, child: const DarkroomApp()));
  AppShortcuts.start(container);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    LaunchTimer.mark('first frame');
    // Opened from a notification: go where it points.
    unawaited(
      notifications.launchPayload().then((p) {
        if (p != null) route(p);
      }, onError: (Object _) {}),
    );
  });
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
