import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../../core/db/media_repository.dart';
import '../../../viewer/presentation/media_actions.dart';
import '../../application/sd_card_controller.dart';
import 'pixel_icons.dart';
import 'win98_widgets.dart';

/// The three places the explorer can show.
/// Tab order in the explorer.
enum ExplorerPlace { sd, floppy, c, photoRoom, myComputer }

/// A folder shown before a folder's files (Photo Room, in C:).
typedef ExplorerFolder = ({
  String name,
  int files,
  bool selected,
  VoidCallback onSelect,
  VoidCallback onOpen,
});

/// Files on the card are listed but locked; files on C: open normally.
class ExplorerFilePane extends StatelessWidget {
  const ExplorerFilePane({
    super.key,
    required this.items,
    required this.view,
    required this.prefs,
    required this.controller,
    required this.selected,
    required this.locked,
    required this.onSelect,
    required this.onOpen,
    required this.onClearSelection,
    required this.onSort,
    this.emptyText,
    this.emptyNote,
    this.folders = const [],
    this.multi = false,
  });

  /// Multi-Select: a tap adds a file to the selection or takes it out
  /// (nothing opens), like holding Ctrl.
  final bool multi;

  /// Folders listed first, always (a tap opens one).
  final List<ExplorerFolder> folders;

  /// What an empty drive says (default: SD card or plain folder).
  final String? emptyText;

  /// A line under [emptyText] (why it's empty).
  final String? emptyNote;

  final List<MediaItem> items;
  final ExplorerView view;
  final ExplorerPrefs prefs;
  final ScrollController controller;
  final Set<String> selected;
  final bool locked;
  final ValueChanged<MediaItem> onSelect;
  final ValueChanged<MediaItem> onOpen;
  final VoidCallback onClearSelection;
  final ValueChanged<ExplorerSort> onSort;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && folders.isEmpty) {
      return GestureDetector(
        onTap: onClearSelection,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emptyText ?? (locked ? 'There are no files on the SD card.' : 'This folder is empty.')),
              if (emptyNote case final note?) ...[
                const SizedBox(height: 6),
                Text(note, style: W98.text.copyWith(color: W98.shadow)),
              ],
            ],
          ),
        ),
      );
    }
    Widget item(MediaItem m, Widget Function(bool selected) builder) => Builder(
      builder: (anchor) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // Second tap on a selected file opens it (double-click is fiddly
          // on a phone). In Multi-Select every tap goes to [onSelect].
          if (!multi && selected.contains(m.id)) {
            onOpen(m);
          } else {
            onSelect(m);
          }
        },
        // (no onDoubleTap: waiting to rule one out held every tap's
        // highlight back ~300 ms; the second tap opens anyway)
        onLongPress: multi
            ? null
            : () {
                onSelect(m);
                if (m.isReady && !locked) unawaited(shareMedia(anchor, m));
              },
        child: builder(selected.contains(m.id)),
      ),
    );

    switch (view) {
      case ExplorerView.largeIcons:
        // every thumbnail's tiny copy, decoded ahead (see _Thumb)
        _Thumb.warm(context, [
          for (final m in items)
            if (m.isReady) ?m.thumbPath,
        ]);
        return GridView.builder(
          controller: controller,
          // (built, and decoded, well before they scroll into view)
          scrollCacheExtent: const ScrollCacheExtent.viewport(1.5),
          padding: const EdgeInsets.all(6),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 96,
            mainAxisExtent: 116,
            crossAxisSpacing: 4,
            mainAxisSpacing: 6,
          ),
          itemCount: folders.length + items.length,
          itemBuilder: (context, i) => i < folders.length
              ? _FolderTile(folder: folders[i], view: view)
              : item(
                  items[i - folders.length],
                  (sel) => _LargeIcon(item: items[i - folders.length], selected: sel, locked: locked),
                ),
        );
      case ExplorerView.smallIcons:
        return GridView.builder(
          controller: controller,
          padding: const EdgeInsets.all(4),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 150,
            mainAxisExtent: 22,
          ),
          itemCount: folders.length + items.length,
          itemBuilder: (context, i) {
            if (i < folders.length) return _FolderTile(folder: folders[i], view: view);
            final m = items[i - folders.length];
            return item(
              m,
              (sel) => Row(
                children: [
                  ExplorerFileIcon(item: m, locked: locked),
                  const SizedBox(width: 4),
                  Flexible(
                    child: _Label(text: m.fileName, selected: sel, maxLines: 1),
                  ),
                ],
              ),
            );
          },
        );
      case ExplorerView.details:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DetailsHeader(prefs: prefs, onSort: onSort),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: folders.length + items.length,
                itemExtent: 22,
                itemBuilder: (context, i) {
                  if (i < folders.length) return _FolderTile(folder: folders[i], view: view);
                  final m = items[i - folders.length];
                  return item(
                    m,
                    (sel) => Row(
                      children: [
                        const SizedBox(width: 2),
                        ExplorerFileIcon(item: m, locked: locked),
                        const SizedBox(width: 4),
                        Expanded(
                          flex: 5,
                          child: _Label(text: m.fileName, selected: sel, maxLines: 1),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            m.isReady ? formatBytes(m.bytes) : '…',
                            textAlign: TextAlign.right,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: Text(
                            m.isVideo ? 'Movie Clip' : 'JPEG Image',
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Text(explorerDate(m.capturedAt), maxLines: 1, overflow: TextOverflow.clip),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
    }
  }
}

/// A folder among the files: tap to open it.
class _FolderTile extends StatelessWidget {
  const _FolderTile({required this.folder, required this.view});

  final ExplorerFolder folder;
  final ExplorerView view;

  @override
  Widget build(BuildContext context) {
    final Widget look = switch (view) {
      ExplorerView.largeIcons => Column(
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: Center(
              child: ColorFiltered(
                colorFilter: folder.selected
                    ? ColorFilter.mode(W98.navy.withValues(alpha: 0.5), BlendMode.srcATop)
                    : const ColorFilter.mode(Color(0x00000000), BlendMode.dst),
                child: const PixelIconView(PixelIcon.folder, size: 48),
              ),
            ),
          ),
          const SizedBox(height: 4),
          _Label(text: folder.name, selected: folder.selected, maxLines: 2),
        ],
      ),
      ExplorerView.smallIcons => Row(
        children: [
          const PixelIconView(PixelIcon.folder),
          const SizedBox(width: 4),
          Flexible(
            child: _Label(text: folder.name, selected: folder.selected, maxLines: 1),
          ),
        ],
      ),
      ExplorerView.details => Row(
        children: [
          const SizedBox(width: 2),
          const PixelIconView(PixelIcon.folder),
          const SizedBox(width: 4),
          Expanded(
            flex: 5,
            child: _Label(text: folder.name, selected: folder.selected, maxLines: 1),
          ),
          Expanded(flex: 3, child: Text('${folder.files} file(s)', textAlign: TextAlign.right, maxLines: 1)),
          const SizedBox(width: 8),
          const Expanded(flex: 3, child: Text('File Folder', maxLines: 1, overflow: TextOverflow.clip)),
          const Expanded(flex: 4, child: SizedBox()),
        ],
      ),
    };
    // like a file: the first tap selects it, a second one opens it
    return Semantics(
      button: true,
      selected: folder.selected,
      label: 'Folder ${folder.name}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: folder.selected ? folder.onOpen : folder.onSelect,
        child: look,
      ),
    );
  }
}

String explorerDate(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '${t.month}/${t.day}/${t.year % 100 < 10 ? '0' : ''}${t.year % 100} '
      '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

class _DetailsHeader extends StatelessWidget {
  const _DetailsHeader({required this.prefs, required this.onSort});

  final ExplorerPrefs prefs;
  final ValueChanged<ExplorerSort> onSort;

  @override
  Widget build(BuildContext context) {
    Widget col(String label, int flex, ExplorerSort? sort) => Expanded(
      flex: flex,
      child: SizedBox(
        height: 20,
        child: Win98Button(
          onPressed: sort == null ? () {} : () => onSort(sort),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.clip)),
              if (sort != null && prefs.sort == sort)
                Win98GlyphView(prefs.ascending ? Win98Glyph.up : Win98Glyph.down, dot: 1),
            ],
          ),
        ),
      ),
    );
    return Row(
      children: [
        col('Name', 6, ExplorerSort.name),
        col('Size', 3, ExplorerSort.size),
        col('Type', 3, null),
        col('Modified', 4, ExplorerSort.date),
      ],
    );
  }
}

class ExplorerFileIcon extends StatelessWidget {
  const ExplorerFileIcon({super.key, required this.item, this.locked = false});

  final MediaItem item;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final base = PixelIconView(switch (item.status) {
      MediaStatus.failed => PixelIcon.error,
      MediaStatus.processing => PixelIcon.hourglass,
      MediaStatus.ready => item.isVideo ? PixelIcon.videoFile : PixelIcon.imageFile,
    });
    if (!locked || !item.isReady) return base;
    return SizedBox(
      width: 16,
      height: 16,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          base,
          const Positioned(right: -3, bottom: -3, child: PixelIconView(PixelIcon.lock, size: 10)),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.text, required this.selected, this.maxLines = 2});

  final String text;
  final bool selected;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: selected
          ? BoxDecoration(
              color: W98.navy,
              border: Border.all(color: const Color(0xFFFFFF80), width: 0.5),
            )
          : null,
      child: Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: W98.text.copyWith(color: selected ? W98.selectInk : W98.windowInk),
      ),
    );
  }
}

/// "Large Icons": a framed thumbnail (the 9x thumbnail view) + 8.3 name.
/// Locked (SD) files show their thumbnail behind a padlock.
class _LargeIcon extends StatelessWidget {
  const _LargeIcon({required this.item, required this.selected, required this.locked});

  final MediaItem item;
  final bool selected;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final thumb = item.thumbPath;
    return Column(
      children: [
        SizedBox(
          width: 72,
          height: 72,
          child: Win98Bevel(
            style: BevelStyle.sunken,
            color: W98.window,
            padding: const EdgeInsets.all(3),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (item.isReady && thumb != null)
                  _Thumb(path: thumb)
                else
                  Center(
                    child: PixelIconView(
                      item.status == MediaStatus.failed ? PixelIcon.error : PixelIcon.hourglass,
                      size: 32,
                    ),
                  ),
                if (selected) const ColoredBox(color: Color(0x55000080)),
                if (item.isVideo)
                  const Positioned(right: 0, bottom: 0, child: PixelIconView(PixelIcon.videoFile)),
                if (locked && item.isReady)
                  const Positioned(left: 0, bottom: 0, child: PixelIconView(PixelIcon.lock)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 3),
        _Label(text: item.fileName, selected: selected),
      ],
    );
  }
}

class ExplorerFolderTree extends StatelessWidget {
  const ExplorerFolderTree({super.key, required this.place, required this.onSelect});

  final ExplorerPlace place;
  final ValueChanged<ExplorerPlace> onSelect;

  @override
  Widget build(BuildContext context) {
    Widget node(
      int depth,
      PixelIcon icon,
      String label, {
      bool selected = false,
      VoidCallback? onTap,
      bool dim = false,
    }) {
      return GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(4 + depth * 12.0, 2, 2, 2),
          child: Row(
            children: [
              PixelIconView(icon),
              const SizedBox(width: 3),
              Flexible(
                child: Container(
                  color: selected ? W98.navy : null,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: dim
                        ? W98.disabledText
                        : W98.text.copyWith(color: selected ? W98.selectInk : W98.windowInk),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Win98Bevel(
      style: BevelStyle.sunken,
      color: W98.window,
      padding: const EdgeInsets.all(2),
      child: ListView(
        children: [
          node(
            0,
            PixelIcon.computer,
            'My Computer',
            selected: place == ExplorerPlace.myComputer,
            onTap: () => onSelect(ExplorerPlace.myComputer),
          ),
          node(1, PixelIcon.floppy, '3½ Floppy (A:)', onTap: () => onSelect(ExplorerPlace.floppy)),
          node(
            2,
            PixelIcon.folderOpen,
            'TAPE01',
            selected: place == ExplorerPlace.floppy,
            onTap: () => onSelect(ExplorerPlace.floppy),
          ),
          node(1, PixelIcon.hardDrive, 'Local Disk (C:)', onTap: () => onSelect(ExplorerPlace.c)),
          node(2, PixelIcon.folder, 'My Pictures', onTap: () => onSelect(ExplorerPlace.c)),
          node(
            3,
            PixelIcon.folderOpen,
            'Darkroom',
            selected: place == ExplorerPlace.c,
            onTap: () => onSelect(ExplorerPlace.c),
          ),
          node(
            3,
            place == ExplorerPlace.photoRoom ? PixelIcon.folderOpen : PixelIcon.folder,
            'Photo Room',
            selected: place == ExplorerPlace.photoRoom,
            onTap: () => onSelect(ExplorerPlace.photoRoom),
          ),
          node(1, PixelIcon.removableDrive, 'SD Card (E:)', onTap: () => onSelect(ExplorerPlace.sd)),
          node(2, PixelIcon.folder, 'DCIM', onTap: () => onSelect(ExplorerPlace.sd)),
          node(
            3,
            PixelIcon.folderOpen,
            '100DRKRM',
            selected: place == ExplorerPlace.sd,
            onTap: () => onSelect(ExplorerPlace.sd),
          ),
        ],
      ),
    );
  }
}

class ExplorerMyComputerPane extends StatelessWidget {
  const ExplorerMyComputerPane({
    super.key,
    required this.sdBytes,
    required this.cBytes,
    required this.sdCount,
    required this.floppyCount,
    required this.onOpenSd,
    required this.onOpenC,
    required this.onOpenFloppy,
  });

  final int sdBytes;
  final int cBytes;
  final int sdCount;
  final int floppyCount;
  final VoidCallback onOpenSd;
  final VoidCallback onOpenC;
  final VoidCallback onOpenFloppy;

  @override
  Widget build(BuildContext context) {
    Widget drive(PixelIcon icon, String label, {VoidCallback? onOpen, Widget? extra, bool dim = false}) =>
        GestureDetector(
          onTap: onOpen,
          child: SizedBox(
            width: 112,
            child: Column(
              children: [
                Opacity(opacity: dim ? 0.45 : 1, child: PixelIconView(icon, size: 40)),
                const SizedBox(height: 4),
                Text(label, textAlign: TextAlign.center, style: dim ? W98.disabledText : W98.text),
                if (extra != null) ...[const SizedBox(height: 4), extra],
              ],
            ),
          ),
        );

    final frac = (sdBytes / sdCardCapacityBytes).clamp(0.0, 1.0);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        runSpacing: 16,
        children: [
          drive(
            PixelIcon.floppy,
            floppyCount == 0 ? '3½ Floppy (A:)\n(no disk)' : '3½ Floppy (A:)',
            dim: floppyCount == 0,
            onOpen: onOpenFloppy,
            extra: floppyCount == 0
                ? null
                : Text('$floppyCount tape clip(s)', style: const TextStyle(fontSize: 10)),
          ),
          drive(
            PixelIcon.hardDrive,
            'Local Disk (C:)',
            onOpen: onOpenC,
            extra: Text('${formatBytes(cBytes)} used', style: const TextStyle(fontSize: 10)),
          ),
          drive(
            PixelIcon.removableDrive,
            sdCount == 0 ? 'SD Card (E:)\n(empty)' : 'SD Card (E:)',
            onOpen: onOpenSd,
            extra: Column(
              children: [
                Win98ProgressBar(value: math.max(frac, sdCount == 0 ? 0 : 0.02)),
                const SizedBox(height: 2),
                Text(
                  '${formatBytes(sdCardCapacityBytes - sdBytes)} free of 128MB',
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ExplorerAddressBar extends StatelessWidget {
  const ExplorerAddressBar({super.key, required this.path, required this.icon});

  final String path;
  final PixelIcon icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('Address')),
          Expanded(
            child: Win98Bevel(
              style: BevelStyle.sunken,
              color: W98.window,
              padding: const EdgeInsets.fromLTRB(4, 3, 2, 3),
              child: Row(
                children: [
                  PixelIconView(icon),
                  const SizedBox(width: 4),
                  Expanded(child: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ExplorerStatusBar extends StatelessWidget {
  const ExplorerStatusBar({super.key, required this.cells});

  final List<String> cells;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Expanded(
            flex: i == 0 ? 3 : 2,
            child: Win98Bevel(
              style: BevelStyle.shallow,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(cells[i], maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ],
    );
  }
}

/// A Large Icons thumbnail: a tiny copy first (decoded in a moment and kept
/// for every file, [warm]; blocky, as a 9x thumbnail loading would be), the
/// real one over it once decoded. A fast scroll never shows empty frames.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.path});

  final String path;

  static const _previewWidth = 32;
  static final _warmed = <String>{};

  static ImageProvider _preview(String path) => ResizeImage(FileImage(File(path)), width: _previewWidth);

  /// Decodes the tiny copies of [paths] not yet asked for, a few at a time.
  static void warm(BuildContext context, List<String> paths) {
    final todo = [
      for (final p in paths)
        if (_warmed.add(p)) p,
    ];
    if (todo.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      for (var i = 0; i < todo.length; i += 6) {
        if (!context.mounted) return;
        await Future.wait([
          for (final p in todo.skip(i).take(6)) precacheImage(_preview(p), context, onError: (_, _) {}),
        ]);
      }
    });
  }

  @override
  Widget build(BuildContext context) => Image.file(
    File(path),
    fit: BoxFit.contain,
    cacheWidth: 160,
    filterQuality: FilterQuality.none,
    gaplessPlayback: true,
    frameBuilder: (context, child, frame, sync) => frame == null && !sync
        ? Image(
            image: _preview(path),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.none,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          )
        : child,
    errorBuilder: (_, _, _) => const Center(child: PixelIconView(PixelIcon.imageFile, size: 32)),
  );
}
