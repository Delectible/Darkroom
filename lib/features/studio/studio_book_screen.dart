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

import '../../core/device/upright.dart';
import 'studio_flip_booklet.dart';
import 'studio_layout.dart';
import 'studio_page_turn.dart';
import 'studio_render.dart';
import 'studio_screen.dart';
import 'studio_store.dart';
import 'studio_ui.dart';

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

  // (turns with the phone, like the corkboard)
  static Route<void> route() => MaterialPageRoute<void>(
    settings: UprightApp.landscape,
    builder: (_) => const UprightPage(child: StudioBookScreen()),
  );

  @override
  ConsumerState<StudioBookScreen> createState() => _StudioBookScreenState();
}

class _StudioBookScreenState extends ConsumerState<StudioBookScreen> with SingleTickerProviderStateMixin {
  final _turn = GlobalKey<PageTurnState>();
  final _shot = GlobalKey();
  final _aspects = <String, double>{};
  final _asking = <String>{};
  int _at = 0;
  bool _saving = false;
  // (a page is up off the left, on its way back)
  bool _lifted = false;

  // The book arrives shut and its cover swings open once its pictures are
  // ready (0 shut .. 1 open).
  late final AnimationController _open =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1150))
        // (the buttons wake once it's open)
        ..addStatusListener((_) {
          if (mounted) setState(() {});
        });
  bool _opening = false;

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  void _openWhenReady(bool ready) {
    if (!ready || _opening) return;
    _opening = true;
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 280), () {
        if (mounted) unawaited(_open.forward());
      }),
    );
  }

  void _measure(List<StudioWork> works) {
    for (final w in works) {
      if (_aspects.containsKey(w.id) || !_asking.add(w.id)) continue;
      unawaited(
        _aspectOf(w).then((a) async {
          // (decoded before the page shows it, at the size the page uses)
          if (mounted && w.kind != StudioKind.flipbook) {
            final size = w.kind == StudioKind.scrapbook ? 1400 : 900;
            await precacheImage(
              ResizeImage(FileImage(File(w.path)), width: size),
              context,
              onError: (_, _) {},
            );
          }
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
    studioNote(context, error ?? 'Page saved to Photos');
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
    final n = pages.length;
    final at = n == 0 ? 0 : _at.clamp(0, n - 1);
    return Scaffold(
      // (text boxes move up out of the keyboard's way; the screen stays put)

      resizeToAvoidBottomInset: false,
      backgroundColor: StudioInk.table,
      body: StudioTable(
        child: SafeArea(
          child: Builder(
            builder: (context) {
              final screen = MediaQuery.sizeOf(context);
              final sideways = screen.width > screen.height * 1.2;
              // (sideways: the width of the heading's column and of the buttons')
              final side = (screen.width * 0.19).clamp(120.0, 164.0);
              final back = IconButton(
                tooltip: 'Back to the Studio',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back, color: StudioInk.ink),
              );
              const title = Text(
                'THE BOOK',
                style: TextStyle(
                  color: StudioInk.label,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                  fontSize: 16,
                ),
              );
              // Sideways both pages are filled, as a book's are: page one
              // faces the cover's lining, then two and three, and so on.
              // [open] is how many leaves have been turned over.
              final open = sideways ? (at + 1) ~/ 2 : at;
              final turns = sideways ? n ~/ 2 + 1 : n;
              int rightOf(int i) => sideways ? 2 * i : i;
              // (the page Save takes: the right one, or the last, on the left)
              final shown = sideways ? math.min(2 * open, n - 1) : at;
              final count = pages.isEmpty
                  ? null
                  : Text(
                      !sideways || open == 0 || 2 * open >= n
                          ? 'page ${shown + 1} of $n'
                          : 'pages ${2 * open}–${2 * open + 1} of $n',
                      style: const TextStyle(color: StudioInk.muted, fontSize: 12),
                    );
              final Widget content = works.isEmpty
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
                  : LayoutBuilder(
                      builder: (context, box) {
                        _openWhenReady(ready);
                        // the open book: the right page as big as fits, a strip
                        // of the left page beside it (all of it, sideways)
                        final left = sideways ? 1.0 : 0.3;
                        // (sideways the buttons are beside it: all the height's the book's)
                        final pw = math.min(
                          (box.maxWidth - (sideways ? side + 40 : 24)) / (1 + left),
                          (box.maxHeight - (sideways ? 44 : 96)) * bookPageAspect,
                        );
                        final ph = pw / bookPageAspect;
                        final opened = _open.isCompleted;
                        final book = Expanded(
                          // (upright the book runs off the left of the screen)
                          child: Align(
                            alignment: sideways ? Alignment.center : Alignment.centerLeft,
                            child: AnimatedBuilder(
                              animation: _open,
                              builder: (context, _) => _OpenBook(
                                // (a page on its way back isn't lying there)
                                leaves: open - (_lifted ? 1 : 0),
                                pageWidth: pw,
                                pageHeight: ph,
                                left: left,
                                open: Curves.easeInOutCubic.transform(_open.value),
                                pages: !ready || pages.isEmpty
                                    ? const Align(
                                        alignment: Alignment.centerRight,
                                        child: FractionallySizedBox(widthFactor: 0.5, child: _PaperPage()),
                                      )
                                    : PageTurn(
                                        key: _turn,
                                        count: turns,
                                        page: open,
                                        onPage: (i) =>
                                            setState(() => _at = sideways ? math.min(2 * i, n - 1) : i),
                                        onTurning: (forward) {
                                          final lifted = forward == false;
                                          if (lifted != _lifted) setState(() => _lifted = lifted);
                                        },
                                        left: (context, i) {
                                          // (facing page one: the front board's
                                          // lining, already there beneath)
                                          if (i == 0) return const SizedBox.shrink();
                                          if (!sideways) {
                                            return const ClipPath(
                                              clipper: _PageShape(left: true),
                                              child: _PaperPage(back: true, left: true),
                                            );
                                          }
                                          final c = 2 * i - 1;
                                          final page = _AlbumPage(
                                            number: c + 1,
                                            left: true,
                                            works: [for (final k in pages[c].pieces) works[k]],
                                            rects: pages[c].rects,
                                          );
                                          return ClipPath(
                                            clipper: const _PageShape(left: true),
                                            child: c == shown
                                                ? RepaintBoundary(key: _shot, child: page)
                                                : page,
                                          );
                                        },
                                        builder: (context, i) {
                                          final c = rightOf(i);
                                          // (sideways the last page may be a left one)
                                          if (c >= n) {
                                            return const ClipPath(clipper: _PageShape(), child: _PaperPage());
                                          }
                                          final page = _AlbumPage(
                                            number: c + 1,
                                            works: [for (final k in pages[c].pieces) works[k]],
                                            rects: pages[c].rects,
                                          );
                                          return ClipPath(
                                            clipper: const _PageShape(),
                                            child: c == shown
                                                ? RepaintBoundary(key: _shot, child: page)
                                                : page,
                                          );
                                        },
                                      ),
                              ),
                            ),
                          ),
                        );
                        final prev = _NavButton(
                          tooltip: 'Previous page',
                          icon: Icons.chevron_left,
                          onTap: !opened || open == 0 ? null : () => _turn.currentState?.previous(),
                        );
                        final next = _NavButton(
                          tooltip: 'Next page',
                          icon: Icons.chevron_right,
                          onTap: !opened || open >= turns - 1 ? null : () => _turn.currentState?.next(),
                        );
                        final save = FilledButton(
                          onPressed: _saving || !opened ? null : () => _savePage(pw),
                          style: FilledButton.styleFrom(
                            backgroundColor: StudioInk.brass,
                            foregroundColor: const Color(0xFF22150B),
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            textStyle: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          child: Text(
                            _saving ? 'Saving…' : (sideways ? 'Save page' : 'Save page to Photos'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                        if (sideways) {
                          return Row(
                            children: [
                              book,
                              SizedBox(
                                width: side,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [prev, const SizedBox(width: 12), next],
                                    ),
                                    const SizedBox(height: 12),
                                    Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: save),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            book,
                            Padding(
                              padding: const EdgeInsets.fromLTRB(0, 6, 0, 14),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  prev,
                                  const SizedBox(width: 12),
                                  Flexible(child: save),
                                  const SizedBox(width: 12),
                                  next,
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    );
              // Sideways the heading stands in a column on the left and the
              // buttons on the right (see the book's own layout), so the
              // book has the screen's whole height.
              if (sideways) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: side,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6, top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            back,
                            const Padding(padding: EdgeInsets.only(left: 12, top: 4), child: title),
                            if (count != null)
                              Padding(padding: const EdgeInsets.only(left: 12, top: 4), child: count),
                          ],
                        ),
                      ),
                    ),
                    Expanded(child: content),
                  ],
                );
              }
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 6, 18, 0),
                    child: Row(
                      children: [
                        back,
                        const Expanded(child: title),
                        ?count,
                      ],
                    ),
                  ),
                  Expanded(child: content),
                ],
              );
            },
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

/// How far the boards stand out past the pages, all round.
const _overhang = 12.0;

/// The album, built as a book is: a back board with the block of pages on
/// it, a spine with its headbands, and the front board, hinged at the
/// spine. [open] swings the front board up towards you and over (0 shut,
/// 1 lying open on the left, its lining up). The left page is where a
/// turned page lands: a strip of it shows upright (the book runs off the
/// screen), all of it sideways.
class _OpenBook extends StatelessWidget {
  const _OpenBook({
    required this.pageWidth,
    required this.pageHeight,
    required this.left,
    required this.open,
    required this.pages,
    required this.leaves,
  });

  final double pageWidth, pageHeight;

  /// How much of the left page shows, in page widths.
  final double left;
  final double open;
  final Widget pages;

  /// How many pages lie turned over on the left.
  final int leaves;

  @override
  Widget build(BuildContext context) {
    final pw = pageWidth, ph = pageHeight;
    final spine = pw * left;
    final lying = open >= 1;
    // The front board: the same one the whole way, so nothing changes as
    // it lands. Past upright its inside shows (the lining).
    final cover = Positioned(
      left: spine,
      width: pw + _overhang,
      top: -_overhang,
      bottom: -_overhang,
      child: Transform(
        alignment: Alignment.centerLeft,
        transform: Matrix4.identity()
          ..setEntry(3, 2, lying ? 0 : 0.0011)
          // (positive: its free edge comes up off the table at you)
          ..rotateY(math.pi * open),
        child: open < 0.5
            ? const _FrontCover()
            : Transform(
                alignment: Alignment.center,
                transform: Matrix4.rotationY(math.pi),
                child: const _CoverInside(),
              ),
      ),
    );
    return SizedBox(
      width: pw * (1 + left),
      height: ph,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // the back board, under the pages
          Positioned(
            left: spine - 2,
            top: -_overhang,
            right: -_overhang,
            bottom: -_overhang,
            child: const _Board(stitchRight: true),
          ),
          // (past upright the front board is over the left side: beneath
          // the pages' layer, which has nothing there until it lands)
          if (open >= 0.5) cover,
          // the spine, the blocks of pages beneath the open ones, the
          // gutter where the pages curve down into it, the headbands
          Positioned.fill(
            child: CustomPaint(
              painter: _BookBody(spine: spine, pageWidth: pw, leaves: lying ? leaves : 0, open: open),
            ),
          ),
          // the pages: the right one, and (once the book's open) the left.
          // A turning page may reach above and below the book.
          Positioned.fill(
            child: ClipRect(
              clipper: _TallClip(ph, from: lying ? 0 : spine),
              child: Stack(
                clipBehavior: Clip.none,
                children: [Positioned(left: spine - pw, width: pw * 2, top: 0, bottom: 0, child: pages)],
              ),
            ),
          ),
          if (open < 0.5) cover,
        ],
      ),
    );
  }
}

/// A leather board with its shadow on the table.
class _Board extends StatelessWidget {
  const _Board({this.stitchLeft = false, this.stitchRight = false});

  final bool stitchLeft, stitchRight;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      borderRadius: BorderRadius.all(Radius.circular(8)),
      boxShadow: [BoxShadow(color: Color(0xA6000000), blurRadius: 26, offset: Offset(0, 14))],
    ),
    child: ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _LeatherPainter(stitchLeft: stitchLeft, stitchRight: stitchRight),
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

/// Everything above and below the book kept; cut at [from] on the left.
class _TallClip extends CustomClipper<Rect> {
  const _TallClip(this.pageHeight, {required this.from});

  final double pageHeight, from;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(from, -pageHeight, size.width * 3, pageHeight * 2);

  @override
  bool shouldReclip(_TallClip old) => old.pageHeight != pageHeight || old.from != from;
}

/// How deep and how long the dip is where a page curves into the gutter
/// (in page widths).
const _dip = 0.02, _dipLength = 0.2;

/// A page's outline: its gutter-side corners dip, as pages do curving down
/// into the spine ([left]: a left-hand page, its gutter on the right).
class _PageShape extends CustomClipper<Path> {
  const _PageShape({this.left = false});

  final bool left;

  @override
  Path getClip(Size size) {
    final w = size.width, h = size.height;
    final n = w * _dip, g = w * _dipLength;
    final p = Path()
      ..moveTo(0, n)
      ..quadraticBezierTo(g * 0.35, 0, g, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(g, h)
      ..quadraticBezierTo(g * 0.35, h, 0, h - n)
      ..close();
    return left
        ? p.transform(
            (Matrix4.identity()
                  ..translateByDouble(w, 0, 0, 1)
                  ..scaleByDouble(-1, 1, 1, 1))
                .storage,
          )
        : p;
  }

  @override
  bool shouldReclip(_PageShape old) => old.left != left;
}

/// What lies under the open pages: the spine (rounded leather, seen above
/// and below the pages), the blocks of pages beneath (each leaf a line,
/// the top page's shadow on them), the dark of the gutter where the pages
/// dip, and the headbands at the head and tail of the spine.
class _BookBody extends CustomPainter {
  const _BookBody({required this.spine, required this.pageWidth, required this.leaves, required this.open});

  final double spine, pageWidth;

  /// How many pages lie on the left (the top one drawn by the pages' layer;
  /// the rest a block beneath it).
  final int leaves;

  /// How far the front board has swung (1: down on the left).
  final double open;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final lying = open >= 1, leftPage = leaves > 0;
    // the spine: a rounded back between the boards
    final back = Rect.fromLTRB(spine - 9, -_overhang, spine + 9, h + _overhang);
    canvas.drawRRect(
      RRect.fromRectAndRadius(back, const Radius.circular(5)),
      Paint()
        ..shader = ui.Gradient.linear(
          back.centerLeft,
          back.centerRight,
          const [
            Color(0xFF2E1A0E),
            Color(0xFF6A3F26),
            Color(0xFF7A4A2C),
            Color(0xFF6A3F26),
            Color(0xFF2E1A0E),
          ],
          const [0, 0.25, 0.5, 0.75, 1],
        ),
    );

    void block(Rect page, int leaves, {required bool right}) {
      for (var k = leaves; k >= 1; k--) {
        final out = k * 1.25;
        final r = right
            ? Rect.fromLTRB(page.left, page.top + k * 0.5, page.right + out, page.bottom + out)
            : Rect.fromLTRB(page.left - out, page.top + k * 0.5, page.right, page.bottom + out);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            r,
            topRight: right ? const Radius.circular(3) : Radius.zero,
            bottomRight: right ? const Radius.circular(4) : Radius.zero,
            topLeft: right ? Radius.zero : const Radius.circular(3),
            bottomLeft: right ? Radius.zero : const Radius.circular(4),
          ),
          Paint()..color = k.isOdd ? const Color(0xFFE6DCC7) : const Color(0xFFCDBFA4),
        );
      }
      // the top page's shadow on the block's edges: a little, close under
      // it (paper still, not a grey line)
      final depth = leaves * 1.25;
      canvas.drawRect(
        Rect.fromLTRB(
          page.left - (right ? 0 : depth),
          page.bottom,
          page.right + (right ? depth : 0),
          page.bottom + depth,
        ),
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, page.bottom), Offset(0, page.bottom + depth), const [
            Color(0x38402510),
            Color(0x08402510),
          ]),
      );
      final sideX = right ? page.right : page.left;
      canvas.drawRect(
        right
            ? Rect.fromLTRB(sideX, page.top, sideX + depth, page.bottom)
            : Rect.fromLTRB(sideX - depth, page.top, sideX, page.bottom),
        Paint()
          ..shader = ui.Gradient.linear(Offset(sideX, 0), Offset(sideX + (right ? depth : -depth), 0), const [
            Color(0x30402510),
            Color(0x08402510),
          ]),
      );
    }

    block(Rect.fromLTRB(spine, 0, spine + pageWidth, h), 5, right: true);
    if (leaves > 1) {
      block(Rect.fromLTRB(spine - pageWidth, 0, spine, h), math.min(leaves - 1, 2), right: false);
    }

    // the gutter: dark where the pages dip into the spine, head and tail
    // (shut, or with the front board still in the air, only the right half:
    // the rest is under the board)
    // The headbands come out from under the board as it lifts.
    final bandFrom = spine - 10 * (open * 2).clamp(0.0, 1.0);
    final n = pageWidth * _dip, g = pageWidth * _dipLength;
    for (final top in [true, false]) {
      final y = top ? 0.0 : h, dir = top ? 1.0 : -1.0;
      canvas.save();
      if (!lying) canvas.clipRect(Rect.fromLTRB(spine, -_overhang, size.width + _overhang, h + _overhang));
      final wedge = Path()
        ..moveTo(spine - (leftPage ? g : 0), y)
        ..lineTo(spine + g, y)
        ..lineTo(spine + g, y + dir * 0.5)
        ..quadraticBezierTo(spine + g * 0.35, y + dir * 0.5, spine, y + dir * (n + 1))
        ..lineTo(spine - (leftPage ? 0.01 : 0), y + dir * (n + 1));
      if (leftPage) wedge.quadraticBezierTo(spine - g * 0.35, y + dir * 0.5, spine - g, y + dir * 0.5);
      wedge.close();
      canvas.drawPath(wedge, Paint()..color = const Color(0xFF24150C));
      canvas.restore();
      // the headband: a little striped silk roll across the spine
      final band = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(spine, y + dir * (n * 0.5 - 1)),
          width: 20,
          height: math.max(4, n * 0.9),
        ),
        const Radius.circular(2.5),
      );
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(bandFrom, -_overhang, size.width, h + _overhang));
      canvas.clipRRect(band);
      canvas.drawRRect(band, Paint()..color = const Color(0xFFE9DFC8));
      final stripe = Paint()..color = const Color(0xFFA5281F);
      for (var x = band.left; x < band.right; x += 4) {
        canvas.drawRect(Rect.fromLTWH(x, band.top, 2, band.height), stripe);
      }
      // (round: light along its top, dark beneath)
      canvas.drawRect(
        band.outerRect,
        Paint()
          ..shader = ui.Gradient.linear(
            band.outerRect.topCenter,
            band.outerRect.bottomCenter,
            const [Color(0x40FFFFFF), Color(0x00000000), Color(0x59000000)],
            const [0, 0.45, 1],
          ),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BookBody old) =>
      old.spine != spine || old.pageWidth != pageWidth || old.leaves != leaves || old.open != open;
}

/// The album's front cover: leather, a gold rule, its name stamped in gold.
class _FrontCover extends StatelessWidget {
  const _FrontCover();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const _Board(stitchRight: true),
      LayoutBuilder(
        builder: (context, box) {
          final u = box.maxWidth;
          const gold = Color(0xFFD9B26A);
          return Padding(
            padding: EdgeInsets.all(u * 0.08),
            child: DecoratedBox(
              decoration: BoxDecoration(border: Border.all(color: gold.withValues(alpha: 0.7), width: 1.5)),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'DARKROOM',
                      style: TextStyle(
                        fontFamily: 'BookSerif',
                        color: gold,
                        fontSize: u * 0.085,
                        letterSpacing: u * 0.02,
                        shadows: const [Shadow(color: Color(0x99000000), offset: Offset(1, 1.5))],
                      ),
                    ),
                    SizedBox(height: u * 0.03),
                    Container(width: u * 0.3, height: 1.2, color: gold.withValues(alpha: 0.7)),
                    SizedBox(height: u * 0.03),
                    Text(
                      'photographs',
                      style: TextStyle(
                        fontFamily: 'BookSerif',
                        fontStyle: FontStyle.italic,
                        color: gold.withValues(alpha: 0.85),
                        fontSize: u * 0.045,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ],
  );
}

/// The inside of the front board: the leather turned in round its outer
/// edges, the lining paper pasted over the rest, up to the hinge (drawn
/// for the board lying open on the left: its hinge on the right).
class _CoverInside extends StatelessWidget {
  const _CoverInside();

  @override
  Widget build(BuildContext context) => const Stack(
    fit: StackFit.expand,
    children: [
      _Board(stitchLeft: true),
      Padding(
        padding: EdgeInsets.fromLTRB(_overhang, _overhang, 0, _overhang),
        child: RepaintBoundary(child: CustomPaint(painter: _LiningPainter())),
      ),
    ],
  );
}

class _LiningPainter extends CustomPainter {
  const _LiningPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = const Color(0xFF5E1F1B));
    final dot = Paint()..color = const Color(0x40D9B26A);
    final step = math.max(10.0, size.width / 18);
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        final o = Offset(x + ((y / step).floor().isOdd ? step / 2 : 0), y);
        canvas.drawPath(
          Path()
            ..moveTo(o.dx, o.dy - 2.4)
            ..lineTo(o.dx + 2.4, o.dy)
            ..lineTo(o.dx, o.dy + 2.4)
            ..lineTo(o.dx - 2.4, o.dy)
            ..close(),
          dot,
        );
      }
    }
    // into the spine on its right
    canvas.drawRect(
      Rect.fromLTWH(size.width - size.width * 0.09, 0, size.width * 0.09, size.height),
      Paint()
        ..shader = ui.Gradient.linear(Offset(size.width, 0), Offset(size.width * 0.91, 0), const [
          Color(0x80000000),
          Color(0x00000000),
        ]),
    );
  }

  @override
  bool shouldRepaint(_LiningPainter old) => false;
}

class _LeatherPainter extends CustomPainter {
  const _LeatherPainter({this.stitchLeft = false, this.stitchRight = false});

  /// Stitching down that edge (along the top and bottom always).
  final bool stitchLeft, stitchRight;

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
      if (stitchRight) canvas.drawLine(Offset(s.right, y), Offset(s.right, y + 3.5), stitch);
      if (stitchLeft) canvas.drawLine(Offset(s.left, y), Offset(s.left, y + 3.5), stitch);
    }
  }

  @override
  bool shouldRepaint(_LeatherPainter old) => old.stitchLeft != stitchLeft || old.stitchRight != stitchRight;
}

/// A bare album page: cream paper with a fine grain, the spine's shadow
/// down its left edge (the back of a page: plain, a touch darker).
class _PaperPage extends StatelessWidget {
  const _PaperPage({this.back = false, this.left = false});

  final bool back;

  /// A left-hand page: curving into the spine on its right.
  final bool left;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _GrainPainter(back, spine: !back && !left),
      foregroundPainter: left ? const _LeftSpine() : null,
    ),
  );
}

class _LeftSpine extends CustomPainter {
  const _LeftSpine();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width, 0);
    canvas.scale(-1, 1);
    _spine(canvas, size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LeftSpine old) => false;
}

class _GrainPainter extends CustomPainter {
  const _GrainPainter(this.back, {required this.spine});

  final bool back, spine;

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
    if (spine) _spine(canvas, size);
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.back != back || old.spine != spine;
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
  const _AlbumPage({required this.number, required this.works, required this.rects, this.left = false});

  /// A left-hand page: the spine on its right.
  final bool left;
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
                Image.file(
                  File(w.path),
                  fit: BoxFit.cover,
                  cacheWidth: 1400,
                  gaplessPlayback: true,
                  frameBuilder: studioFadeIn,
                ),
                IgnorePointer(child: CustomPaint(painter: left ? const _LeftSpine() : const _SpinePainter())),
              ],
            ),
          );
        }
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            _PaperPage(left: left),
            for (var i = 0; i < works.length; i++) _placed(context, works[i], rects[i], u, i, works.length),
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

  Widget _placed(BuildContext context, StudioWork w, Rect unit, double u, int index, int count) {
    final rnd = math.Random(w.id.hashCode);
    final turn = (rnd.nextDouble() - 0.5) * 0.13;
    // Stuck down by hand, not lined up: the first piece drifts towards the
    // top left, the last towards the bottom right, a little at random too.
    final along = count == 1 ? 0.0 : index / (count - 1) - 0.5;
    final drift = Offset(along * 0.1 * u, along * 0.05 * u);
    final nudge = Offset((rnd.nextDouble() - 0.5) * 0.03 * u, (rnd.nextDouble() - 0.5) * 0.03 * u);
    final r = Rect.fromLTWH(unit.left * u, unit.top * u, unit.width * u, unit.height * u);
    // (a touch smaller than its spot: room to turn without touching)
    var shown = Rect.fromCenter(
      center: r.center + drift + nudge,
      width: r.width * 0.93,
      height: r.height * 0.93,
    );
    // (never off the page)
    final page = Rect.fromLTWH(0.03 * u, 0.03 * u, u * 0.94, u / bookPageAspect - 0.1 * u);
    shown = shown.shift(
      Offset(
        math.max(0, page.left - shown.left) - math.max(0, shown.right - page.right),
        math.max(0, page.top - shown.top) - math.max(0, shown.bottom - page.bottom),
      ),
    );
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
    settings: UprightApp.landscape,
    builder: (_) => UprightPage(
      child: w.kind == StudioKind.flipbook ? FlipBookViewer(work: w) : StudioWorkViewer(work: w),
    ),
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
        child: FlipBooklet(work: work, riffle: Riffle.loop),
      );
    }
    final rnd = math.Random(seed);
    final picture = DecoratedBox(
      decoration: const BoxDecoration(
        boxShadow: [BoxShadow(color: Color(0x59000000), blurRadius: 6, offset: Offset(1.5, 3.5))],
      ),
      child: Image.file(
        File(work.path),
        fit: BoxFit.fill,
        cacheWidth: 900,
        gaplessPlayback: true,
        frameBuilder: studioFadeIn,
      ),
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
  late final StudioWork _work = widget.work;
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

  /// The video (made at its speed when it was made: that's how it plays).
  Future<String?> _ready() async => _work.path;

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
    studioNote(context, error ?? 'Saved to Photos');
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
    final ok = await studioAsk(
      context,
      title: 'Take it out of the book?',
      message: 'A copy you saved to Photos stays there.',
      yes: 'Take it out',
      no: 'Keep',
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
      // (text boxes move up out of the keyboard's way; the screen stays put)

      resizeToAvoidBottomInset: false,
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
              child: Builder(
                builder: (context) {
                  final size = MediaQuery.sizeOf(context);
                  final sideways = size.width > size.height * 1.2;
                  // the booklet as big as fits (it's 4:5, a little edge round it)
                  final booklet = LayoutBuilder(
                    builder: (context, box) => Center(
                      child: SizedBox(
                        width: math.min(box.maxWidth * (sideways ? 0.86 : 0.72), (box.maxHeight - 24) * 0.74),
                        child: FlipBooklet(
                          key: ValueKey(_replays),
                          work: _work,
                          riffle: Riffle.loop,
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
                  );
                  final controls = <Widget>[
                    // (shrinks to fit a narrow side panel)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
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
                    ),
                  ];
                  if (sideways) {
                    return Row(
                      children: [
                        Expanded(child: booklet),
                        SizedBox(
                          width: math.min(400, size.width * 0.42),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: controls),
                        ),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Expanded(child: booklet),
                      ...controls,
                    ],
                  );
                },
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
    studioNote(context, error ?? 'Saved to Photos');
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
    final ok = await studioAsk(
      context,
      title: 'Take it out of the book?',
      message: 'A copy you saved to Photos stays there.',
      yes: 'Take it out',
      no: 'Keep',
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
      // (text boxes move up out of the keyboard's way; the screen stays put)

      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFF17120E),
      appBar: StudioTitleBar(
        title: name,
        subtitle: 'Made ${MaterialLocalizations.of(context).formatMediumDate(widget.work.createdAt)}',
        background: const Color(0xFF17120E),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: widget.work.isVideo
                  ? Center(
                      child: v != null && v.value.isInitialized
                          ? AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v))
                          : const CircularProgressIndicator(color: StudioInk.brass),
                    )
                  // (the zoom works over the whole screen, not just the picture's box)
                  : InteractiveViewer(
                      maxScale: 6,
                      child: SizedBox.expand(child: Image.file(File(widget.work.path), fit: BoxFit.contain)),
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
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        fontSize: 15,
                      ),
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
