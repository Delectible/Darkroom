import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/media_repository.dart';
import '../../../core/providers.dart';
import '../../cameras/domain/camera_catalog.dart';
import '../../viewer/presentation/media_actions.dart';
import '../../viewer/presentation/zoomable.dart';

/// Inspecting prints on a dark light-table: swipe between them, pinch to
/// look closer, Save copies one to the phone's photo library.
class PrintViewerScreen extends ConsumerStatefulWidget {
  const PrintViewerScreen({super.key, required this.items, required this.initialIndex});

  final List<MediaItem> items;
  final int initialIndex;

  static Route<void> route(List<MediaItem> items, int index) => PageRouteBuilder<void>(
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
    unawaited(HapticFeedback.lightImpact());
    messenger.showSnackBar(SnackBar(content: Text(err ?? 'Saved to your photo library ($filmAlbum).')));
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
      backgroundColor: const Color(0xFF15120F),
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(radius: 0.9, colors: [Color(0xFF2B241D), Color(0xFF100D0B)]),
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
                    itemBuilder: (context, i, onZoom) => _Print(item: items[i], onZoomChanged: onZoom),
                  ),
                ),
                _ActionBar(
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
  const _Print({required this.item, required this.onZoomChanged});

  final MediaItem item;
  final ValueChanged<bool> onZoomChanged;

  @override
  Widget build(BuildContext context) {
    final path = item.outputPath;
    final aspect = (item.width ?? 3) / (item.height ?? 2);
    return Zoomable(
      onZoomChanged: onZoomChanged,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: AspectRatio(
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
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.saved,
    required this.saving,
    required this.onSave,
    required this.onDelete,
    required this.onShare,
  });

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
