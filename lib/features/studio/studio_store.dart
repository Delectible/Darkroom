import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/paths/app_paths.dart';
import '../../core/providers.dart';
import '../camera/application/camera_ui_state.dart' show PrefKeys;

/// The prints in the Studio (their ids, in the order they went in). Their
/// spot on the corkboard shows the pin and an "In studio" note until they
/// come back.
final studioProvider = NotifierProvider<StudioNotifier, List<String>>(StudioNotifier.new);

class StudioNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    try {
      return ref.read(sharedPrefsProvider).getStringList(PrefKeys.studioItems) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  bool contains(String id) => state.contains(id);

  Future<void> add(String id) async {
    if (state.contains(id)) return;
    await _set([...state, id]);
  }

  /// Back to the board.
  Future<void> remove(Iterable<String> ids) async {
    final out = {...ids};
    await _set([
      for (final id in state)
        if (!out.contains(id)) id,
    ]);
  }

  Future<void> clear() => _set(const []);

  /// Prints no longer on the board (thrown away) leave the Studio too.
  Future<void> keepOnly(Set<String> existing) async {
    if (state.every(existing.contains)) return;
    await _set([
      for (final id in state)
        if (existing.contains(id)) id,
    ]);
  }

  Future<void> _set(List<String> ids) async {
    state = ids;
    try {
      await ref.read(sharedPrefsProvider).setStringList(PrefKeys.studioItems, ids);
    } catch (_) {
      // (tests: nowhere to keep it)
    }
  }
}

/// What a Studio piece is.
enum StudioKind { strip, collage, scrapbook, flipbook }

/// One thing made in the Studio, kept in its book.
class StudioWork {
  const StudioWork({
    required this.id,
    required this.kind,
    required this.path,
    required this.createdAt,
    this.cover,
    this.pages = const [],
    this.paper,
    this.pageMs,
  });

  final String id;
  final StudioKind kind;

  /// The image (or the flip book's video).
  final String path;

  /// A flip book's first page, as a picture for the book.
  final String? cover;
  final DateTime createdAt;

  /// A flip book's photos, one a page (the book riffles through them, and
  /// a new speed is made from them); empty for flip books from before.
  final List<String> pages;

  /// A flip book's paper (a [StudioPaper] name) and time a page.
  final String? paper;
  final int? pageMs;

  StudioWork copyWith({String? path, String? cover, int? pageMs}) => StudioWork(
    id: id,
    kind: kind,
    path: path ?? this.path,
    createdAt: createdAt,
    cover: cover ?? this.cover,
    pages: pages,
    paper: paper,
    pageMs: pageMs ?? this.pageMs,
  );

  bool get isVideo => kind == StudioKind.flipbook;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'path': path,
    'cover': cover,
    'at': createdAt.millisecondsSinceEpoch,
    if (pages.isNotEmpty) 'pages': pages,
    'paper': ?paper,
    'pageMs': ?pageMs,
  };

  static StudioWork? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = StudioKind.values.asNameMap()[j['kind']];
    final id = j['id'], path = j['path'], at = j['at'];
    if (kind == null || id is! String || path is! String || at is! int) return null;
    return StudioWork(
      id: id,
      kind: kind,
      path: path,
      cover: j['cover'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(at),
      pages: [
        if (j['pages'] case final List<Object?> l)
          for (final x in l)
            if (x is String) x,
      ],
      paper: j['paper'] as String?,
      pageMs: j['pageMs'] as int?,
    );
  }
}

/// The Studio's book: everything made there, newest last, kept as files in
/// the app's support folder (studio/) with an index (book.json).
final studioBookProvider = AsyncNotifierProvider<StudioBook, List<StudioWork>>(StudioBook.new);

class StudioBook extends AsyncNotifier<List<StudioWork>> {
  static Future<Directory> folder() async {
    final dir = Directory('${(await AppPaths.resolve()).supportDir.path}/studio');
    await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _index() async => File('${(await folder()).path}/book.json');

  @override
  Future<List<StudioWork>> build() async {
    try {
      final f = await _index();
      if (!f.existsSync()) return const [];
      final list = jsonDecode(await f.readAsString());
      if (list is! List) return const [];
      return [
        for (final j in list)
          if (StudioWork.fromJson(j) case final w? when File(w.path).existsSync()) w,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// A new piece, its file already in [folder].
  Future<void> add(StudioWork w) async {
    final now = [...(state.value ?? await future), w];
    state = AsyncData(now);
    await _save(now);
  }

  /// [w] in place of the piece with its id (a flip book at a new speed).
  Future<void> replace(StudioWork w) async {
    final now = [for (final x in state.value ?? await future) x.id == w.id ? w : x];
    state = AsyncData(now);
    await _save(now);
  }

  Future<void> delete(StudioWork w) async {
    final now = [
      for (final x in state.value ?? const <StudioWork>[])
        if (x.id != w.id) x,
    ];
    state = AsyncData(now);
    await _save(now);
    for (final p in [w.path, w.cover, ...w.pages]) {
      if (p == null) continue;
      try {
        await File(p).delete();
      } catch (_) {}
    }
    if (w.pages.isNotEmpty) {
      try {
        await File(w.pages.first).parent.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> _save(List<StudioWork> works) async {
    final f = await _index();
    final part = File('${f.path}.part');
    await part.writeAsString(jsonEncode([for (final w in works) w.toJson()]));
    await part.rename(f.path);
  }
}

/// How many prints each piece takes.
class StudioNeeds {
  const StudioNeeds._(this.counts, this.label);

  final List<int> counts;
  final String label;

  int get min => counts.first;
  int get max => counts.last;

  bool fits(int n) => counts.contains(n);

  static StudioNeeds of(StudioKind k) => switch (k) {
    StudioKind.strip => const StudioNeeds._([3, 4], '3 or 4 prints'),
    StudioKind.collage => const StudioNeeds._([2, 4, 6, 9], '2, 4, 6 or 9 prints'),
    StudioKind.scrapbook => const StudioNeeds._([1, 2, 3, 4, 5, 6, 7, 8], '1 to 8 prints'),
    StudioKind.flipbook => StudioNeeds._([for (var i = 4; i <= 24; i++) i], '4 to 24 prints'),
  };
}
