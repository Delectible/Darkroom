import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import 'studio_screen.dart';
import 'studio_store.dart';

/// The photo-library album Studio pieces are saved to.
const studioAlbum = 'Darkroom Studio';

/// The book's pages: a scrapbook fills a page; strips (1 place), collages
/// and flip books (2 places) share pages of 3 places, in the order made.
List<List<StudioWork>> studioPages(List<StudioWork> works) {
  final pages = <List<StudioWork>>[];
  var page = <StudioWork>[];
  var used = 0;
  void close() {
    if (page.isNotEmpty) pages.add(page);
    page = [];
    used = 0;
  }

  for (final w in works) {
    if (w.kind == StudioKind.scrapbook) {
      close();
      pages.add([w]);
      continue;
    }
    final size = w.kind == StudioKind.strip ? 1 : 2;
    if (used + size > 3) close();
    page.add(w);
    used += size;
  }
  close();
  return pages;
}

/// Everything made in the Studio, as pages of an album.
class StudioBookScreen extends ConsumerStatefulWidget {
  const StudioBookScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const StudioBookScreen());

  @override
  ConsumerState<StudioBookScreen> createState() => _StudioBookScreenState();
}

class _StudioBookScreenState extends ConsumerState<StudioBookScreen> {
  final _pages = PageController();
  int _at = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final works = ref.watch(studioBookProvider).value ?? const <StudioWork>[];
    final pages = studioPages(works);
    final at = pages.isEmpty ? 0 : _at.clamp(0, pages.length - 1);
    return Scaffold(
      backgroundColor: StudioInk.table,
      body: StudioTable(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 18, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back to the Studio',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: StudioInk.ink),
                    ),
                    const Expanded(
                      child: Text(
                        'THE BOOK',
                        style: TextStyle(
                          color: StudioInk.label,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (pages.isNotEmpty)
                      Text(
                        'page ${at + 1} of ${pages.length}',
                        style: const TextStyle(color: StudioInk.muted, fontSize: 12),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: pages.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: Text(
                            'The book is empty. Strips, collages, scrapbook pages and flip books you make in the '
                            'Studio go here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: StudioInk.muted, height: 1.4),
                          ),
                        ),
                      )
                    : PageView.builder(
                        controller: _pages,
                        itemCount: pages.length,
                        onPageChanged: (i) => setState(() => _at = i),
                        itemBuilder: (context, i) => _BookPage(works: pages[i]),
                      ),
              ),
              if (pages.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Previous page',
                        onPressed: at == 0
                            ? null
                            : () => _pages.previousPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOut,
                              ),
                        icon: const Icon(Icons.chevron_left, color: StudioInk.ink),
                      ),
                      const SizedBox(width: 24),
                      IconButton(
                        tooltip: 'Next page',
                        onPressed: at >= pages.length - 1
                            ? null
                            : () => _pages.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOut,
                              ),
                        icon: const Icon(Icons.chevron_right, color: StudioInk.ink),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One album page: dark paper, its pieces laid on it.
class _BookPage extends StatelessWidget {
  const _BookPage({required this.works});

  final List<StudioWork> works;

  @override
  Widget build(BuildContext context) {
    final full = works.length == 1 && works.first.kind == StudioKind.scrapbook;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFF1C1714),
          borderRadius: BorderRadius.horizontal(left: Radius.circular(4), right: Radius.circular(10)),
          boxShadow: [BoxShadow(color: Color(0x99000000), blurRadius: 24, offset: Offset(0, 12))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: full
              ? Center(child: _Piece(work: works.first))
              : LayoutBuilder(
                  builder: (context, box) => Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (final w in works)
                          SizedBox(
                            width: box.maxWidth * (w.kind == StudioKind.strip ? 0.28 : 0.62),
                            child: _Piece(work: w),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _Piece extends StatelessWidget {
  const _Piece({required this.work});

  final StudioWork work;

  @override
  Widget build(BuildContext context) {
    final picture = work.cover ?? work.path;
    return GestureDetector(
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StudioWorkViewer(work: work))),
      child: Stack(
        alignment: Alignment.center,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              boxShadow: [BoxShadow(color: Color(0x88000000), blurRadius: 8, offset: Offset(0, 4))],
            ),
            child: Image.file(File(picture), cacheWidth: 900, gaplessPlayback: true),
          ),
          if (work.isVideo)
            const DecoratedBox(
              decoration: BoxDecoration(color: Color(0x88000000), shape: BoxShape.circle),
              child: Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.play_arrow, color: Colors.white, size: 32),
              ),
            ),
        ],
      ),
    );
  }
}

/// One piece, big: save to Photos, share, throw away. A flip book plays.
class StudioWorkViewer extends ConsumerStatefulWidget {
  const StudioWorkViewer({super.key, required this.work});

  final StudioWork work;

  @override
  ConsumerState<StudioWorkViewer> createState() => _StudioWorkViewerState();
}

class _StudioWorkViewerState extends ConsumerState<StudioWorkViewer> {
  VideoPlayerController? _video;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.work.isVideo) {
      final v = _video = VideoPlayerController.file(File(widget.work.path));
      unawaited(
        v.initialize().then((_) async {
          await v.setLooping(true);
          await v.play();
          if (mounted) setState(() {});
        }),
      );
    }
  }

  @override
  void dispose() {
    unawaited(_video?.dispose());
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    String? error;
    try {
      final ok = await Gal.hasPermission(toAlbum: true) || await Gal.requestPermission(toAlbum: true);
      if (!ok) {
        error = 'Photo library access was denied';
      } else if (widget.work.isVideo) {
        await Gal.putVideo(widget.work.path, album: studioAlbum);
      } else {
        await Gal.putImage(widget.work.path, album: studioAlbum);
      }
    } on GalException catch (e) {
      error = e.type.message;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error ?? 'Saved to Photos')));
  }

  Future<void> _share(BuildContext anchor) async {
    final box = anchor.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(widget.work.path, mimeType: widget.work.isVideo ? 'video/mp4' : 'image/jpeg')],
        sharePositionOrigin: box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null,
      ),
    );
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Take it out of the book?'),
        content: const Text('A copy you saved to Photos stays there.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Take it out')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(studioBookProvider.notifier).delete(widget.work);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final v = _video;
    final (name, _) = studioKindLook(widget.work.kind);
    return Scaffold(
      backgroundColor: const Color(0xFF17120E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF17120E),
        foregroundColor: StudioInk.ink,
        title: Text(name),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: widget.work.isVideo
                    ? (v != null && v.value.isInitialized
                          ? AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v))
                          : const CircularProgressIndicator(color: StudioInk.brass))
                    : InteractiveViewer(maxScale: 5, child: Image.file(File(widget.work.path))),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Builder(
                    builder: (anchor) => TextButton.icon(
                      onPressed: () => unawaited(_share(anchor)),
                      style: TextButton.styleFrom(foregroundColor: StudioInk.ink),
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Share'),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: StudioInk.brass,
                      foregroundColor: const Color(0xFF22150B),
                    ),
                    icon: const Icon(Icons.download),
                    label: Text(_saving ? 'Saving…' : 'Save to Photos'),
                  ),
                  TextButton.icon(
                    onPressed: _delete,
                    style: TextButton.styleFrom(foregroundColor: StudioInk.muted),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
