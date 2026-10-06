import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';

import '../../viewer/presentation/media_actions.dart';

import '../../../core/db/media_repository.dart';
import '../../../core/providers.dart';
import '../../camera/application/camera_ui_state.dart';
import '../../cameras/domain/camera_catalog.dart';
import '../../cameras/domain/camera_spec.dart';

enum ExplorerView { largeIcons, smallIcons, details }

enum ExplorerSort { name, date, size }

enum ExplorerFilter { all, photos, videos }

@immutable
class ExplorerPrefs {
  const ExplorerPrefs({
    this.view = ExplorerView.largeIcons,
    this.sort = ExplorerSort.date,
    this.ascending = false,
    this.filter = ExplorerFilter.all,
    this.showTree = false,
  });

  final ExplorerView view;
  final ExplorerSort sort;
  final bool ascending;
  final ExplorerFilter filter;
  final bool showTree;

  ExplorerPrefs copyWith({
    ExplorerView? view,
    ExplorerSort? sort,
    bool? ascending,
    ExplorerFilter? filter,
    bool? showTree,
  }) => ExplorerPrefs(
    view: view ?? this.view,
    sort: sort ?? this.sort,
    ascending: ascending ?? this.ascending,
    filter: filter ?? this.filter,
    showTree: showTree ?? this.showTree,
  );
}

class ExplorerPrefsNotifier extends Notifier<ExplorerPrefs> {
  @override
  ExplorerPrefs build() {
    final p = ref.read(sharedPrefsProvider);
    T pick<T extends Enum>(List<T> values, String key, T fallback) =>
        values.asNameMap()[p.getString(key)] ?? fallback;
    return ExplorerPrefs(
      view: pick(ExplorerView.values, PrefKeys.explorerView, ExplorerView.largeIcons),
      sort: pick(ExplorerSort.values, PrefKeys.explorerSort, ExplorerSort.date),
      ascending: p.getBool(PrefKeys.explorerSortAsc) ?? false,
      filter: pick(ExplorerFilter.values, PrefKeys.explorerFilter, ExplorerFilter.all),
      showTree: p.getBool(PrefKeys.explorerTree) ?? false,
    );
  }

  Future<void> _save() async {
    final p = ref.read(sharedPrefsProvider);
    await p.setString(PrefKeys.explorerView, state.view.name);
    await p.setString(PrefKeys.explorerSort, state.sort.name);
    await p.setBool(PrefKeys.explorerSortAsc, state.ascending);
    await p.setString(PrefKeys.explorerFilter, state.filter.name);
    await p.setBool(PrefKeys.explorerTree, state.showTree);
  }

  void setView(ExplorerView v) {
    state = state.copyWith(view: v);
    unawaited(_save());
  }

  /// Same column again flips the direction, like clicking a details header.
  void sortBy(ExplorerSort s) {
    state = s == state.sort
        ? state.copyWith(ascending: !state.ascending)
        : state.copyWith(sort: s, ascending: s == ExplorerSort.name);
    unawaited(_save());
  }

  void setFilter(ExplorerFilter f) {
    state = state.copyWith(filter: f);
    unawaited(_save());
  }

  void toggleTree() {
    state = state.copyWith(showTree: !state.showTree);
    unawaited(_save());
  }
}

final explorerPrefsProvider = NotifierProvider<ExplorerPrefsNotifier, ExplorerPrefs>(
  ExplorerPrefsNotifier.new,
);

List<MediaItem> _all(Ref ref) => ref.watch(sdCardItemsProvider).value ?? const <MediaItem>[];

/// The explorer's drives that hold files.
enum Drive { sd, floppy, c }

bool _onFloppy(MediaItem m) => CameraCatalog.byId(m.cameraId).storage == DigitalStorage.floppy;

/// Files still on the virtual card. Failed renders stay visible as
/// "corrupt" files (with the error on open) instead of silently vanishing.
final sdCardFilesProvider = Provider<List<MediaItem>>(
  (ref) => _all(ref).where((m) => m.onSdCard && !_onFloppy(m)).toList(),
);

/// Camcorder clips waiting on the floppies in A: (not yet copied to C:).
final floppyFilesProvider = Provider<List<MediaItem>>(
  (ref) => _all(ref).where((m) => m.onSdCard && _onFloppy(m)).toList(),
);

/// Files moved to "Local Disk (C:)" (also in the phone's photo library).
final cDriveFilesProvider = Provider<List<MediaItem>>((ref) => _all(ref).where((m) => !m.onSdCard).toList());

/// What a content pane shows: filtered + sorted.
final explorerItemsProvider = Provider.family<List<MediaItem>, Drive>((ref, drive) {
  final prefs = ref.watch(explorerPrefsProvider);
  final source = switch (drive) {
    Drive.sd => ref.watch(sdCardFilesProvider),
    Drive.floppy => ref.watch(floppyFilesProvider),
    Drive.c => ref.watch(cDriveFilesProvider),
  };
  final items = source.where(
    (m) => switch (prefs.filter) {
      ExplorerFilter.all => true,
      ExplorerFilter.photos => !m.isVideo,
      ExplorerFilter.videos => m.isVideo,
    },
  );
  int cmp(MediaItem a, MediaItem b) => switch (prefs.sort) {
    ExplorerSort.name => a.fileName.compareTo(b.fileName),
    ExplorerSort.date => a.capturedAt.compareTo(b.capturedAt),
    ExplorerSort.size => (a.bytes ?? 0).compareTo(b.bytes ?? 0),
  };
  return items.toList()..sort((a, b) => prefs.ascending ? cmp(a, b) : cmp(b, a));
});

/// Virtual card capacity (a period-correct 128MB card).
const sdCardCapacityBytes = 128 * 1024 * 1024;

/// A formatted 3½" high-density disk.
const floppyCapacityBytes = 1457664;

/// How many floppies a file spans.
int floppiesFor(int? bytes) => math.max(1, ((bytes ?? 0) / floppyCapacityBytes).ceil());

@immutable
class TransferState {
  const TransferState({
    required this.total,
    this.done = 0,
    this.current,
    this.failures = const [],
    this.finished = false,
    this.cancelled = false,
  });

  final int total;
  final int done;
  final String? current;
  final List<String> failures;
  final bool finished;
  final bool cancelled;

  double get progress => total == 0 ? 1 : done / total;

  TransferState copyWith({
    int? done,
    String? current,
    List<String>? failures,
    bool? finished,
    bool? cancelled,
  }) => TransferState(
    total: total,
    done: done ?? this.done,
    current: current ?? this.current,
    failures: failures ?? this.failures,
    finished: finished ?? this.finished,
    cancelled: cancelled ?? this.cancelled,
  );
}

enum TransferOutcome { done, nothingToDo, accessDenied, partial, cancelled }

/// "Move to C:" / "Transfer": copies ready files from the card into the
/// public photo library (album "Darkroom") and moves them to "Local Disk
/// (C:)", where they can be opened. Nothing leaves the card unless the OS
/// confirmed the copy.
class SdTransferNotifier extends Notifier<TransferState?> {
  bool _cancel = false;

  @override
  TransferState? build() => null;

  void cancel() => _cancel = true;

  /// [ids] = null moves every ready file on the card.
  Future<TransferOutcome> moveToC({Iterable<String>? ids}) async {
    if (state != null && !state!.finished) return TransferOutcome.nothingToDo;
    final repo = ref.read(sdCardRepositoryProvider);
    final wanted = ids?.toSet();
    final ready = (await repo.readyItems())
        .where((m) => m.onSdCard && (wanted == null || wanted.contains(m.id)))
        .toList();
    if (ready.isEmpty) return TransferOutcome.nothingToDo;

    final access = await Gal.hasAccess(toAlbum: true) || await Gal.requestAccess(toAlbum: true);
    if (!access) return TransferOutcome.accessDenied;

    _cancel = false;
    state = TransferState(total: ready.length);
    final failures = <String>[];
    for (final item in ready) {
      if (_cancel) {
        state = state!.copyWith(cancelled: true, finished: true);
        return TransferOutcome.cancelled;
      }
      state = state!.copyWith(current: item.fileName);
      try {
        final path = item.outputPath;
        if (path == null || !File(path).existsSync()) throw const FileSystemException('missing');
        final err = await keepMedia(repo, item, album: digitalAlbum, moveToC: true);
        if (err != null) throw FileSystemException(err);
      } catch (e) {
        debugPrint('Transfer of ${item.fileName} failed: $e');
        failures.add(item.fileName);
      }
      state = state!.copyWith(done: state!.done + 1, failures: [...failures]);
    }
    state = state!.copyWith(finished: true);
    return failures.isEmpty ? TransferOutcome.done : TransferOutcome.partial;
  }

  void reset() => state = null;
}

final sdTransferProvider = NotifierProvider<SdTransferNotifier, TransferState?>(SdTransferNotifier.new);
