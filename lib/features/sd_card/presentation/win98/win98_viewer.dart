import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/media_repository.dart';
import '../../../../core/providers.dart';
import '../../../viewer/presentation/media_actions.dart';
import '../../../viewer/presentation/media_view.dart';
import 'explorer_dialogs.dart';
import 'pixel_icons.dart';
import 'win98_widgets.dart';

/// "Imaging" / "Media Player"-style window for files on Local Disk (C:).
/// ◀ ▶ (or a swipe) flips through the folder in its current sort order.
class Win98ViewerScreen extends ConsumerStatefulWidget {
  const Win98ViewerScreen({super.key, required this.items, required this.initialIndex});

  final List<MediaItem> items;
  final int initialIndex;

  @override
  ConsumerState<Win98ViewerScreen> createState() => _Win98ViewerScreenState();
}

class _Win98ViewerScreenState extends ConsumerState<Win98ViewerScreen> {
  late final List<MediaItem> _items = [...widget.items];
  late int _index = widget.initialIndex.clamp(0, _items.length - 1);
  late final PageController _pages = PageController(initialPage: _index);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  MediaItem get _item => _items[_index];

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= _items.length) {
      unawaited(HapticFeedback.selectionClick());
      return;
    }
    _pages.animateToPage(next, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
  }

  Future<void> _delete() async {
    final r = await win98Box(
      context,
      'Confirm File Delete',
      "Are you sure you want to delete '${_item.fileName}'?\n\nThe copy in your phone's photo library is not affected.",
      icon: Win98MessageIcon.question,
      buttons: const ['Yes', 'No'],
    );
    if (r != 0) return;
    await deleteMedia(ref.read(sdCardRepositoryProvider), _item);
    if (!mounted) return;
    setState(() {
      _items.removeAt(_index);
      if (_index >= _items.length) _index = _items.length - 1;
    });
    if (_items.isEmpty) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final item = _item;
    return Scaffold(
      backgroundColor: W98.desktop,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Win98Window(
            title: '${item.isVideo ? 'Media Player' : 'Imaging'} - ${item.fileName}',
            icon: PixelIconView(item.isVideo ? PixelIcon.videoFile : PixelIcon.imageFile),
            onClose: () => Navigator.of(context).pop(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      _NavButton(glyph: '◀', onPressed: _index > 0 ? () => _go(-1) : null),
                      const SizedBox(width: 2),
                      _NavButton(glyph: '▶', onPressed: _index < _items.length - 1 ? () => _go(1) : null),
                      const SizedBox(width: 8),
                      Win98Bevel(
                        style: BevelStyle.shallow,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        child: Text('${_index + 1} of ${_items.length}', style: W98.text),
                      ),
                      const Spacer(),
                      Builder(
                        builder: (anchor) => Win98Button(
                          onPressed: () => unawaited(shareMedia(anchor, item)),
                          child: const Text('Send To...'),
                        ),
                      ),
                      const SizedBox(width: 3),
                      Win98Button(onPressed: _delete, child: const Text('Delete')),
                    ],
                  ),
                ),
                Expanded(
                  child: Win98Bevel(
                    style: BevelStyle.sunken,
                    color: Colors.black,
                    padding: const EdgeInsets.all(2),
                    child: PageView.builder(
                      controller: _pages,
                      itemCount: _items.length,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemBuilder: (context, i) => MediaView(key: ValueKey(_items[i].id), item: _items[i]),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Win98Bevel(
                  style: BevelStyle.shallow,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    '${item.width ?? '?'} x ${item.height ?? '?'}   ${formatBytes(item.bytes)}'
                    '${item.isVideo ? '   ${formatDuration(item.durationMs)}' : ''}'
                    '${item.isSaved ? '   In Photos' : ''}',
                    style: W98.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Chunky arrow button that fits the 9x toolbar.
class _NavButton extends StatelessWidget {
  const _NavButton({required this.glyph, this.onPressed});

  final String glyph;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 26,
      child: Win98Button(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        child: Text(glyph, style: W98.text.copyWith(fontSize: 13, height: 1)),
      ),
    );
  }
}
