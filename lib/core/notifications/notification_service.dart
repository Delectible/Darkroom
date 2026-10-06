import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// Local notifications for the Darkroom.
///
/// Consolidation strategy: there is exactly ONE darkroom notification id.
/// Every time prints finish developing we *re-post the same id* with the
/// cumulative count of developed-but-unseen prints ("3 photos have finished
/// developing"), with `onlyAlertOnce` so updates replace the card silently
/// instead of stacking or buzzing again.
///
/// iOS cannot run our Dart code on a timer while suspended, so there the
/// future updates are pre-scheduled with zonedSchedule in coalesced batches
/// (one per ~minute window) grouped under one thread.
class NotificationService {
  NotificationService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static const darkroomId = 4100;
  static const _iosBatchBase = 4200;
  static const _iosMaxBatches = 32;
  static const corkboardPayload = 'route:corkboard';

  /// Android notification channels are immutable once created, so the quiet
  /// version needs a new id (the old, buzzing 'darkroom' channel is deleted
  /// at start-up).
  static const _channelId = 'darkroom_quiet';
  static const _legacyChannelId = 'darkroom';

  static const _android = AndroidNotificationDetails(
    _channelId,
    'Darkroom',
    channelDescription: 'Quietly tells you when film has finished developing.',
    importance: Importance.low, // shade + status bar only: no sound, no vibration
    priority: Priority.low,
    playSound: false,
    enableVibration: false,
    silent: true,
    onlyAlertOnce: true,
    category: AndroidNotificationCategory.status,
    groupKey: 'darkroom',
    icon: '@drawable/ic_stat_darkroom',
  );

  static const _darwin = DarwinNotificationDetails(
    threadIdentifier: 'darkroom',
    presentBanner: false, // in foreground the app shows its own banner
    presentList: true,
    presentSound: false,
    interruptionLevel: InterruptionLevel.passive, // no sound, no vibration, no wake
  );

  static const _details = NotificationDetails(android: _android, iOS: _darwin);

  Future<void> init({void Function(String? payload)? onTap}) async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_stat_darkroom'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (r) => onTap?.call(r.payload),
    );
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      try {
        await android?.deleteNotificationChannel(channelId: _legacyChannelId);
      } catch (_) {
        // never existed
      }
    }
  }

  /// Payload of the notification that cold-started the app, if any.
  Future<String?> launchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp ?? false) {
      return details!.notificationResponse?.payload;
    }
    return null;
  }

  Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    }
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    }
    return false;
  }

  /// Super 8 clips are "reels".
  @visibleForTesting
  static String developedMessage({required int photos, required int videos}) {
    const tail = 'finished developing in the Darkroom.';
    final total = photos + videos;
    if (total <= 1) return videos == 1 ? 'A reel has $tail' : 'A photo has $tail';
    if (videos == 0) return '$photos photos have $tail';
    if (photos == 0) return '$videos reels have $tail';
    String n(int c, String one) => c == 1 ? 'a $one' : '$c ${one}s';
    final head = n(photos, 'photo');
    return '${head[0].toUpperCase()}${head.substring(1)} and ${n(videos, 'reel')} have $tail';
  }

  /// Posts / updates the single consolidated darkroom notification.
  Future<void> showDeveloped({required int photos, required int videos}) async {
    if (photos + videos == 0) return;
    await _plugin.show(
      id: darkroomId,
      title: 'Darkroom',
      body: developedMessage(photos: photos, videos: videos),
      notificationDetails: _details,
      payload: corkboardPayload,
    );
  }

  Future<void> cancelDeveloped() => _plugin.cancel(id: darkroomId);

  /// iOS only: pre-schedules the cumulative updates for prints still in the
  /// developer. [readyTimes] must be sorted ascending; [alreadyUnseen] is
  /// the number of developed-but-unseen prints right now.
  Future<void> scheduleIosBatches({
    required List<({DateTime readyAt, bool isVideo})> pending,
    required int alreadyUnseenPhotos,
    required int alreadyUnseenVideos,
  }) async {
    if (!Platform.isIOS) return;
    for (var i = 0; i < _iosMaxBatches; i++) {
      await _plugin.cancel(id: _iosBatchBase + i);
    }
    if (pending.isEmpty) return;

    // Coalesce prints finishing within 60s of the batch's first print into a
    // single notification fired when the last of them is ready.
    const window = Duration(seconds: 60);
    var photos = alreadyUnseenPhotos, videos = alreadyUnseenVideos;
    var batch = 0;
    var i = 0;
    while (i < pending.length && batch < _iosMaxBatches) {
      final start = pending[i].readyAt;
      var fireAt = start;
      while (i < pending.length && pending[i].readyAt.difference(start) <= window) {
        fireAt = pending[i].readyAt;
        if (pending[i].isVideo) {
          videos++;
        } else {
          photos++;
        }
        i++;
      }
      await _plugin.zonedSchedule(
        id: _iosBatchBase + batch,
        title: 'Darkroom',
        body: developedMessage(photos: photos, videos: videos),
        scheduledDate: tz.TZDateTime.from(fireAt, tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: corkboardPayload,
      );
      batch++;
    }
  }
}
