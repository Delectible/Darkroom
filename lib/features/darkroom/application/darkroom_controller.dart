import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/sfx.dart';
import '../../../core/db/media_repository.dart';
import '../../../core/device/haptics.dart';
import '../../../core/providers.dart';
import '../../../core/review/review_prompt.dart';
import '../../camera/application/lab_note.dart';

@immutable
class DarkroomBanner {
  const DarkroomBanner(this.items, {this.labNote});

  final List<MediaItem> items;

  /// "Note from the Lab: ..." for a print that came back underexposed.
  final String? labNote;

  String get text {
    if (items.isEmpty) return 'Your prints are back from the lab';
    final videos = items.where((i) => i.isVideo).length;
    final photos = items.length - videos;
    if (items.length == 1) {
      return videos == 1 ? 'A reel just came out of the developer' : 'A print just came out of the developer';
    }
    return '${items.length} ${photos == 0 ? 'reels' : 'prints'} just came out of the developer';
  }
}

/// Shown once when over 20% of prints come out after their timer.
const slowPhoneNote =
    "Note from the Lab: your phone is the bottleneck in our darkroom. It's not a problem, "
    'but expect some prints to come out a little late.';

/// In-process darkroom clock.
///
/// While the app process is alive (foreground, or backgrounded but not yet
/// killed on Android) a single Timer is armed for the next `ready_at`; it
/// announces exactly on time and posts the consolidated notification when
/// the app isn't in front. The OS-level wake-ups (WorkManager / iOS
/// scheduled notifications) are re-armed after every change so the process
/// being killed doesn't matter.
class DarkroomController extends Notifier<DarkroomBanner?> {
  Timer? _timer;
  Timer? _bannerTimer;
  bool _checking = false;
  bool _again = false;

  @override
  DarkroomBanner? build() {
    ref.listen(filmItemsProvider, (_, _) => _arm());
    ref.listen<AppLifecycleState>(appLifecycleProvider, (prev, next) {
      if (next == AppLifecycleState.resumed) {
        // The WorkManager isolate may have finished/announced prints while we
        // were away; its writes don't reach this isolate's change feed.
        ref.read(filmRepositoryProvider).notifyChanged();
        ref.read(sdCardRepositoryProvider).notifyChanged();
        unawaited(check());
      }
    });
    ref.onDispose(() {
      _timer?.cancel();
      _bannerTimer?.cancel();
    });
    Future.microtask(check);
    return null;
  }

  void _arm() {
    _timer?.cancel();
    final items = ref.read(filmItemsProvider).value ?? const <MediaItem>[];
    final now = DateTime.now();
    DateTime? next;
    var dueNow = false;
    for (final m in items) {
      if (m.notified || m.status == MediaStatus.failed) continue;
      if (m.isDevelopedAt(now)) {
        dueNow = true;
      } else if (m.readyAt.isAfter(now) && (next == null || m.readyAt.isBefore(next))) {
        next = m.readyAt;
      }
    }
    if (dueNow) {
      unawaited(check());
    } else if (next != null) {
      _timer = Timer(next.difference(now) + const Duration(milliseconds: 60), check);
    }
  }

  Future<void> check() async {
    if (_checking) {
      _again = true;
      return;
    }
    _checking = true;
    try {
      do {
        _again = false;
        final engine = ref.read(darkroomEngineProvider);
        final foreground = ref.read(appLifecycleProvider) == AppLifecycleState.resumed;
        final fresh = await engine.announceDeveloped(foreground: foreground);
        if (!ref.mounted) return;
        // Notes from the lab ride with their prints, once developed (also
        // ones that came out while the app was closed).
        var notes = const <String>[];
        if (foreground) {
          final now = DateTime.now();
          final developed = (ref.read(filmItemsProvider).value ?? const <MediaItem>[])
              .where((m) => m.isDevelopedAt(now))
              .map((m) => m.id);
          notes = await LabNote.take(ref.read(sharedPrefsProvider), {
            ...developed,
            ...fresh.map((m) => m.id),
          });
          if (!ref.mounted) return;
        }
        var note = notes.isEmpty ? null : notes.last;
        // Once, if this phone keeps missing the darkroom's timers.
        final stats = ref.read(developStatsProvider);
        if (foreground && fresh.isNotEmpty && note == null && stats.shouldWarn) {
          note = slowPhoneNote;
          unawaited(stats.markTold());
        }
        if (fresh.isEmpty && note != null) {
          state = DarkroomBanner(const [], labNote: note);
          _bannerTimer?.cancel();
          _bannerTimer = Timer(const Duration(seconds: 8), dismissBanner);
        }
        if (fresh.isNotEmpty && foreground) {
          // A small moment: a soft tick and a light tap as the banner drops
          // (the gallery button's print swaps in on its own).
          Sfx.keyUp.play();
          unawaited(Haptics.lightImpact());
          final now = DateTime.now();
          final total = (ref.read(filmItemsProvider).value ?? const <MediaItem>[])
              .where((m) => m.isDevelopedAt(now))
              .length;
          ref.read(reviewPromptProvider).developed(fresh.length, total: total);
          state = DarkroomBanner(fresh, labNote: note);
          _bannerTimer?.cancel();
          _bannerTimer = Timer(Duration(seconds: note == null ? 4 : 8), dismissBanner);
        }
        await engine.reschedule();
      } while (_again && ref.mounted);
    } finally {
      _checking = false;
    }
    if (ref.mounted) _arm();
  }

  void dismissBanner() => state = null;
}

final darkroomControllerProvider = NotifierProvider<DarkroomController, DarkroomBanner?>(
  DarkroomController.new,
);
