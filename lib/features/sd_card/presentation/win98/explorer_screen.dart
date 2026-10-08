import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/audio/sfx.dart';

import '../../../../core/db/media_repository.dart';
import '../../../../core/providers.dart';
import '../../../viewer/presentation/media_actions.dart';
import '../../application/sd_card_controller.dart';
import '../../../onboarding/onboarding_screen.dart';
import 'debug_menu.dart';
import 'explorer_dialogs.dart';
import 'explorer_panes.dart';
import 'pixel_icons.dart';
import 'win98_viewer.dart';
import 'games/bricks.dart';
import 'games/minesweeper.dart';
import 'games/pinball.dart';
import 'games/solitaire.dart';
import 'win98_programs.dart';
import 'win98_shutdown.dart';
import 'win98_widgets.dart';
import '../../../../core/device/upright.dart';

/// Digital Mode's file manager, styled after the 9x Explorer.
///
///  * SD Card (E:) — where new shots land. Files here are *locked*: opening
///    one offers to move it to C:.
///  * Local Disk (C:) — files moved off the card (and into the phone's photo
///    library). These open in the viewer.
///  * My Computer — the drives.
class ExplorerScreen extends ConsumerStatefulWidget {
  const ExplorerScreen({super.key});

  /// The explorer arrives on its monitor: an off-white plastic set slides
  /// in from the right (the way the swipe went) and comes to rest against
  /// the left edge; however the explorer is closed, it slides back out.
  static PageRouteBuilder<void> slideIn() => PageRouteBuilder<void>(
    settings: UprightApp.landscape,
    transitionDuration: slideDuration,
    reverseTransitionDuration: const Duration(milliseconds: 460),
    pageBuilder: (context, _, _) => const ExplorerMonitor(child: ExplorerScreen()),
    transitionsBuilder: (context, a, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
        CurvedAnimation(parent: a, curve: const Cubic(0.3, 0.0, 0.5, 0.94), reverseCurve: Curves.easeInCubic),
      ),
      // The shadow it casts on the camera: a gradient strip, not a blur
      // (a full-screen blur cost slower phones a frame every frame).
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          const Positioned(
            left: -44,
            width: 44,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0x00000000), Color(0x66000000), Color(0xCC000000)],
                    stops: [0, 0.6, 1],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    ),
  );

  static const slideDuration = Duration(milliseconds: 820);

  @override
  ConsumerState<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends ConsumerState<ExplorerScreen> {
  final _sdScroll = ScrollController();
  final _cScroll = ScrollController();
  final _aScroll = ScrollController();
  final Set<String> _selected = {};
  ExplorerPlace? _place;

  /// Shut Down plays its own tune and switch-off, not the exit chime.
  bool _shutDown = false;

  @override
  void initState() {
    super.initState();
    for (final s in Sfx.windows98) {
      unawaited(s.preload());
    }
    Sfx.w98Login.play();
  }

  @override
  void dispose() {
    if (!_shutDown) Sfx.w98Exit.play();
    _sdScroll.dispose();
    _cScroll.dispose();
    _aScroll.dispose();
    super.dispose();
  }

  ExplorerPlace get _current {
    if (_place != null) return _place!;
    if (ref.read(sdCardFilesProvider).isNotEmpty) return ExplorerPlace.sd;
    if (ref.read(floppyFilesProvider).isNotEmpty) return ExplorerPlace.floppy;
    if (ref.read(cDriveFilesProvider).isNotEmpty) return ExplorerPlace.c;
    return ExplorerPlace.myComputer;
  }

  void _go(ExplorerPlace p) => setState(() {
    _place = p;
    _selected.clear();
  });

  Future<int?> _box(
    String title,
    String msg, {
    Win98MessageIcon icon = Win98MessageIcon.info,
    List<String> buttons = const ['OK'],
  }) => win98Box(context, title, msg, icon: icon, buttons: buttons);

  // ---- actions ---------------------------------------------------------------

  Future<void> _open(MediaItem item) async {
    if (item.status == MediaStatus.failed) {
      final r = await _box(
        item.fileName,
        'The file is corrupt and cannot be opened.\n\n${item.error ?? 'Unknown error'}\n\nDelete it?',
        icon: Win98MessageIcon.error,
        buttons: const ['Delete', 'Keep', 'Copy'],
      );
      if (r == 0) await deleteMedia(ref.read(sdCardRepositoryProvider), item);
      if (r == 2) await Clipboard.setData(ClipboardData(text: errorReport(item)));
      return;
    }
    if (!item.isReady) {
      await _box(
        item.fileName,
        'This file is still being written to the card.\n\nPlease wait a moment.',
        icon: Win98MessageIcon.warning,
      );
      return;
    }
    if (item.onSdCard && ref.read(floppyFilesProvider).any((m) => m.id == item.id)) {
      final r = await _box(
        '3½ Floppy (A:)',
        "'${item.fileName}' was captured from tape onto ${floppiesFor(item.bytes)} floppy disk(s).\n\n"
            "Copy it to Local Disk (C:) to play it? It will also be copied to your phone's photo library.",
        icon: Win98MessageIcon.question,
        buttons: const ['Copy', 'Cancel'],
      );
      if (r != 0 || !await _copyFromFloppy([item]) || !mounted) return;
      _go(ExplorerPlace.c);
      final list = ref.read(explorerItemsProvider(Drive.c));
      final i = list.indexWhere((m) => m.id == item.id);
      if (i >= 0) await _view(list, i);
      return;
    }
    if (item.onSdCard) {
      final others = ref.read(sdCardFilesProvider).where((m) => m.isReady).length;
      final r = await _box(
        'SD Card (E:)',
        "'${item.fileName}' is on the SD card.\n\nMove it to Local Disk (C:) to open it? "
            "It will also be copied to your phone's photo library.",
        icon: Win98MessageIcon.question,
        buttons: [if (others > 1) 'Move All', 'Move', 'Cancel'],
      );
      final moveAll = others > 1 && r == 0;
      final moveOne = r == (others > 1 ? 1 : 0);
      if (!moveAll && !moveOne) return;
      final ok = await _transfer(ids: moveAll ? null : [item.id], quiet: true);
      if (!ok || !mounted) return;
      _go(ExplorerPlace.c);
      final list = ref.read(explorerItemsProvider(Drive.c));
      final i = list.indexWhere((m) => m.id == item.id);
      if (i >= 0) await _view(list, i);
      return;
    }
    final list = ref.read(explorerItemsProvider(Drive.c));
    final i = list.indexWhere((m) => m.id == item.id);
    await _view(list, i < 0 ? 0 : i);
  }

  Future<void> _view(List<MediaItem> items, int index) => Navigator.of(context).push(
    PageRouteBuilder<void>(
      settings: UprightApp.landscape,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, _, _) => Win98ViewerScreen(items: items, initialIndex: index),
      transitionsBuilder: (context, a, _, child) => Win98ZoomTransition(animation: a, child: child),
    ),
  );

  /// Camcorder clips: swap through the floppies, then move them to C:.
  Future<bool> _copyFromFloppy(List<MediaItem> items) async {
    final ready = items.where((m) => m.isReady && m.onSdCard).toList();
    if (ready.isEmpty) return false;
    final disks = ready.fold<int>(0, (s, m) => s + floppiesFor(m.bytes));
    final label = ready.length == 1 ? ready.first.fileName : '${ready.length} clips';
    if (!await showFloppySpan(context, disks: disks, label: label)) {
      if (mounted) {
        await _box(
          '3½ Floppy (A:)',
          'Copy cancelled. The clips are still on the floppies.',
          icon: Win98MessageIcon.warning,
        );
      }
      return false;
    }
    if (!mounted) return false;
    return _transfer(ids: [for (final m in ready) m.id], fromFloppy: true);
  }

  /// Moves files from the card to C: ([ids] null = everything ready on the
  /// card). Returns true if at least the requested files made it.
  Future<bool> _transfer({List<String>? ids, bool quiet = false, bool fromFloppy = false}) async {
    final sd = fromFloppy ? ref.read(floppyFilesProvider) : ref.read(sdCardFilesProvider);
    if (sd.isEmpty) return false;
    if (ids == null && sd.any((m) => m.status == MediaStatus.processing)) {
      final r = await _box(
        'SD Card (E:)',
        'Some files are still being written. They will stay on the card.\n\nMove the finished files now?',
        icon: Win98MessageIcon.question,
        buttons: const ['Yes', 'No'],
      );
      if (r != 0) return false;
    }
    // Only this drive's files (the floppies have their own copy routine).
    ids ??= [
      for (final m in sd)
        if (m.isReady) m.id,
    ];
    if (!mounted) return false;
    final notifier = ref.read(sdTransferProvider.notifier);
    final dialog = showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black12,
      transitionDuration: const Duration(milliseconds: 120),
      transitionBuilder: (context, a, _, child) => Win98ZoomTransition(animation: a, child: child),
      pageBuilder: (_, _, _) => Win98Scale(child: CopyingDialog(fromFloppy: fromFloppy)),
    );
    final outcome = await notifier.moveToC(ids: ids);
    if (mounted) Navigator.of(context).pop();
    await dialog;
    final t = ref.read(sdTransferProvider);
    notifier.reset();
    setState(_selected.clear);
    if (!mounted) return false;
    switch (outcome) {
      case TransferOutcome.done:
        if (!quiet) {
          await _box(
            'Transfer Complete',
            "${t?.total ?? 0} file(s) moved to C:\\My Documents\\Darkroom and copied to your photo library "
                "(album 'Darkroom').",
          );
        }
        return true;
      case TransferOutcome.partial:
        await _box(
          'Error Moving File',
          'Cannot move ${t!.failures.join(', ')}: Access is denied.\n\nThe other files were moved.',
          icon: Win98MessageIcon.error,
        );
        return false;
      case TransferOutcome.accessDenied:
        await _box(
          'SD Card (E:)',
          'Access is denied.\n\nAllow photo library access in Settings to move your files.',
          icon: Win98MessageIcon.error,
        );
        return false;
      case TransferOutcome.cancelled:
        await _box(
          'SD Card (E:)',
          'The operation was cancelled. Remaining files are still on the card.',
          icon: Win98MessageIcon.warning,
        );
        return false;
      case TransferOutcome.nothingToDo:
        return false;
    }
  }

  List<MediaItem> _selectedItems() {
    final all = [
      ...ref.read(sdCardFilesProvider),
      ...ref.read(floppyFilesProvider),
      ...ref.read(cDriveFilesProvider),
    ];
    return all.where((m) => _selected.contains(m.id)).toList();
  }

  Future<void> _deleteSelected() async {
    final items = _selectedItems();
    if (items.isEmpty) return;
    final onC = items.any((m) => !m.onSdCard);
    final what = items.length == 1 ? "'${items.first.fileName}'" : 'these ${items.length} items';
    final r = await _box(
      'Confirm File Delete',
      'Are you sure you want to delete $what?'
          '${onC ? "\n\nCopies already in your phone's photo library are not affected." : ''}',
      icon: Win98MessageIcon.question,
      buttons: const ['Yes', 'No'],
    );
    if (r != 0) return;
    final repo = ref.read(sdCardRepositoryProvider);
    for (final m in items) {
      await deleteMedia(repo, m);
    }
    setState(_selected.clear);
  }

  Future<void> _formatCard() async {
    final sd = ref.read(sdCardFilesProvider).where((m) => m.status != MediaStatus.processing).toList();
    if (sd.isEmpty) {
      await _box('Format SD Card (E:)', 'The card is already empty.');
      return;
    }
    final r = await _box(
      'Format SD Card (E:)',
      'WARNING: Formatting will ERASE ALL ${sd.length} file(s) on the SD card that have not been moved to C:.\n\n'
          'To format the card, click OK. To quit, click Cancel.',
      icon: Win98MessageIcon.warning,
      buttons: const ['OK', 'Cancel'],
    );
    if (r != 0) return;
    final repo = ref.read(sdCardRepositoryProvider);
    for (final m in sd) {
      await deleteMedia(repo, m);
    }
    if (mounted) {
      await _box(
        'Format Results',
        'Format complete.\n\n134,217,728 bytes total disk space\n134,217,728 bytes available on disk',
      );
    }
  }

  Future<void> _start() async {
    final a = await showStartMenu(context);
    if (!mounted || a == null) return;
    switch (a) {
      case StartAction.camera:
        Navigator.of(context).pop();
      case StartAction.documents:
        _go(ExplorerPlace.c);
      case StartAction.options:
        await showExplorerOptions(context);
      case StartAction.help:
        await showTipOfTheDay(context);
      case StartAction.run:
        await _run();
      case StartAction.profile:
        await showUserProfile(context);
      case StartAction.shutDown:
        _shutDown = true;
        await showShutDownSequence(context);
        if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _run() async {
    final typed = (await showRunDialog(context))?.trim();
    if (!mounted || typed == null || typed.isEmpty) return;
    final cmd = typed.toLowerCase();
    // RABBIT, rabbit.exe and c:\rabbit.exe all run the same program.
    final name = cmd.split(RegExp(r'[\\/]')).last.replaceFirst(RegExp(r'\.(exe|bat|com|txt)$'), '');
    switch (name) {
      case 'rabbit' || 'bunny':
        return showRabbitExe(context);
      case 'develop':
        return showDosPrompt(context, command: 'DEVELOP', lines: developLines);
      case 'ping':
        return showDosPrompt(context, command: 'PING CORKBOARD', lines: pingLines);
      case 'readme' || 'notepad':
        return showNotepad(context, file: 'README.TXT', text: readmeText);
      case 'sol' || 'solitaire':
        return showSolitaire(context);
      case 'bricks' || 'breakout' || 'brickbreaker':
        return showBricks(context);
      case 'pinball' || 'spacecadet' || 'space cadet' || 'spacerabbit':
        return showPinball(context);
      case 'mines' || 'minefield' || 'minesweeper' || 'winmine':
        return showMinesweeper(context);
    }
    if (!mounted) return;
    switch (cmd) {
      case 'defrag' || 'defrag.exe':
        await showDefragmenter(context, files: ref.read(sdCardFilesProvider).length);
      case 'winver' || 'about':
        await showAboutDarkroom(context);
      case 'c:' || 'c:\\' || 'explorer':
        _go(ExplorerPlace.c);
      case 'e:' || 'e:\\':
        _go(ExplorerPlace.sd);
      case 'a:' || 'a:\\':
        _go(ExplorerPlace.floppy);
      case 'camera' || 'darkroom':
        Navigator.of(context).pop();
      case 'format c:':
        await _box('Format', 'Nice try.', icon: Win98MessageIcon.warning);
      default:
        await _box(
          cmd,
          "Cannot find the file '$typed' (or one of its components). Make sure the path and filename are "
          'correct. (Stuck? Try README.)',
          icon: Win98MessageIcon.error,
        );
    }
  }

  // ---- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final sdFiles = ref.watch(sdCardFilesProvider);
    final floppyFiles = ref.watch(floppyFilesProvider);
    final cFiles = ref.watch(cDriveFilesProvider);
    final place = _current;
    final drive = switch (place) {
      ExplorerPlace.sd => Drive.sd,
      ExplorerPlace.floppy => Drive.floppy,
      ExplorerPlace.c || ExplorerPlace.myComputer => Drive.c,
    };
    final onFloppy = place == ExplorerPlace.floppy;
    final visible = place == ExplorerPlace.myComputer
        ? const <MediaItem>[]
        : ref.watch(explorerItemsProvider(drive));
    final floppyBytes = floppyFiles.fold<int>(0, (s, m) => s + (m.bytes ?? 0));
    final readyOnFloppy = floppyFiles.where((m) => m.isReady).length;
    final prefs = ref.watch(explorerPrefsProvider);
    final prefsN = ref.read(explorerPrefsProvider.notifier);
    final sdBytes = sdFiles.fold<int>(0, (s, m) => s + (m.bytes ?? 0));
    final cBytes = cFiles.fold<int>(0, (s, m) => s + (m.bytes ?? 0));
    final readyOnSd = sdFiles.where((m) => m.isReady).length;
    // The big Transfer button, toolbar and File menu act on the open drive.
    final readyHere = onFloppy ? readyOnFloppy : readyOnSd;
    Future<bool> transferAll() => onFloppy ? _copyFromFloppy(floppyFiles) : _transfer();
    _selected.removeWhere((id) => !visible.any((m) => m.id == id));
    final selectedBytes = visible
        .where((m) => _selected.contains(m.id))
        .fold<int>(0, (s, m) => s + (m.bytes ?? 0));
    final selectedSdReady = visible
        .where((m) => _selected.contains(m.id) && m.onSdCard && m.isReady)
        .map((m) => m.id)
        .toList();
    Future<bool> moveSelected() => onFloppy
        ? _copyFromFloppy(visible.where((m) => selectedSdReady.contains(m.id)).toList())
        : _transfer(ids: selectedSdReady);

    final (title, pathIcon, path) = switch (place) {
      ExplorerPlace.sd => ('Exploring - SD Card (E:)', PixelIcon.removableDrive, r'E:\DCIM\100DRKRM'),
      ExplorerPlace.floppy => ('Exploring - 3½ Floppy (A:)', PixelIcon.floppy, r'A:\TAPE01'),
      ExplorerPlace.c => ('Exploring - Local Disk (C:)', PixelIcon.hardDrive, r'C:\My Documents\Darkroom'),
      ExplorerPlace.myComputer => ('My Computer', PixelIcon.computer, 'My Computer'),
    };

    final land = MediaQuery.sizeOf(context).aspectRatio > 1;
    return Win98Scale(
      child: Scaffold(
        backgroundColor: W98.desktop,
        body: DefaultTextStyle(
          style: W98.text,
          child: Win98Safe(
            covered: ExplorerMonitor.bezelOf(context),
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                    child: Win98Window(
                      title: title,
                      icon: PixelIconView(pathIcon),
                      onClose: () => Navigator.of(context).pop(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Win98MenuBar(
                            menus: {
                              'File': () => [
                                Win98MenuItem(
                                  'Open',
                                  onSelected: _selected.length == 1
                                      ? () => _open(visible.firstWhere((m) => m.id == _selected.first))
                                      : null,
                                ),
                                Win98MenuItem(
                                  'Move to C:',
                                  onSelected: selectedSdReady.isEmpty ? null : moveSelected,
                                ),
                                Win98MenuItem(
                                  'Transfer All to C:',
                                  onSelected: readyHere == 0 ? null : transferAll,
                                ),
                                Win98MenuItem(
                                  'Delete',
                                  onSelected: _selected.isEmpty ? null : _deleteSelected,
                                ),
                                const Win98MenuItem.separator(),
                                Win98MenuItem(
                                  'Properties',
                                  onSelected: place == ExplorerPlace.myComputer
                                      ? null
                                      : () => showDriveProperties(
                                          context,
                                          label: switch (place) {
                                            ExplorerPlace.sd => 'SD Card (E:)',
                                            ExplorerPlace.floppy => '3½ Floppy (A:)',
                                            _ => 'Local Disk (C:)',
                                          },
                                          used: switch (place) {
                                            ExplorerPlace.sd => sdBytes,
                                            ExplorerPlace.floppy => floppyBytes,
                                            _ => cBytes,
                                          },
                                          capacity: switch (place) {
                                            ExplorerPlace.sd => sdCardCapacityBytes,
                                            // Spanned: as many disks as it takes.
                                            ExplorerPlace.floppy =>
                                              floppyCapacityBytes *
                                                  floppyFiles.fold<int>(
                                                    0,
                                                    (s, m) => s + floppiesFor(m.bytes),
                                                  ),
                                            _ => 0,
                                          },
                                        ),
                                ),
                                const Win98MenuItem.separator(),
                                Win98MenuItem('Close', onSelected: () => Navigator.of(context).pop()),
                              ],
                              'Edit': () => [
                                Win98MenuItem(
                                  'Select All',
                                  onSelected: visible.isEmpty
                                      ? null
                                      : () => setState(() => _selected.addAll(visible.map((m) => m.id))),
                                ),
                                Win98MenuItem(
                                  'Invert Selection',
                                  onSelected: visible.isEmpty
                                      ? null
                                      : () => setState(() {
                                          for (final m in visible) {
                                            if (!_selected.remove(m.id)) _selected.add(m.id);
                                          }
                                        }),
                                ),
                              ],
                              'View': () => [
                                for (final v in ExplorerView.values)
                                  Win98MenuItem(
                                    _viewLabel(v),
                                    radio: true,
                                    checked: prefs.view == v,
                                    onSelected: () => prefsN.setView(v),
                                  ),
                                const Win98MenuItem.separator(),
                                for (final s in ExplorerSort.values)
                                  Win98MenuItem(
                                    'Arrange by ${_sortLabel(s)}',
                                    radio: true,
                                    checked: prefs.sort == s,
                                    onSelected: () => prefsN.sortBy(s),
                                  ),
                                const Win98MenuItem.separator(),
                                for (final f in ExplorerFilter.values)
                                  Win98MenuItem(
                                    _filterLabel(f),
                                    radio: true,
                                    checked: prefs.filter == f,
                                    onSelected: () => prefsN.setFilter(f),
                                  ),
                                const Win98MenuItem.separator(),
                                Win98MenuItem(
                                  'Folders',
                                  checked: prefs.showTree,
                                  onSelected: prefsN.toggleTree,
                                ),
                                Win98MenuItem('Options...', onSelected: () => showExplorerOptions(context)),
                              ],
                              'Tools': () => [
                                Win98MenuItem(
                                  'Defragment SD Card...',
                                  onSelected: () => showDefragmenter(context, files: sdFiles.length),
                                ),
                                Win98MenuItem('Format SD Card...', onSelected: _formatCard),
                                const Win98MenuItem.separator(),
                                Win98MenuItem('Run...', onSelected: _run),
                              ],
                              'Help': () => [
                                Win98MenuItem(
                                  'Tip of the Day...',
                                  onSelected: () => showTipOfTheDay(context),
                                ),
                                Win98MenuItem(
                                  'Welcome Tour...',
                                  onSelected: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (context) =>
                                          OnboardingScreen(onDone: () => Navigator.of(context).pop()),
                                    ),
                                  ),
                                ),
                                Win98MenuItem(
                                  'How Do I...',
                                  onSelected: () => _box(
                                    'Darkroom Help',
                                    'New pictures are saved to the SD Card (E:).\n\n'
                                        'Files on the card are locked: open one, or press Transfer, to move it to '
                                        "Local Disk (C:). Moving also copies it to your phone's photo library.\n\n"
                                        'On C:, tap a file twice to open it, hold it to send it, and use the arrows in '
                                        'the viewer to flip through your pictures.',
                                  ),
                                ),
                                Win98MenuItem('Debug...', onSelected: () => showDebugMenu(context)),
                                const Win98MenuItem.separator(),
                                Win98MenuItem('About Darkroom', onSelected: () => showAboutDarkroom(context)),
                              ],
                            },
                          ),
                          _Toolbar(
                            canMove: selectedSdReady.isNotEmpty,
                            canDelete: _selected.isNotEmpty,
                            canTransfer: readyHere > 0,
                            onUp: () => _go(ExplorerPlace.myComputer),
                            onMove: moveSelected,
                            onTransfer: transferAll,
                            onDelete: _deleteSelected,
                            onFolders: prefsN.toggleTree,
                            foldersOn: prefs.showTree,
                          ),
                          ExplorerAddressBar(path: path, icon: pathIcon),
                          const SizedBox(height: 4),
                          Win98TabStrip(
                            tabs: [
                              const Win98Tab('SD Card (E:)', icon: PixelIconView(PixelIcon.removableDrive)),
                              const Win98Tab('A:', icon: PixelIconView(PixelIcon.floppy)),
                              const Win98Tab('C:', icon: PixelIconView(PixelIcon.hardDrive)),
                              const Win98Tab('My Computer', icon: PixelIconView(PixelIcon.computer)),
                            ],
                            selected: place.index,
                            onSelect: (i) => _go(ExplorerPlace.values[i]),
                          ),
                          Expanded(
                            child: Win98Bevel(
                              style: BevelStyle.window,
                              padding: const EdgeInsets.all(4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (prefs.showTree) ...[
                                    SizedBox(
                                      width: 132,
                                      child: ExplorerFolderTree(place: place, onSelect: _go),
                                    ),
                                    const SizedBox(width: 3),
                                  ],
                                  Expanded(
                                    child: Win98Bevel(
                                      style: BevelStyle.sunken,
                                      color: Colors.white,
                                      padding: const EdgeInsets.all(2),
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 120),
                                        child: KeyedSubtree(
                                          key: ValueKey(place),
                                          child: place == ExplorerPlace.myComputer
                                              ? ExplorerMyComputerPane(
                                                  sdBytes: sdBytes,
                                                  cBytes: cBytes,
                                                  sdCount: sdFiles.length,
                                                  floppyCount: floppyFiles.length,
                                                  onOpenSd: () => _go(ExplorerPlace.sd),
                                                  onOpenC: () => _go(ExplorerPlace.c),
                                                  onOpenFloppy: () => _go(ExplorerPlace.floppy),
                                                )
                                              : Win98Scrollbar(
                                                  controller: switch (place) {
                                                    ExplorerPlace.sd => _sdScroll,
                                                    ExplorerPlace.floppy => _aScroll,
                                                    _ => _cScroll,
                                                  },
                                                  child: ExplorerFilePane(
                                                    items: visible,
                                                    view: prefs.view,
                                                    prefs: prefs,
                                                    controller: switch (place) {
                                                      ExplorerPlace.sd => _sdScroll,
                                                      ExplorerPlace.floppy => _aScroll,
                                                      _ => _cScroll,
                                                    },
                                                    selected: _selected,
                                                    locked: place == ExplorerPlace.sd || onFloppy,
                                                    emptyText: onFloppy
                                                        ? 'There are no files on the floppy disk.'
                                                        : null,
                                                    onSelect: (m) => setState(() {
                                                      _selected
                                                        ..clear()
                                                        ..add(m.id);
                                                    }),
                                                    onOpen: _open,
                                                    onClearSelection: () => setState(_selected.clear),
                                                    onSort: prefsN.sortBy,
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Landscape is short: the toolbar's Transfer does the job.
                          if (!land) const SizedBox(height: 4),
                          if (!land)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: SizedBox(
                                height: 30,
                                child: Win98Button(
                                  onPressed: readyHere == 0 ? null : transferAll,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      PixelIconView(onFloppy ? PixelIcon.floppy : PixelIcon.transfer),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          onFloppy
                                              ? (readyHere == 0
                                                    ? 'No Disk in Drive A:'
                                                    : 'Copy $readyHere Clip(s) to Local Disk (C:)')
                                              : (readyHere == 0
                                                    ? 'SD Card Empty'
                                                    : 'Transfer $readyHere File(s) to Local Disk (C:)'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 3),
                          ExplorerStatusBar(
                            cells: [
                              _selected.isEmpty
                                  ? '${place == ExplorerPlace.myComputer ? 3 : visible.length} object(s)'
                                  : '${_selected.length} object(s) selected',
                              formatBytes(
                                _selected.isEmpty
                                    ? switch (place) {
                                        ExplorerPlace.c => cBytes,
                                        ExplorerPlace.floppy => floppyBytes,
                                        _ => sdBytes,
                                      }
                                    : selectedBytes,
                              ),
                              switch (place) {
                                ExplorerPlace.sd => 'SD Card',
                                ExplorerPlace.floppy => '3½ Floppy',
                                ExplorerPlace.c => 'Local Disk',
                                ExplorerPlace.myComputer => 'My Computer',
                              },
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _Taskbar(
                  title: title,
                  icon: pathIcon,
                  onStart: _start,
                  onClockHold: () => showBlueScreen(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _viewLabel(ExplorerView v) => switch (v) {
    ExplorerView.largeIcons => 'Large Icons',
    ExplorerView.smallIcons => 'Small Icons',
    ExplorerView.details => 'Details',
  };

  static String _sortLabel(ExplorerSort s) => switch (s) {
    ExplorerSort.name => 'Name',
    ExplorerSort.date => 'Date',
    ExplorerSort.size => 'Size',
  };

  static String _filterLabel(ExplorerFilter f) => switch (f) {
    ExplorerFilter.all => 'Show All Files',
    ExplorerFilter.photos => 'Show Pictures Only',
    ExplorerFilter.videos => 'Show Movies Only',
  };
}

class _Toolbar extends ConsumerWidget {
  const _Toolbar({
    required this.canMove,
    required this.canDelete,
    required this.canTransfer,
    required this.onUp,
    required this.onMove,
    required this.onTransfer,
    required this.onDelete,
    required this.onFolders,
    required this.foldersOn,
  });

  final bool canMove;
  final bool canDelete;
  final bool canTransfer;
  final VoidCallback onUp;
  final VoidCallback onMove;
  final VoidCallback onTransfer;
  final VoidCallback onDelete;
  final VoidCallback onFolders;
  final bool foldersOn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(explorerPrefsProvider);
    final n = ref.read(explorerPrefsProvider.notifier);
    Widget tool(PixelIcon icon, String label, VoidCallback? onTap, {bool toggled = false}) => Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Win98Button(
        onPressed: onTap,
        toggled: toggled,
        minWidth: 44,
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PixelIconView(icon, size: 22),
            Text(label, style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: W98.white),
          bottom: BorderSide(color: W98.shadow),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            tool(PixelIcon.upFolder, 'Up', onUp),
            tool(PixelIcon.folderOpen, 'Folders', onFolders, toggled: foldersOn),
            Builder(
              builder: (anchor) => tool(PixelIcon.views, 'Views', () {
                unawaited(
                  showWin98Menu(anchor, [
                    for (final v in ExplorerView.values)
                      Win98MenuItem(
                        _ExplorerScreenState._viewLabel(v),
                        radio: true,
                        checked: prefs.view == v,
                        onSelected: () => n.setView(v),
                      ),
                  ]),
                );
              }),
            ),
            Builder(
              builder: (anchor) => tool(PixelIcon.imageFile, 'Show', () {
                unawaited(
                  showWin98Menu(anchor, [
                    for (final f in ExplorerFilter.values)
                      Win98MenuItem(
                        _ExplorerScreenState._filterLabel(f),
                        radio: true,
                        checked: prefs.filter == f,
                        onSelected: () => n.setFilter(f),
                      ),
                  ]),
                );
              }),
            ),
            tool(PixelIcon.hardDrive, 'Move to C:', canMove ? onMove : null),
            tool(PixelIcon.delete, 'Delete', canDelete ? onDelete : null),
            tool(PixelIcon.transfer, 'Transfer', canTransfer ? onTransfer : null),
          ],
        ),
      ),
    );
  }
}

class _Taskbar extends StatefulWidget {
  const _Taskbar({required this.title, required this.icon, required this.onStart, required this.onClockHold});

  final String title;
  final PixelIcon icon;
  final VoidCallback onStart;
  final VoidCallback onClockHold;

  @override
  State<_Taskbar> createState() => _TaskbarState();
}

class _TaskbarState extends State<_Taskbar> {
  late final Timer _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 20), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = TimeOfDay.now();
    final h = now.hourOfPeriod == 0 ? 12 : now.hourOfPeriod;
    final time = '$h:${now.minute.toString().padLeft(2, '0')} ${now.period == DayPeriod.am ? 'AM' : 'PM'}';
    return Win98Bevel(
      padding: const EdgeInsets.fromLTRB(2, 3, 2, 2),
      child: SizedBox(
        height: 26,
        child: Row(
          children: [
            Win98Button(
              onPressed: widget.onStart,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  const PixelIconView(PixelIcon.rabbit),
                  const SizedBox(width: 3),
                  Text('Start', style: W98.text.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Win98Button(
                  toggled: true,
                  onPressed: () {},
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PixelIconView(widget.icon),
                      const SizedBox(width: 4),
                      Flexible(child: Text(widget.title, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              ),
            ),
            GestureDetector(
              onLongPress: widget.onClockHold,
              child: Win98Bevel(
                style: BevelStyle.shallow,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(time),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The beige monitor round the explorer: a moulded plastic bezel with a
/// recessed, slightly shadowed screen, a maker's badge and a green power
/// lamp on the chin.
class ExplorerMonitor extends StatelessWidget {
  const ExplorerMonitor({super.key, required this.child});

  static const bezel = 16.0;

  /// Thinner turned to landscape, where height is short.
  static double bezelOf(BuildContext context) => MediaQuery.sizeOf(context).aspectRatio > 1 ? 8 : bezel;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bezel = bezelOf(context);
    return ColoredBox(
      color: const Color(0xFFD9D3C3),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: EdgeInsets.all(bezel),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: RepaintBoundary(child: child),
            ),
          ),
          IgnorePointer(
            child: RepaintBoundary(child: CustomPaint(painter: _BezelPainter(bezel))),
          ),
        ],
      ),
    );
  }
}

class _BezelPainter extends CustomPainter {
  const _BezelPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Offset.zero & size;
    final screen = RRect.fromRectAndRadius(outer.deflate(t), const Radius.circular(6));
    // The plastic: lit from above, a touch darker toward the bottom, with
    // a faint moulding texture.
    final frame = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(outer)
      ..addRRect(screen);
    canvas.drawPath(
      frame,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEEE9DC), Color(0xFFDCD5C4), Color(0xFFC9C1AE)],
          stops: [0, 0.5, 1],
        ).createShader(outer),
    );
    // Rounded outer edge catching the light (left/top) and in shade (right/bottom).
    canvas.drawRect(
      outer.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFBF8EF), Color(0xFFA79F8B)],
        ).createShader(outer),
    );
    // The screen sits in a recess: a dark lip, a shadow cast inward.
    canvas.drawRRect(
      screen.inflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8E8674), Color(0xFFF4F0E4)],
        ).createShader(outer),
    );
    canvas.save();
    canvas.clipRRect(screen);
    // The recess's inner shadow: gradients along each edge (no blur pass).
    const depth = 9.0, shade = Color(0x4D000000), clear = Color(0x00000000);
    final r = screen.outerRect;
    for (final (rect, begin, end) in [
      (Rect.fromLTWH(r.left, r.top, r.width, depth), Alignment.topCenter, Alignment.bottomCenter),
      (Rect.fromLTWH(r.left, r.bottom - depth, r.width, depth), Alignment.bottomCenter, Alignment.topCenter),
      (Rect.fromLTWH(r.left, r.top, depth, r.height), Alignment.centerLeft, Alignment.centerRight),
      (Rect.fromLTWH(r.right - depth, r.top, depth, r.height), Alignment.centerRight, Alignment.centerLeft),
    ]) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(begin: begin, end: end, colors: const [shade, clear]).createShader(rect),
      );
    }
    // A whisper of glass glare across the top-left.
    canvas.drawRect(
      screen.outerRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: const Alignment(0.2, 0.1),
          colors: [Colors.white.withValues(alpha: 0.07), Colors.white.withValues(alpha: 0)],
        ).createShader(screen.outerRect),
    );
    canvas.restore();
    // Power lamp on the chin (right) and the maker's badge (left).
    final y = size.height - t / 2;
    final lamp = Offset(size.width - t * 2.2, y);
    canvas.drawCircle(lamp, 3.2, Paint()..color = const Color(0xFF3C6E3C));
    canvas.drawCircle(lamp, 2.4, Paint()..color = const Color(0xFF7CFF6B));
    canvas.drawCircle(
      lamp,
      7,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x667CFF6B), Color(0x007CFF6B)],
        ).createShader(Rect.fromCircle(center: lamp, radius: 7)),
    );
    final badge = TextPainter(
      text: const TextSpan(
        text: 'DARKROOM',
        style: TextStyle(
          color: Color(0xFF9C9480),
          fontSize: 7.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    badge.paint(canvas, Offset(t * 1.6, y - badge.height / 2));
  }

  @override
  bool shouldRepaint(_BezelPainter old) => old.t != t;
}
