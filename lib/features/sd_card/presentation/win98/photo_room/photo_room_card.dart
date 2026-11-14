import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../../../core/db/media_repository.dart';
import '../pixel_icons.dart';
import '../win98_widgets.dart';

/// WordArt's classic looks.
enum WordArtStyle {
  fire('Fire'),
  rainbow('Rainbow'),
  chrome('Chrome'),
  ocean('Ocean'),
  classic('Classic');

  const WordArtStyle(this.label);
  final String label;
}

/// The card's paper.
enum CardPaper {
  cream('Cream', Color(0xFFFFFBE8)),
  white('White', Color(0xFFFFFFFF)),
  sky('Sky', Color(0xFFCDEBFF)),
  pink('Pink', Color(0xFFFFDDEE)),
  teal('Teal', Color(0xFF008080));

  const CardPaper(this.label, this.color);
  final String label;
  final Color color;
}

/// The clip art on offer.
const clipArt = [
  PixelIcon.clipSun,
  PixelIcon.clipBalloon,
  PixelIcon.clipCake,
  PixelIcon.clipHeart,
  PixelIcon.clipStar,
  PixelIcon.clipFlower,
  PixelIcon.clipNote,
  PixelIcon.clipSmiley,
  PixelIcon.clipComputer,
];

enum CardBitKind { photo, word, clip }

/// One thing on the card; places and sizes in card widths.
class CardBit {
  CardBit.photo(MediaItem this.item, this.at) : kind = CardBitKind.photo, clip = null;
  CardBit.word(String this.text, this.at, {this.style = WordArtStyle.fire})
    : kind = CardBitKind.word,
      item = null,
      clip = null;
  CardBit.clip(PixelIcon this.clip, this.at) : kind = CardBitKind.clip, item = null;

  final CardBitKind kind;
  final MediaItem? item;
  final PixelIcon? clip;
  String? text;
  WordArtStyle style = WordArtStyle.fire;
  Offset at;
  double scale = 1;
  double turn = 0;
  final key = GlobalKey();
}

/// The card in progress (kept while the wizard goes back and forth).
class CardDraft {
  CardDraft(List<MediaItem> photos) {
    bits.add(CardBit.word('Hello!', const Offset(0.5, 0.13)));
    final n = photos.length;
    final rnd = math.Random(n);
    for (var i = 0; i < n; i++) {
      final cols = n == 1 ? 1 : 2;
      final row = i ~/ cols, col = i % cols;
      final rows = (n / cols).ceil();
      bits.add(
        CardBit.photo(
            photos[i],
            Offset(
              cols == 1 ? 0.5 : 0.28 + col * 0.44,
              0.34 + (rows == 1 ? 0.18 : row * 0.38) + (rnd.nextDouble() - 0.5) * 0.03,
            ),
          )
          ..turn = (rnd.nextDouble() - 0.5) * 0.16
          ..scale = n == 1 ? 1.5 : 1,
      );
    }
  }

  final bits = <CardBit>[];
  CardPaper paper = CardPaper.cream;

  /// A card is 5 x 7, upright.
  static const aspect = 5 / 7;
}

/// WordArt: [text] in [style], drawn with its fill, outline and shadow.
class WordArt extends StatelessWidget {
  const WordArt({super.key, required this.text, required this.style, required this.size});

  final String text;
  final WordArtStyle style;
  final double size;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontFamily: 'Dial',
      fontWeight: FontWeight.w600,
      fontSize: size,
      height: 1.0,
      letterSpacing: size * 0.02,
    );
    final (fill, outline, shadow) = switch (style) {
      WordArtStyle.fire => (
        const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF35A), Color(0xFFFF8A00), Color(0xFFD40000)],
        ),
        const Color(0xFF3A0000),
        const Color(0xFF808080),
      ),
      WordArtStyle.rainbow => (
        const LinearGradient(
          colors: [
            Color(0xFFFF0000),
            Color(0xFFFF8000),
            Color(0xFFFFFF00),
            Color(0xFF00C000),
            Color(0xFF0080FF),
            Color(0xFF8000FF),
          ],
        ),
        const Color(0xFF000000),
        const Color(0x00000000),
      ),
      WordArtStyle.chrome => (
        const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFF9DB4D8), Color(0xFF3A4A6A), Color(0xFFDDE6F5)],
          stops: [0, 0.45, 0.55, 1],
        ),
        const Color(0xFF000080),
        const Color(0xFF404040),
      ),
      WordArtStyle.ocean => (
        const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF00FFFF), Color(0xFF0060C0), Color(0xFF000080)],
        ),
        const Color(0xFFFFFFFF),
        const Color(0xFF000040),
      ),
      WordArtStyle.classic => (
        const LinearGradient(colors: [Color(0xFF000080), Color(0xFF000080)]),
        const Color(0x00000000),
        const Color(0xFFA0A0A0),
      ),
    };
    final art = Stack(
      children: [
        // the hard drop shadow
        Transform.translate(
          offset: Offset(size * 0.07, size * 0.07),
          child: Text(text, style: base.copyWith(color: shadow)),
        ),
        Text(
          text,
          style: base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = size * 0.08
              ..strokeJoin = StrokeJoin.round
              ..color = outline,
          ),
        ),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: fill.createShader,
          child: Text(text, style: base.copyWith(color: const Color(0xFFFFFFFF))),
        ),
      ],
    );
    // fire and chrome lean back, classic slants
    return switch (style) {
      WordArtStyle.fire || WordArtStyle.chrome => Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.004)
          ..rotateX(0.35),
        child: art,
      ),
      WordArtStyle.classic => Transform(
        alignment: Alignment.center,
        transform: Matrix4.skewX(-0.25),
        child: art,
      ),
      _ => art,
    };
  }
}

/// The card maker: drag, pinch to size and turn; tap a piece to pick it.
/// [boundary] wraps the card for saving.
class CardEditor extends StatefulWidget {
  const CardEditor({super.key, required this.draft, required this.boundary});

  final CardDraft draft;
  final GlobalKey boundary;

  @override
  State<CardEditor> createState() => CardEditorState();
}

class CardEditorState extends State<CardEditor> {
  CardBit? _picked;
  CardBit? _moving;
  double _startScale = 1, _startTurn = 0;
  double _width = 1;
  Offset? _tapAt;

  CardDraft get _d => widget.draft;

  /// Clears the pick (before the card is saved).
  void unpick() => setState(() => _picked = null);

  CardBit? _bitAt(Offset global) {
    for (final b in _d.bits.reversed) {
      final box = b.key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      if ((Offset.zero & box.size).inflate(6).contains(box.globalToLocal(global))) return b;
    }
    return null;
  }

  void _lift(CardBit b) {
    _picked = b;
    _d.bits
      ..remove(b)
      ..add(b);
  }

  Future<String?> _ask(String title, String initial) => showWin98Window<String>(
    context,
    title: title,
    width: 280,
    builder: (context) => _TextAsk(initial: initial),
  );

  Future<void> _addWord() async {
    final t = await _ask('WordArt', 'Happy Birthday!');
    if (t == null || t.isEmpty) return;
    setState(() {
      final b = CardBit.word(t, const Offset(0.5, 0.86), style: WordArtStyle.values[_d.bits.length % 5]);
      _d.bits.add(b);
      _picked = b;
    });
  }

  Future<void> _addClip() async {
    final c = await showWin98Window<PixelIcon>(
      context,
      title: 'Clip Art',
      width: 260,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(8),
        child: Win98Bevel(
          style: BevelStyle.sunken,
          color: W98.window,
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in clipArt)
                GestureDetector(onTap: () => Navigator.of(context).pop(c), child: PixelIconView(c, size: 48)),
            ],
          ),
        ),
      ),
    );
    if (c == null) return;
    setState(() {
      final rnd = math.Random();
      final b = CardBit.clip(c, Offset(0.25 + rnd.nextDouble() * 0.5, 0.55 + rnd.nextDouble() * 0.25));
      _d.bits.add(b);
      _picked = b;
    });
  }

  Future<void> _edit(CardBit b) async {
    if (b.kind != CardBitKind.word) return;
    final t = await _ask('Edit WordArt', b.text ?? '');
    if (t == null) return;
    setState(() {
      if (t.isEmpty) {
        _d.bits.remove(b);
        _picked = null;
      } else {
        b.text = t;
      }
    });
  }

  Widget _bitView(CardBit b, double w) {
    final Widget look = switch (b.kind) {
      CardBitKind.photo => Container(
        width: w * 0.42,
        padding: EdgeInsets.all(w * 0.012),
        decoration: BoxDecoration(
          color: W98.white,
          boxShadow: const [BoxShadow(color: Color(0x80000000), offset: Offset(3, 3))],
        ),
        child: AspectRatio(
          aspectRatio: (b.item!.width ?? 4) / (b.item!.height ?? 3),
          child: b.item!.outputPath == null
              ? ColoredBox(color: W98.shadow)
              : Image.file(File(b.item!.outputPath!), fit: BoxFit.cover, cacheWidth: 900),
        ),
      ),
      CardBitKind.word => WordArt(text: b.text ?? '', style: b.style, size: w * 0.11),
      CardBitKind.clip => PixelIconView(b.clip!, size: w * 0.2),
    };
    return Container(
      key: b.key,
      foregroundDecoration: identical(b, _picked)
          ? BoxDecoration(border: Border.all(color: W98.navy, width: 1.5))
          : null,
      child: look,
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = _picked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // the tool column, like Paint's
              Column(
                children: [
                  _Tool(label: 'A', tip: 'WordArt', onTap: _addWord, wordArt: true),
                  _Tool(icon: PixelIcon.clipBalloon, tip: 'Clip Art', onTap: _addClip),
                  _Tool(
                    icon: PixelIcon.views,
                    tip: 'Paper',
                    onTap: () => setState(
                      () => _d.paper = CardPaper.values[(_d.paper.index + 1) % CardPaper.values.length],
                    ),
                  ),
                  _Tool(
                    icon: PixelIcon.delete,
                    tip: 'Delete',
                    onTap: b == null
                        ? null
                        : () => setState(() {
                            _d.bits.remove(b);
                            _picked = null;
                          }),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Win98Bevel(
                  style: BevelStyle.sunken,
                  color: W98.shadow,
                  padding: const EdgeInsets.all(6),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final w = math.min(box.maxWidth, box.maxHeight * CardDraft.aspect);
                      _width = w;
                      return Center(
                        child: SizedBox(
                          width: w,
                          height: w / CardDraft.aspect,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (d) => setState(() {
                              final hit = _bitAt(d.globalPosition);
                              if (hit == null) {
                                _picked = null;
                              } else {
                                _lift(hit);
                              }
                            }),
                            onDoubleTapDown: (d) => _tapAt = d.globalPosition,
                            onDoubleTap: () {
                              final hit = _tapAt == null ? null : _bitAt(_tapAt!);
                              if (hit != null) _edit(hit);
                            },
                            onScaleStart: (d) {
                              final hit = _bitAt(d.focalPoint) ?? (d.pointerCount > 1 ? _picked : null);
                              _moving = hit;
                              if (hit == null) return;
                              _startScale = hit.scale;
                              _startTurn = hit.turn;
                              setState(() => _lift(hit));
                            },
                            onScaleUpdate: (d) {
                              final m = _moving;
                              if (m == null) return;
                              setState(() {
                                m.at += d.focalPointDelta / _width;
                                m.scale = (_startScale * d.scale).clamp(0.3, 3.5);
                                m.turn = _startTurn + d.rotation;
                              });
                            },
                            onScaleEnd: (_) => _moving = null,
                            child: RepaintBoundary(
                              key: widget.boundary,
                              child: ClipRect(
                                child: ColoredBox(
                                  color: _d.paper.color,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      for (final x in _d.bits)
                                        Positioned(
                                          key: ObjectKey(x),
                                          left: x.at.dx * w,
                                          top: x.at.dy * w,
                                          child: FractionalTranslation(
                                            translation: const Offset(-0.5, -0.5),
                                            child: Transform.rotate(
                                              angle: x.turn,
                                              child: Transform.scale(scale: x.scale, child: _bitView(x, w)),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // what the picked piece can do (always one line, so nothing moves)
        SizedBox(
          height: 26,
          child: b?.kind == CardBitKind.word
              ? ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final s in WordArtStyle.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: Win98Button(
                          toggled: b!.style == s,
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          onPressed: () => setState(() => b.style = s),
                          child: Text(s.label),
                        ),
                      ),
                    Win98Button(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      onPressed: () => _edit(b!),
                      child: const Text('Edit...'),
                    ),
                  ],
                )
              : Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    b == null
                        ? 'Paper: ${_d.paper.label}. Tap a piece to pick it; drag, pinch to size and turn.'
                        : 'Drag to move, pinch to size and turn. Delete removes it.',
                    maxLines: 2,
                    style: W98.text.copyWith(fontSize: 11),
                  ),
                ),
        ),
      ],
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({this.icon, this.label, required this.tip, this.onTap, this.wordArt = false});

  final PixelIcon? icon;
  final String? label;
  final String tip;
  final VoidCallback? onTap;
  final bool wordArt;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Tooltip(
      message: tip,
      child: Win98Button(
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: SizedBox(
          width: 34,
          height: 32,
          child: Center(
            child: wordArt
                ? const WordArt(text: 'A', style: WordArtStyle.fire, size: 20)
                : Opacity(opacity: onTap == null ? 0.4 : 1, child: PixelIconView(icon!, size: 20)),
          ),
        ),
      ),
    ),
  );
}

class _TextAsk extends StatefulWidget {
  const _TextAsk({required this.initial});

  final String initial;

  @override
  State<_TextAsk> createState() => _TextAskState();
}

class _TextAskState extends State<_TextAsk> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Your text:'),
        const SizedBox(height: 4),
        Win98Bevel(
          style: BevelStyle.sunken,
          color: W98.window,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: TextField(
            controller: _c,
            autofocus: true,
            maxLength: 30,
            style: W98.text.copyWith(color: W98.windowInk),
            cursorColor: W98.windowInk,
            decoration: const InputDecoration(isDense: true, border: InputBorder.none, counterText: ''),
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Win98Button(
              minWidth: 70,
              onPressed: () => Navigator.of(context).pop(_c.text.trim()),
              child: const Text('OK'),
            ),
            const SizedBox(width: 6),
            Win98Button(
              minWidth: 70,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    ),
  );
}
