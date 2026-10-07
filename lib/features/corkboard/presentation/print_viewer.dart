import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/media_repository.dart';
import '../../../core/providers.dart';
import '../../cameras/domain/camera_catalog.dart';
import '../../viewer/presentation/media_actions.dart';
import '../../viewer/presentation/zoomable.dart';
import '../../../core/processing/instant_frame.dart';
import 'instant_print.dart';
import '../../../core/device/haptics.dart';

/// Inspecting prints on a dark light-table: swipe between them, pinch to
/// look closer, Save copies one to the phone's photo library.
class PrintViewerScreen extends ConsumerStatefulWidget {
  const PrintViewerScreen({super.key, required this.items, required this.initialIndex});

  final List<MediaItem> items;
  final int initialIndex;

  /// Held up in front of the corkboard: the board stays behind, dimmed.
  static Route<void> route(List<MediaItem> items, int index) => PageRouteBuilder<void>(
    opaque: false,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, _, _) => PrintViewerScreen(items: items, initialIndex: index < 0 ? 0 : index),
    transitionsBuilder: (context, a, _, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(
        scale: Tween(begin: 0.96, end: 1.0).chain(CurveTween(curve: Curves.easeOutCubic)).animate(a),
        child: child,
      ),
    ),
  );

  @override
  ConsumerState<PrintViewerScreen> createState() => _PrintViewerScreenState();
}

class _PrintViewerScreenState extends ConsumerState<PrintViewerScreen> {
  late final List<String> _ids = widget.items.map((m) => m.id).toList();
  late int _index = widget.initialIndex.clamp(0, _ids.length - 1);
  late final PageController _pages = PageController(initialPage: _index);
  bool _saving = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _save(MediaItem item) async {
    if (_saving || item.isSaved) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final err = await keepMedia(ref.read(filmRepositoryProvider), item, album: filmAlbum);
    if (!mounted) return;
    setState(() => _saving = false);
    unawaited(Haptics.lightImpact());
    messenger.showSnackBar(SnackBar(content: Text(err ?? 'Saved to your photo library ($filmAlbum).')));
  }

  /// Instant prints: write (or change) the note on the bottom border.
  Future<void> _writeNote(MediaItem item) async {
    final text = TextEditingController(text: item.note ?? '');
    // The box is the print's own off-white paper with felt-tip ink, so the
    // writing reads the same in light and dark mode.
    const paper = InstantFrame.paper, ink = InstantFrame.ink;
    final note = await showDialog<String>(
      context: context,
      builder: (context) => Theme(
        data: ThemeData.light(useMaterial3: true).copyWith(
          colorScheme: const ColorScheme.light(
            primary: ink,
            onPrimary: paper,
            surface: paper,
            onSurface: ink,
          ),
          textSelectionTheme: TextSelectionThemeData(
            cursorColor: ink,
            selectionColor: ink.withValues(alpha: 0.2),
            selectionHandleColor: ink,
          ),
        ),
        child: AlertDialog(
          backgroundColor: paper,
          title: const Text('Write on the print', style: TextStyle(color: ink)),
          content: TextField(
            controller: text,
            autofocus: true,
            maxLength: InstantFrame.maxNoteLength,
            textCapitalization: TextCapitalization.sentences,
            style: InstantFrame.noteStyle(260).copyWith(fontSize: 26),
            decoration: InputDecoration(
              hintText: 'summer \'26, the lake…',
              hintStyle: InstantFrame.noteStyle(
                260,
              ).copyWith(fontSize: 26, color: ink.withValues(alpha: 0.3)),
              counterStyle: TextStyle(color: ink.withValues(alpha: 0.6)),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ink.withValues(alpha: 0.4))),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: ink, width: 1.6)),
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, text.text), child: const Text('Done')),
          ],
        ),
      ),
    );
    text.dispose();
    if (note == null || !mounted) return;
    final repo = ref.read(filmRepositoryProvider);
    if (note == (item.note ?? '')) return;
    await repo.setNote(item.id, note);
    // Already in the photo library: that copy can't be changed, so offer a
    // new one with the note on it.
    if (!item.isSaved || !mounted) return;
    final again = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save a copy with the note?'),
        content: const Text(
          'This print is already in your photo library without it. A new copy is added; the old one stays.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save copy')),
        ],
      ),
    );
    if (again != true || !mounted) return;
    final fresh = await repo.byId(item.id);
    if (fresh == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final err = await saveToGallery(fresh, album: filmAlbum);
    if (!mounted) return;
    unawaited(Haptics.lightImpact());
    messenger.showSnackBar(SnackBar(content: Text(err ?? 'Saved a copy with the note ($filmAlbum).')));
  }

  Future<void> _delete(MediaItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Throw this print away?'),
        content: Text(
          item.isSaved
              ? "It will be removed from the corkboard. The copy in your photo library stays."
              : 'It has not been saved to your photo library. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Throw away')),
        ],
      ),
    );
    if (ok != true) return;
    await deleteMedia(ref.read(filmRepositoryProvider), item);
    if (!mounted) return;
    setState(() {
      _ids.remove(item.id);
      if (_index >= _ids.length) _index = _ids.length - 1;
    });
    if (_ids.isEmpty) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Live rows (saved state changes while we look).
    final live = {for (final m in ref.watch(filmItemsProvider).value ?? widget.items) m.id: m};
    final items = [for (final id in _ids) live[id] ?? widget.items.firstWhere((m) => m.id == id)];
    if (items.isEmpty) return const SizedBox.shrink();
    final item = items[_index];
    final spec = CameraCatalog.byId(item.cameraId);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // The corkboard behind, dimmed (a little more towards the edges).
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(radius: 0.9, colors: [Color(0xB3100D0B), Color(0xE6100D0B)]),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white70),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.fileName,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                            Text(
                              '${spec.name} · ${MaterialLocalizations.of(context).formatMediumDate(item.capturedAt)}',
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Text('${_index + 1} / ${items.length}', style: const TextStyle(color: Colors.white54)),
                    ],
                  ),
                ),
                Expanded(
                  child: ZoomPageView(
                    controller: _pages,
                    itemCount: items.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i, onZoom) => _Print(
                      item: items[i],
                      onZoomChanged: onZoom,
                      onWrite: () => _writeNote(items[i]),
                      onDismiss: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ),
                _ActionBar(
                  onWrite: spec.isInstant ? () => _writeNote(item) : null,
                  saved: item.isSaved,
                  saving: _saving,
                  onSave: () => _save(item),
                  onDelete: () => _delete(item),
                  onShare: (anchor) => shareMedia(anchor, item),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Print extends StatelessWidget {
  const _Print({
    required this.item,
    required this.onZoomChanged,
    required this.onWrite,
    required this.onDismiss,
  });

  final MediaItem item;
  final ValueChanged<bool> onZoomChanged;
  final VoidCallback onWrite;

  /// A tap off the print (on the dimmed board) puts it down.
  final VoidCallback onDismiss;

  /// Taps on the print itself are kept; taps around it dismiss.
  Widget _held(Widget print) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onDismiss,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: GestureDetector(onTap: () {}, child: print),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final path = item.outputPath;
    if (CameraCatalog.byId(item.cameraId).isInstant) {
      return Zoomable(
        onZoomChanged: onZoomChanged,
        child: _held(
          InstantPrint(
            note: item.note,
            onNoteTap: onWrite,
            picture: path == null
                ? const ColoredBox(color: Colors.black12)
                : Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                  ),
          ),
        ),
      );
    }
    final aspect = (item.width ?? 3) / (item.height ?? 2);
    return Zoomable(
      onZoomChanged: onZoomChanged,
      child: _held(
        AspectRatio(
          aspectRatio: aspect,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Color(0xFFFBF8F1),
              boxShadow: [BoxShadow(color: Colors.black87, blurRadius: 24, offset: Offset(0, 12))],
            ),
            child: path == null
                ? const ColoredBox(color: Colors.black12)
                : Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                  ),
          ),
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    this.onWrite,
    required this.saved,
    required this.saving,
    required this.onSave,
    required this.onDelete,
    required this.onShare,
  });

  final VoidCallback? onWrite;
  final bool saved;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onDelete;
  final Future<void> Function(BuildContext anchor) onShare;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Builder(
            builder: (anchor) =>
                _RoundAction(icon: Icons.ios_share, label: 'Share', onTap: () => unawaited(onShare(anchor))),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: saved
                ? const _RoundAction(key: ValueKey('s'), icon: Icons.check, label: 'Saved', highlighted: true)
                : _RoundAction(
                    key: const ValueKey('u'),
                    icon: Icons.download,
                    label: saving ? 'Saving…' : 'Save',
                    onTap: saving ? null : onSave,
                    primary: true,
                  ),
          ),
          if (onWrite != null) _RoundAction(icon: Icons.edit_outlined, label: 'Write', onTap: onWrite),
          _RoundAction(icon: Icons.delete_outline, label: 'Throw away', onTap: onDelete),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.primary = false,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final bg = primary
        ? const Color(0xFFF3E3C8)
        : (highlighted ? const Color(0xFF2F4A2A) : const Color(0x22FFFFFF));
    final fg = primary ? const Color(0xFF3B2A1A) : (highlighted ? const Color(0xFFB9E3A0) : Colors.white);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, color: fg),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}
