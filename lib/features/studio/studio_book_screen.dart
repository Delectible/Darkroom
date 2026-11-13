import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import 'studio_flip_booklet.dart';
import 'studio_layout.dart';
import 'studio_make.dart';
import 'studio_page_turn.dart';
import 'studio_render.dart';
import 'studio_screen.dart';
import 'studio_store.dart';

/// The photo-library album Studio pieces are saved to.
const studioAlbum = 'Darkroom Studio';

/// The album's colours: cream pages in a brown leather cover.
class _Album {
  static const page = Color(0xFFF2EADB);
  static const pageBack = Color(0xFFECE2CF);
  static const leather = Color(0xFF5B3520);
  static const corner = Color(0xFF2A1A10);
  static const number = Color(0xFF8A7258);
}

/// A piece's shape on the page: its picture's, or a flip book's booklet.
Future<double> _aspectOf(StudioWork w) async {
  if (w.kind == StudioKind.flipbook) return 0.8;
  try {
    final buffer = await ui.ImmutableBuffer.fromFilePath(w.path);
    final d = await ui.ImageDescriptor.encoded(buffer);
    final a = d.width / d.height;
    d.dispose();
    buffer.dispose();
    return a;
  } catch (_) {
    return 1;
  }
}

/// Everything made in the Studio, as an album: cream pages in a leather
/// cover, turned like paper; the pieces packed onto each page as many as
/// fit well, each stuck down by hand (a little turned, taped or cornered);
/// a scrapbook page is a page of the album by itself.
class StudioBookScreen extends ConsumerStatefulWidget {
  const StudioBookScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const StudioBookScreen());

  @override
  ConsumerState<StudioBookScreen> createState() => _StudioBookScreenState();
}

class _StudioBookScreenState extends ConsumerState<StudioBookScreen> {
  final _turn = GlobalKey<PageTurnState>();
  final _shot = GlobalKey();
  final _aspects = <String, double>{};
  final _asking = <String>{};
  int _at = 0;
  bool _saving = false;

  void _measure(List<StudioWork> works) {
    for (final w in works) {
      if (_aspects.containsKey(w.id) || !_asking.add(w.id)) continue;
      unawaited(
        _aspectOf(w).then((a) {
          if (mounted) setState(() => _aspects[w.id] = a);
        }),
      );
    }
  }

  Future<void> _savePage(double width) async {
    final box = _shot.currentContext?.findRenderObject();
    if (box is! RenderRepaintBoundary) return;
    setState(() => _saving = true);
    String? error;
    try {
      final ok = await Gal.hasPermission(toAlbum: true) || await Gal.requestPermission(toAlbum: true);
      if (!ok) {
        error = 'Photo library access was denied';
      } else {
        final image = await box.toImage(pixelRatio: 2000 / width);
        final path = '${Directory.systemTemp.path}/studio_page_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await writeStudioJpeg(image, path);
        image.dispose();
        await Gal.putImage(path, album: studioAlbum);
        unawaited(File(path).delete().then((_) {}, onError: (_) {}));
      }
    } on GalException catch (e) {
      error = e.type.message;
    } catch (e) {
      error = "Couldn't save it: $e";
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error ?? 'Page saved to Photos')));
  }

  @override
  Widget build(BuildContext context) {
    final works = ref.watch(studioBookProvider).value ?? const <StudioWork>[];
    _measure(works);
    final ready = works.every((w) => _aspects.containsKey(w.id));
    final pages = ready
        ? layBook([
            for (final w in works) (aspect: _aspects[w.id]!, fullPage: w.kind == StudioKind.scrapbook),
          ])
        : const <BookPageLayout>[];
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
                child: works.isEmpty
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
                    : !ready
                    ? const Center(child: CircularProgressIndicator(color: StudioInk.brass))
                    : LayoutBuilder(
                        builder: (context, box) {
                          // the biggest 3:4 page that fits, room round it for the cover
                          final pw = math.min(box.maxWidth - 44, (box.maxHeight - 40) * bookPageAspect);
                          final ph = pw / bookPageAspect;
                          return Column(
                            children: [
                              Expanded(
                                child: Center(
                                  child: _Cover(
                                    width: pw,
                                    height: ph,
                                    child: ClipRect(
                                      child: PageTurn(
                                        key: _turn,
                                        count: pages.length,
                                        page: at,
                                        onPage: (i) => setState(() => _at = i),
                                        back: const _PaperPage(back: true),
                                        builder: (context, i) {
                                          final page = _AlbumPage(
                                            number: i + 1,
                                            works: [for (final k in pages[i].pieces) works[k]],
                                            rects: pages[i].rects,
                                          );
                                          return i == at ? RepaintBoundary(key: _shot, child: page) : page;
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(0, 6, 0, 14),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _NavButton(
                                      tooltip: 'Previous page',
                                      icon: Icons.chevron_left,
                                      onTap: at == 0 ? null : () => _turn.currentState?.previous(),
                                    ),
                                    const SizedBox(width: 12),
                                    Flexible(
                                      child: FilledButton(
                                        onPressed: _saving ? null : () => _savePage(pw),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: StudioInk.brass,
                                          foregroundColor: const Color(0xFF22150B),
                                          minimumSize: const Size(0, 44),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          textStyle: const TextStyle(fontWeight: FontWeight.w700),
                                        ),
                                        child: Text(
                                          _saving ? 'Saving…' : 'Save page to Photos',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    _NavButton(
                                      tooltip: 'Next page',
                                      icon: Icons.chevron_right,
                                      onTap: at >= pages.length - 1 ? null : () => _turn.currentState?.next(),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.tooltip, required this.icon, this.onTap});

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: onTap == null ? const Color(0x335A3A24) : const Color(0xFF5A3A24),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: onTap == null ? StudioInk.muted : StudioInk.ink),
        ),
      ),
    ),
  );
}

/// The leather cover round the page, and the page edges beneath it.
class _Cover extends StatelessWidget {
  const _Cover({required this.width, required this.height, required this.child});

  final double width, height;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        const Positioned(
          left: -10,
          top: -10,
          right: -16,
          bottom: -12,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.horizontal(left: Radius.circular(6), right: Radius.circular(14)),
              boxShadow: [BoxShadow(color: Color(0x99000000), blurRadius: 26, offset: Offset(0, 14))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.horizontal(left: Radius.circular(6), right: Radius.circular(14)),
              child: RepaintBoundary(child: CustomPaint(painter: _LeatherPainter())),
            ),
          ),
        ),
        // the edges of the pages beneath this one
        for (var k = 4; k >= 1; k--)
          Positioned(
            left: 0,
            top: k * 0.8,
            right: -k * 1.5,
            bottom: -k * 1.4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color.lerp(const Color(0xFFE9E0CD), const Color(0xFFCFC3AA), k / 4),
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(5)),
              ),
            ),
          ),
        Positioned.fill(child: child),
      ],
    ),
  );
}

class _LeatherPainter extends CustomPainter {
  const _LeatherPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.5),
          radius: 1.3,
          colors: [Color(0xFF6E4229), _Album.leather, Color(0xFF3E2414)],
        ).createShader(r),
    );
    // the grain: fine pits and creases
    final rnd = math.Random(7);
    final dot = Paint();
    final n = (size.width * size.height / 14).round().clamp(500, 30000);
    for (var i = 0; i < n; i++) {
      dot.color = rnd.nextBool() ? const Color(0x1A000000) : const Color(0x0DFFE0C0);
      canvas.drawCircle(
        Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
        0.4 + rnd.nextDouble() * 0.9,
        dot,
      );
    }
    // a stitched line round the edge
    final stitch = Paint()
      ..color = const Color(0x55E8C9A0)
      ..strokeWidth = 1;
    final s = r.deflate(5);
    for (var x = s.left; x < s.right; x += 7) {
      canvas.drawLine(Offset(x, s.top), Offset(x + 3.5, s.top), stitch);
      canvas.drawLine(Offset(x, s.bottom), Offset(x + 3.5, s.bottom), stitch);
    }
    for (var y = s.top; y < s.bottom; y += 7) {
      canvas.drawLine(Offset(s.right, y), Offset(s.right, y + 3.5), stitch);
    }
  }

  @override
  bool shouldRepaint(_LeatherPainter old) => false;
}

/// A bare album page: cream paper with a fine grain, the spine's shadow
/// down its left edge (the back of a page: plain, a touch darker).
class _PaperPage extends StatelessWidget {
  const _PaperPage({this.back = false});

  final bool back;

  @override
  Widget build(BuildContext context) => RepaintBoundary(child: CustomPaint(painter: _GrainPainter(back)));
}

class _GrainPainter extends CustomPainter {
  const _GrainPainter(this.back);

  final bool back;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = back ? _Album.pageBack : _Album.page);
    final rnd = math.Random(back ? 5 : 3);
    // soft blotches and fine specks
    for (var i = 0; i < 18; i++) {
      final rad = size.shortestSide * (0.1 + rnd.nextDouble() * 0.25);
      canvas.drawCircle(
        Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
        rad,
        Paint()
          ..color = (rnd.nextBool() ? const Color(0xFF8A6A40) : const Color(0xFFFFFFFF)).withValues(
            alpha: 0.05,
          )
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, rad * 0.6),
      );
    }
    final speck = Paint();
    final n = (size.width * size.height / 30).round().clamp(300, 20000);
    for (var i = 0; i < n; i++) {
      speck.color = const Color(0xFF6A5030).withValues(alpha: 0.04 + rnd.nextDouble() * 0.07);
      canvas.drawCircle(
        Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
        0.3 + rnd.nextDouble() * 0.5,
        speck,
      );
    }
    if (!back) _spine(canvas, size);
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.back != back;
}

/// The page curving into the spine: dark at the left edge.
void _spine(Canvas canvas, Size size) {
  final w = size.width * 0.09;
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w, size.height),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(w, 0),
        const [Color(0x70402510), Color(0x20402510), Color(0x00402510)],
        const [0, 0.35, 1],
      ),
  );
}

class _SpinePainter extends CustomPainter {
  const _SpinePainter();

  @override
  void paint(Canvas canvas, Size size) => _spine(canvas, size);

  @override
  bool shouldRepaint(_SpinePainter old) => false;
}

/// One page of the album: its pieces where the layout put them, each a
/// little turned and off true, as if stuck down by hand (the same each
/// time). A scrapbook is the page.
class _AlbumPage extends StatelessWidget {
  const _AlbumPage({required this.number, required this.works, required this.rects});

  final int number;
  final List<StudioWork> works;
  final List<Rect> rects;

  @override
  Widget build(BuildContext context) {
    final scrapbook = works.length == 1 && works.first.kind == StudioKind.scrapbook;
    return LayoutBuilder(
      builder: (context, box) {
        final u = box.maxWidth;
        if (scrapbook) {
          final w = works.first;
          return GestureDetector(
            onTap: () => _open(context, w),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: _Album.page),
                Image.file(File(w.path), fit: BoxFit.cover, cacheWidth: 1400, gaplessPlayback: true),
                const IgnorePointer(child: CustomPaint(painter: _SpinePainter())),
              ],
            ),
          );
        }
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            const _PaperPage(),
            for (var i = 0; i < works.length; i++) _placed(context, works[i], rects[i], u),
            Positioned(
              left: 0,
              right: 0,
              bottom: u * 0.025,
              child: Text(
                '— $number —',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontFamilyFallback: const ['serif', 'Times New Roman'],
                  fontStyle: FontStyle.italic,
                  color: _Album.number,
                  fontSize: math.max(11, u * 0.034),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _placed(BuildContext context, StudioWork w, Rect unit, double u) {
    final rnd = math.Random(w.id.hashCode);
    final turn = (rnd.nextDouble() - 0.5) * 0.13;
    final nudge = Offset((rnd.nextDouble() - 0.5) * 0.03 * u, (rnd.nextDouble() - 0.5) * 0.03 * u);
    final r = Rect.fromLTWH(unit.left * u, unit.top * u, unit.width * u, unit.height * u);
    // (a touch smaller than its spot: room to turn without touching)
    final shown = Rect.fromCenter(center: r.center + nudge, width: r.width * 0.93, height: r.height * 0.93);
    return Positioned.fromRect(
      rect: shown,
      child: Transform.rotate(
        angle: turn,
        child: GestureDetector(
          onTap: () => _open(context, w),
          child: _StuckDown(work: w, unit: u, seed: rnd.nextInt(1 << 30)),
        ),
      ),
    );
  }
}

void _open(BuildContext context, StudioWork w) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => w.kind == StudioKind.flipbook ? FlipBookViewer(work: w) : StudioWorkViewer(work: w),
  ),
);

/// A piece as it sits on the page: strips taped at the top, collages held
/// by photo corners, a flip book as its booklet (riffling now and then).
class _StuckDown extends StatelessWidget {
  const _StuckDown({required this.work, required this.unit, required this.seed});

  final StudioWork work;
  final double unit;
  final int seed;

  @override
  Widget build(BuildContext context) {
    if (work.kind == StudioKind.flipbook) {
      return Center(
        child: FlipBooklet(work: work, riffle: Riffle.nowAndThen, badge: true),
      );
    }
    final rnd = math.Random(seed);
    final picture = DecoratedBox(
      decoration: const BoxDecoration(
        boxShadow: [BoxShadow(color: Color(0x59000000), blurRadius: 6, offset: Offset(1.5, 3.5))],
      ),
      child: Image.file(File(work.path), fit: BoxFit.fill, cacheWidth: 900, gaplessPlayback: true),
    );
    final c = unit * 0.045;
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        picture,
        if (work.kind == StudioKind.strip)
          Positioned(
            top: -unit * 0.018,
            left: 0,
            right: 0,
            child: Center(
              child: Transform.rotate(
                angle: (rnd.nextDouble() - 0.5) * 0.3,
                child: Container(
                  width: unit * 0.13,
                  height: unit * 0.04,
                  decoration: const BoxDecoration(
                    color: Color(0xBFF0E1B4),
                    boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 1.5, offset: Offset(0, 1))],
                  ),
                ),
              ),
            ),
          )
        else ...[
          for (final (a, at) in [
            (0.0, Alignment.topLeft),
            (math.pi / 2, Alignment.topRight),
            (math.pi, Alignment.bottomRight),
            (-math.pi / 2, Alignment.bottomLeft),
          ])
            Positioned(
              left: at.x < 0 ? -c * 0.25 : null,
              right: at.x > 0 ? -c * 0.25 : null,
              top: at.y < 0 ? -c * 0.25 : null,
              bottom: at.y > 0 ? -c * 0.25 : null,
              child: Transform.rotate(
                angle: a,
                child: CustomPaint(size: Size.square(c), painter: const _PhotoCorner()),
              ),
            ),
        ],
      ],
    );
  }
}

/// A black paper photo corner (drawn for the top left).
class _PhotoCorner extends CustomPainter {
  const _PhotoCorner();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawShadow(path, const Color(0xFF000000), 1.5, false);
    canvas.drawPath(path, Paint()..color = _Album.corner);
    canvas.drawLine(
      Offset(size.width * 0.9, size.height * 0.05),
      Offset(size.width * 0.05, size.height * 0.9),
      Paint()
        ..color = const Color(0x22FFFFFF)
        ..strokeWidth = 0.8,
    );
  }

  @override
  bool shouldRepaint(_PhotoCorner old) => false;
}

/// A flip book held big: the booklet flicking through its pages at the
/// speed you pick, replay, and Save or Share as a video (made again at the
/// new speed if you changed it). One from before its pages were kept plays
/// its video in the booklet.
class FlipBookViewer extends ConsumerStatefulWidget {
  const FlipBookViewer({super.key, required this.work});

  final StudioWork work;

  @override
  ConsumerState<FlipBookViewer> createState() => _FlipBookViewerState();
}

class _FlipBookViewerState extends ConsumerState<FlipBookViewer> {
  late StudioWork _work = widget.work;
  late int _pageMs = widget.work.pageMs ?? StudioMake.pageMsDefault;
  int _replays = 0;
  String? _busy;
  VideoPlayerController? _video;

  bool get _hasPages => _work.pages.length > 1;

  @override
  void initState() {
    super.initState();
    if (!_hasPages) {
      final v = _video = VideoPlayerController.file(File(_work.path));
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

  /// The video at the speed chosen (made again if it changed).
  Future<String?> _ready() async {
    if (!_hasPages || _pageMs == _work.pageMs) return _work.path;
    setState(() => _busy = 'Making…');
    try {
      final w = await StudioMake.reflip(_work, _pageMs);
      await ref.read(studioBookProvider.notifier).replace(w);
      _work = w;
      return w.path;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't make it: $e")));
      }
      return null;
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _save() async {
    final path = await _ready();
    if (path == null || !mounted) return;
    setState(() => _busy = 'Saving…');
    String? error;
    try {
      final ok = await Gal.hasPermission(toAlbum: true) || await Gal.requestPermission(toAlbum: true);
      if (!ok) {
        error = 'Photo library access was denied';
      } else {
        await Gal.putVideo(path, album: studioAlbum);
      }
    } on GalException catch (e) {
      error = e.type.message;
    }
    if (!mounted) return;
    setState(() => _busy = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error ?? 'Saved to Photos')));
  }

  Future<void> _share(BuildContext anchor) async {
    final box = anchor.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
    final path = await _ready();
    if (path == null) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: 'video/mp4')],
        sharePositionOrigin: origin,
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
    await ref.read(studioBookProvider.notifier).delete(_work);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final v = _video;
    final n = _work.pages.length;
    return Scaffold(
      backgroundColor: const Color(0xFF17120E),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back to the book',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: StudioInk.ink),
                  ),
                  const Expanded(
                    child: Text(
                      'FLIP BOOK',
                      style: TextStyle(
                        color: StudioInk.label,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (n > 0) Text('$n pages', style: const TextStyle(color: StudioInk.muted, fontSize: 12)),
                  IconButton(
                    tooltip: 'Take it out of the book',
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline, color: StudioInk.muted),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: FractionallySizedBox(
                  widthFactor: 0.72,
                  child: FlipBooklet(
                    key: ValueKey(_replays),
                    work: _work,
                    riffle: Riffle.loop,
                    pageMs: _pageMs,
                    cacheWidth: 1000,
                    face: _hasPages
                        ? null
                        : (v != null && v.value.isInitialized
                              ? FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: v.value.size.width,
                                    height: v.value.size.height,
                                    child: VideoPlayer(v),
                                  ),
                                )
                              : const ColoredBox(color: Color(0xFFF7F4EE))),
                  ),
                ),
              ),
            ),
            if (_hasPages)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    const Text('Slow', style: TextStyle(color: StudioInk.muted, fontSize: 12)),
                    Expanded(
                      child: Slider(
                        // (right = faster)
                        value: (StudioMake.pageMsMax + StudioMake.pageMsMin - _pageMs).toDouble(),
                        min: StudioMake.pageMsMin.toDouble(),
                        max: StudioMake.pageMsMax.toDouble(),
                        activeColor: StudioInk.brass,
                        inactiveColor: StudioInk.card,
                        onChanged: (x) =>
                            setState(() => _pageMs = StudioMake.pageMsMax + StudioMake.pageMsMin - x.round()),
                      ),
                    ),
                    const Text('Fast', style: TextStyle(color: StudioInk.muted, fontSize: 12)),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _BigAction(
                    icon: Icons.replay,
                    label: 'Replay',
                    onTap: () {
                      setState(() => _replays++);
                      unawaited(_video?.seekTo(Duration.zero));
                    },
                  ),
                  const SizedBox(width: 12),
                  Builder(
                    builder: (anchor) => _BigAction(
                      icon: Icons.ios_share,
                      label: 'Share',
                      onTap: _busy != null ? null : () => unawaited(_share(anchor)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _BigAction(
                    icon: Icons.download,
                    label: _busy ?? 'Save video',
                    primary: true,
                    onTap: _busy != null ? null : _save,
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

class _BigAction extends StatelessWidget {
  const _BigAction({required this.icon, required this.label, this.onTap, this.primary = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? const Color(0xFF22150B) : StudioInk.ink;
    return Material(
      color: primary ? StudioInk.brass : const Color(0xFF2A221B),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: primary ? 112 : 86,
          height: 62,
          child: Opacity(
            opacity: onTap == null ? 0.5 : 1,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: fg, size: 22),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
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
