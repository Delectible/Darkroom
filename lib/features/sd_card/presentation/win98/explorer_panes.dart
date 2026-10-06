import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/db/media_repository.dart';
import '../../../viewer/presentation/media_actions.dart';
import '../../application/sd_card_controller.dart';
import 'pixel_icons.dart';
import 'win98_widgets.dart';

/// The three places the explorer can show.
enum ExplorerPlace { sd, c, myComputer }

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
  });

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
    if (items.isEmpty) {
      return GestureDetector(
        onTap: onClearSelection,
        child: Center(child: Text(locked ? 'There are no files on the SD card.' : 'This folder is empty.')),
      );
    }
    Widget item(MediaItem m, Widget Function(bool selected) builder) => Builder(
      builder: (anchor) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // Second tap on a selected file opens it (double-click is fiddly
          // on a phone).
          if (selected.contains(m.id)) {
            onOpen(m);
          } else {
            onSelect(m);
          }
        },
        onDoubleTap: () => onOpen(m),
        onLongPress: () {
          onSelect(m);
          if (m.isReady && !locked) unawaited(shareMedia(anchor, m));
        },
        child: builder(selected.contains(m.id)),
      ),
    );

    switch (view) {
      case ExplorerView.largeIcons:
        return GridView.builder(
          controller: controller,
          padding: const EdgeInsets.all(6),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 96,
            mainAxisExtent: 116,
            crossAxisSpacing: 4,
            mainAxisSpacing: 6,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) =>
              item(items[i], (sel) => _LargeIcon(item: items[i], selected: sel, locked: locked)),
        );
      case ExplorerView.smallIcons:
        return GridView.builder(
          controller: controller,
          padding: const EdgeInsets.all(4),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 150,
            mainAxisExtent: 22,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) => item(
            items[i],
            (sel) => Row(
              children: [
                ExplorerFileIcon(item: items[i], locked: locked),
                const SizedBox(width: 4),
                Flexible(
                  child: _Label(text: items[i].fileName, selected: sel, maxLines: 1),
                ),
              ],
            ),
          ),
        );
      case ExplorerView.details:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DetailsHeader(prefs: prefs, onSort: onSort),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: items.length,
                itemExtent: 22,
                itemBuilder: (context, i) {
                  final m = items[i];
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
                Text(prefs.ascending ? '▲' : '▼', style: const TextStyle(fontSize: 8)),
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
        style: W98.text.copyWith(color: selected ? Colors.white : Colors.black),
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
            color: Colors.white,
            padding: const EdgeInsets.all(3),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (item.isReady && thumb != null)
                  Image.file(
                    File(thumb),
                    fit: BoxFit.contain,
                    cacheWidth: 160,
                    filterQuality: FilterQuality.none,
                    errorBuilder: (_, _, _) =>
                        const Center(child: PixelIconView(PixelIcon.imageFile, size: 32)),
                  )
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
                        : W98.text.copyWith(color: selected ? Colors.white : Colors.black),
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
      color: Colors.white,
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
          node(1, PixelIcon.floppy, '3½ Floppy (A:)', dim: true),
          node(1, PixelIcon.hardDrive, 'Local Disk (C:)', onTap: () => onSelect(ExplorerPlace.c)),
          node(2, PixelIcon.folder, 'My Documents', onTap: () => onSelect(ExplorerPlace.c)),
          node(
            3,
            PixelIcon.folderOpen,
            'Darkroom',
            selected: place == ExplorerPlace.c,
            onTap: () => onSelect(ExplorerPlace.c),
          ),
          node(1, PixelIcon.removableDrive, 'SD Card (E:)', onTap: () => onSelect(ExplorerPlace.sd)),
          node(2, PixelIcon.folder, 'DCIM', onTap: () => onSelect(ExplorerPlace.sd)),
          node(
            3,
            PixelIcon.folderOpen,
            '100RETRO',
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
    required this.onOpenSd,
    required this.onOpenC,
    required this.onOpenFloppy,
  });

  final int sdBytes;
  final int cBytes;
  final int sdCount;
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
          drive(PixelIcon.floppy, '3½ Floppy (A:)', dim: true, onOpen: onOpenFloppy),
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
              color: Colors.white,
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
