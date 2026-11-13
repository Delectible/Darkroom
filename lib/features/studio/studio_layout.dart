import 'dart:math' as math;
import 'dart:ui';

/// The book's page shape: 3:4, the scrapbook's own, so a scrapbook page
/// fills a page of the book edge to edge.
const bookPageAspect = 3 / 4;

/// One piece to place: its shape (width / height) and whether it takes a
/// page to itself (a scrapbook).
typedef BookPiece = ({double aspect, bool fullPage});

/// A page: which pieces (by index) and where, as rects on a page 1 wide
/// and 1 / [bookPageAspect] tall.
typedef BookPageLayout = ({List<int> pieces, List<Rect> rects});

const _margin = 0.07, _gap = 0.05;

/// No piece smaller than this across its longest side (page widths), so
/// everything stays big enough to make out.
const _minSide = 0.34;

const _maxPerPage = 6;

/// ...and none bigger than this (page widths).
const _maxSide = 0.68;

/// The book's pages, in the order the pieces were made: a scrapbook alone,
/// the rest packed as many to a page as fit well. For each page every way
/// of putting the next few pieces in rows (or columns) is tried, and the
/// one that covers the most paper wins, a little in favour of more pieces.
List<BookPageLayout> layBook(List<BookPiece> pieces) {
  final pages = <BookPageLayout>[];
  var i = 0;
  while (i < pieces.length) {
    if (pieces[i].fullPage) {
      pages.add((pieces: [i], rects: [Offset.zero & const Size(1, 1 / bookPageAspect)]));
      i++;
      continue;
    }
    // the run up to the next scrapbook
    var end = i;
    while (end < pieces.length && !pieces[end].fullPage && end - i < _maxPerPage) {
      end++;
    }
    _Try? best;
    for (var k = 1; k <= end - i; k++) {
      final idx = [for (var j = i; j < i + k; j++) j];
      final t = _bestOf(idx, [for (final j in idx) pieces[j].aspect]);
      if (t == null) continue;
      if (best == null || t.score > best.score) best = t;
    }
    best ??= _bestOf([i], [pieces[i].aspect], strict: false)!;
    pages.add((pieces: best.pieces, rects: best.rects));
    i += best.pieces.length;
  }
  return pages;
}

class _Try {
  _Try(this.pieces, this.rects, this.score);

  final List<int> pieces;
  final List<Rect> rects;
  final double score;
}

/// The best arrangement of these pieces on one page, or null if none keeps
/// every piece big enough.
_Try? _bestOf(List<int> idx, List<double> aspects, {bool strict = true}) {
  const w = 1 - 2 * _margin, h = 1 / bookPageAspect - 2 * _margin;
  _Try? best;
  // (in the order made, and tall to wide: strips side by side)
  final orders = <List<int>>{
    [for (var j = 0; j < idx.length; j++) j],
    [for (var j = 0; j < idx.length; j++) j]..sort((a, b) => aspects[a].compareTo(aspects[b])),
  };
  final n = idx.length;
  for (final order in orders) {
    // every split of the order into consecutive rows
    for (var mask = 0; mask < 1 << (n - 1); mask++) {
      final groups = <List<int>>[[]];
      for (var j = 0; j < n; j++) {
        groups.last.add(order[j]);
        if (j < n - 1 && mask & (1 << j) != 0) groups.add([]);
      }
      for (final byColumns in [false, true]) {
        final rects = _arrange(groups, aspects, w, h, byColumns);
        if (rects == null) continue;
        final small = rects.any((r) => math.max(r.width, r.height) < _minSide);
        if (strict && small) continue;
        final covered = rects.fold<double>(0, (a, r) => a + r.width * r.height) / (w * h);
        // (more pieces to a page beats one big one; the space still counts)
        final score = covered * 0.6 + 0.2 * n;
        if (best == null || score > best.score) {
          best = _Try([for (final o in order) idx[o]], [for (final o in order) rects[o]], score);
        }
      }
    }
  }
  return best;
}

/// [groups] as rows across the page (or columns down it), each row as tall
/// as fills the width, all shrunk to fit if too tall; centred. Rects come
/// back by piece (indexes into [aspects]).
List<Rect>? _arrange(List<List<int>> groups, List<double> aspects, double w, double h, bool byColumns) {
  // (columns: the same sum with the axes swapped)
  final across = byColumns ? h : w, along = byColumns ? w : h;
  double shape(int j) => byColumns ? 1 / aspects[j] : aspects[j];
  final sizes = <double>[];
  for (final g in groups) {
    final sum = g.fold<double>(0, (a, j) => a + shape(j));
    sizes.add((across - _gap * (g.length - 1)) / sum);
  }
  final total = sizes.fold<double>(0, (a, s) => a + s);
  final room = along - _gap * (groups.length - 1);
  if (room <= 0) return null;
  var k = math.min(1.0, room / total);
  // (and none bigger than about two thirds of the page: a lone piece sits
  // on the page rather than filling it)
  var biggest = 0.0;
  for (var gi = 0; gi < groups.length; gi++) {
    for (final j in groups[gi]) {
      biggest = math.max(biggest, math.max(shape(j), 1.0) * sizes[gi]);
    }
  }
  if (biggest * k > _maxSide) k = _maxSide / biggest;
  final out = List<Rect>.filled(aspects.length, Rect.zero);
  final used = total * k + _gap * (groups.length - 1);
  var y = _margin + (along - used) / 2;
  for (var gi = 0; gi < groups.length; gi++) {
    final g = groups[gi];
    final s = sizes[gi] * k;
    final rowLen = g.fold<double>(0, (a, j) => a + shape(j) * s) + _gap * (g.length - 1);
    var x = _margin + (across - rowLen) / 2;
    for (final j in g) {
      final len = shape(j) * s;
      out[j] = byColumns ? Rect.fromLTWH(y, x, s, len) : Rect.fromLTWH(x, y, len, s);
      x += len + _gap;
    }
    y += s + _gap;
  }
  return out;
}
