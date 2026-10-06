import 'dart:io';

import '../../../core/db/media_repository.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/settings/settings_repository.dart';

/// Schedules a background wake-up for the next print to finish developing.
abstract interface class DevelopWakeScheduler {
  Future<void> wakeAt(DateTime? at);
}

/// The Darkroom's timekeeping, independent of any widget.
///
/// Development time is pure data: each print row stores an absolute epoch
/// `ready_at`. Nothing counts down in memory, so app kills, process death and
/// reboots cannot lose or reset a timer — on every start (UI or background
/// worker) we simply compare `ready_at` with the clock.
class DarkroomEngine {
  DarkroomEngine({
    required this.film,
    required this.notifications,
    required this.settings,
    required this.scheduler,
  });

  final MediaRepository film;
  final NotificationService notifications;
  final SettingsRepository settings;
  final DevelopWakeScheduler scheduler;

  /// Announces prints that finished developing since the last check.
  ///
  /// In the foreground the caller shows an in-app banner instead of a system
  /// notification. Returns the newly developed prints.
  Future<List<MediaItem>> announceDeveloped({required bool foreground}) async {
    final now = DateTime.now();
    final fresh = await film.developedUnnotified(now);
    if (fresh.isEmpty) return fresh;
    final global = await settings.loadGlobal();
    if (global.notificationsEnabled && !foreground) {
      final c = await film.unseenDevelopedCounts(now);
      await notifications.showDeveloped(photos: c.photos, videos: c.videos);
    }
    await film.markNotified([for (final m in fresh) m.id]);
    return fresh;
  }

  /// Re-arms the OS-level wake-ups. Call after any change to the queue.
  Future<void> reschedule() async {
    final now = DateTime.now();
    final global = await settings.loadGlobal();
    if (Platform.isIOS) {
      if (!global.notificationsEnabled || !global.darkroomEnabled) {
        await notifications.scheduleIosBatches(
          pending: const [],
          alreadyUnseenPhotos: 0,
          alreadyUnseenVideos: 0,
        );
        return;
      }
      final pending = await film.pendingDevelopment(now);
      final unseen = await film.unseenDevelopedCounts(now);
      await notifications.scheduleIosBatches(
        pending: [for (final m in pending) (readyAt: m.readyAt, isVideo: m.isVideo)],
        alreadyUnseenPhotos: unseen.photos,
        alreadyUnseenVideos: unseen.videos,
      );
      return;
    }
    // Android: one WorkManager one-off per "next print ready" (self-chaining).
    final next = global.notificationsEnabled ? await film.nextUnnotifiedReadyAt(after: now) : null;
    await scheduler.wakeAt(next);
  }

  /// The user looked at the Corkboard: clear the badge + notification.
  Future<void> markSeen() async {
    await film.markAllSeen(DateTime.now());
    await notifications.cancelDeveloped();
    await reschedule();
  }

  /// Darkroom toggled off in settings: everything in the developer is done.
  Future<void> developEverythingNow() async {
    await film.developAllNow(DateTime.now());
    await reschedule();
  }
}
