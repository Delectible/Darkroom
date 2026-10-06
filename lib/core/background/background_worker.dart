import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import '../../features/darkroom/application/darkroom_engine.dart';
import '../db/app_database.dart';
import '../db/media_repository.dart';
import '../notifications/notification_service.dart';
import '../paths/app_paths.dart';
import '../processing/isolate_jobs.dart';
import '../processing/photo_pipeline.dart';
import '../settings/settings_repository.dart';

/// WorkManager wiring for the Darkroom on Android.
///
/// Each time a print is queued we register a one-off task that fires when the
/// next print is due. WorkManager persists it in its own database and
/// re-arms it after reboots, so it fires even if the app was swiped away or
/// the phone restarted. The worker announces what developed and chains the
/// next wake-up. Two alternating unique names are used so a running worker
/// never REPLACE-cancels itself when it schedules its successor.
class WorkmanagerDevelopScheduler implements DevelopWakeScheduler {
  const WorkmanagerDevelopScheduler({this.slot = 'a'});

  static const taskName = 'darkroom.develop';
  static const _uniquePrefix = 'darkroom.develop.';

  /// The slot this scheduler writes to ('a' from the UI, the other slot from
  /// inside a running worker).
  final String slot;

  @override
  Future<void> wakeAt(DateTime? at) async {
    if (!Platform.isAndroid) return;
    final name = '$_uniquePrefix$slot';
    if (at == null) {
      await Workmanager().cancelByUniqueName(name);
      return;
    }
    var delay = at.difference(DateTime.now());
    if (delay.isNegative) delay = Duration.zero;
    await Workmanager().registerOneOffTask(
      name,
      taskName,
      // A couple of seconds of slack so the row is definitely "ready" when
      // the worker reads it.
      initialDelay: delay + const Duration(seconds: 2),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      inputData: {'slot': slot},
    );
  }
}

/// Entry point of the background isolate WorkManager spins up.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != WorkmanagerDevelopScheduler.taskName) return true;
    try {
      WidgetsFlutterBinding.ensureInitialized();
      final slot = inputData?['slot'] == 'a' ? 'b' : 'a';
      await BackgroundDarkroom.run(nextSlot: slot);
      return true;
    } catch (e, st) {
      debugPrint('Darkroom worker failed: $e\n$st');
      return false; // WorkManager retries with backoff
    }
  });
}

class BackgroundDarkroom {
  const BackgroundDarkroom._();

  static Future<void> run({required String nextSlot}) async {
    final db = await AppDatabase.open();
    final paths = await AppPaths.resolve();
    final film = MediaRepository(db, paths, table: AppDatabase.filmTable);
    final notifications = NotificationService(FlutterLocalNotificationsPlugin());
    await notifications.init();
    final engine = DarkroomEngine(
      film: film,
      notifications: notifications,
      settings: SettingsRepository(db),
      scheduler: WorkmanagerDevelopScheduler(slot: nextSlot),
    );

    // Finish any still that was interrupted mid-processing (app killed right
    // after the shutter). Videos are left for the next app launch: FFmpeg
    // transcodes can outlive a worker's execution window.
    for (final item in await film.processing()) {
      if (item.isVideo || item.job == null) continue;
      final raw = item.rawPath;
      if (raw == null || !File(raw).existsSync()) {
        await film.markFailed(item.id, 'Capture file missing');
        continue;
      }
      final map = jsonDecode(item.job!) as Map<String, Object?>;
      final job = PhotoJob.fromJson(map);
      try {
        await film.bumpAttempts(item.id);
        final r = await renderPhotoInIsolate(job);
        await film.markReady(
          id: item.id,
          outputPath: job.outputPath,
          thumbPath: job.thumbPath,
          width: r.width,
          height: r.height,
          bytes: r.bytes,
        );
        // The un-filtered original can only be saved to the gallery from the
        // UI (permission prompt); in the background we just purge it.
        final orig = r.originalCopyPath;
        if (orig != null) {
          try {
            await File(orig).delete();
          } on FileSystemException {
            // already gone
          }
        }
        await File(raw).delete();
      } catch (e) {
        if (item.attempts >= 2) {
          await film.markFailed(item.id, e.toString());
          if (File(raw).existsSync()) await File(raw).delete();
        }
      }
    }

    await engine.announceDeveloped(foreground: false);
    await engine.reschedule();
  }
}
