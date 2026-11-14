import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/db/media_repository.dart';
import '../../core/device/haptics.dart';
import '../../core/processing/instant_frame.dart';
import '../../core/processing/paper_wear.dart';
import '../cameras/domain/camera_catalog.dart';
import '../corkboard/presentation/instant_print.dart';
import '../corkboard/presentation/print_frames.dart';
import 'studio_make.dart';
import 'studio_render.dart';
import 'studio_screen.dart';
import 'studio_snapshot.dart';
import 'studio_stickers.dart';
import 'studio_store.dart';

/// The lettering writing can take.
enum ScrapFont {
  hand('Hand', 'Caveat'),
  type('Typewriter', 'Typewriter'),
  marker('Marker', 'Marker'),
  serif('Serif', 'BookSerif'),
  label('Label', 'Dial');

  const ScrapFont(this.title, this.family);
  final String title;
  final String family;
}

enum _Kind { photo, text, sticker }

/// One thing on the page. Positions and sizes are in page widths, so the
/// page can be any size on screen.
class _Bit {
  _Bit.photo(MediaItem this.item, this.at, {required this.frame, this.note})
    : kind = _Kind.photo,
      text = null,
      sticker = null;
  _Bit.text(String this.text, this.at, {this.title = false}) : kind = _Kind.text, item = null, sticker = null;
  _Bit.sticker(Sticker this.sticker, this.at, {this.text}) : kind = _Kind.sticker, item = null;

  final _Kind kind;
  final MediaItem? item;
  final Sticker? sticker;
  bool title = false;

  /// A print's frame here (a frame or instant style name): only on this
  /// page, the print on the board keeps its own.
  String frame = '';

  /// An instant print's writing, a text's words, a sticky note's.
  String? note;
  String? text;
  ScrapFont font = ScrapFont.hand;
  Color? color;

  Offset at;
  double scale = 1;
  double turn = 0;
  final key = GlobalKey();

  bool get instant => item != null && CameraCatalog.byId(item!.cameraId).isInstant;
}

/// The scrapbook: prints (each in a frame of your choosing, just for this
/// page), writing in five letterings, paper stickers; drag, pinch to size
/// and turn; saved as one large picture. The page is as big as fits and
/// stays put while the tools below change.
class ScrapbookEditor extends ConsumerStatefulWidget {
  const ScrapbookEditor({super.key, required this.prints});

  final List<MediaItem> prints;

  @override
  ConsumerState<ScrapbookEditor> createState() => _ScrapbookEditorState();
}

class _ScrapbookEditorState extends ConsumerState<ScrapbookEditor> {
  final _page = GlobalKey();
  final _bits = <_Bit>[];
  StudioPaper _paper = StudioPaper.kraft;
  _Bit? _picked;
  _Bit? _moving;
  double _startScale = 1, _startTurn = 0;
  Offset? _tapAt;
  double _width = 1;
  bool _busy = false;
  bool _laid = false;

  Color get _ink => _paper == StudioPaper.black ? const Color(0xFFF1E9DA) : const Color(0xFF2A1A10);

  static const _inks = [
    Color(0xFF2A1A10),
    Color(0xFFF1E9DA),
    Color(0xFFB3261E),
    Color(0xFF1F3A68),
    Color(0xFF2E6B3A),
    Color(0xFFC8962E),
  ];

  static const _photoWidth = 0.42;

  @override
  void initState() {
    super.initState();
    _lay();
  }

  /// The prints spread evenly over the page under the title, a little
  /// turned and off true.
  void _lay() {
    final frames = ref.read(printFramesProvider);
    final n = widget.prints.length;
    final cols = n <= 1 ? 1 : (n <= 4 ? 2 : 3);
    final rows = (n / cols).ceil();
    const top = 0.2, bottom = 4 / 3 - 0.05;
    final cellW = 0.92 / cols, cellH = (bottom - top) / rows;
    final scale = math.min(1.0, math.min(cellW * 0.86 / _photoWidth, cellH * 0.8 / (_photoWidth * 1.1)));
    final rnd = math.Random(n * 7 + 3);
    _bits.add(_Bit.text('My scrapbook', const Offset(0.5, 0.1), title: true));
    for (var i = 0; i < n; i++) {
      final m = widget.prints[i];
      final row = i ~/ cols, col = i % cols;
      // (a short last row sits in the middle)
      final inRow = row == rows - 1 ? n - row * cols : cols;
      final x = 0.5 + (col - (inRow - 1) / 2) * cellW;
      final y = top + (row + 0.5) * cellH;
      final instant = CameraCatalog.byId(m.cameraId).isInstant;
      _bits.add(
        _Bit.photo(
            m,
            Offset(x + (rnd.nextDouble() - 0.5) * 0.04, y + (rnd.nextDouble() - 0.5) * 0.04),
            frame: instant ? PrintFrames.styleOf(frames, m.id).name : PrintFrames.frameOf(frames, m.id).name,
            note: m.note,
          )
          ..turn = (rnd.nextDouble() - 0.5) * 0.22
          ..scale = scale,
      );
    }
    _laid = true;
  }

  Future<String?> _write(String title, String initial, {int max = 80}) => showDialog<String>(
    context: context,
    builder: (context) {
      final c = TextEditingController(text: initial);
      return AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, maxLength: max, maxLines: 3, minLines: 1),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('OK')),
        ],
      );
    },
  );

  Future<void> _addText() async {
    final t = await _write('Add writing', '');
    if (t == null || t.isEmpty) return;
    setState(() {
      final b = _Bit.text(t, const Offset(0.5, 1.15));
      _bits.add(b);
      _picked = b;
    });
  }

  Future<void> _addSticker() async {
    final s = await showModalBottomSheet<Sticker>(
      context: context,
      backgroundColor: StudioInk.tableDark,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final s in Sticker.values)
                GestureDetector(
                  onTap: () => Navigator.pop(context, s),
                  child: SizedBox(
                    width: 84,
                    child: Column(
                      children: [
                        SizedBox(
                          height: 70,
                          child: Center(child: StickerView(sticker: s, width: 70)),
                        ),
                        const SizedBox(height: 4),
                        Text(s.label, style: const TextStyle(color: StudioInk.muted, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (s == null || !mounted) return;
    String? words;
    if (s == Sticker.note) {
      words = await _write('Sticky note', '', max: 40);
      if (words == null || !mounted) return;
    }
    setState(() {
      final rnd = math.Random();
      final b = _Bit.sticker(
        s,
        Offset(0.35 + rnd.nextDouble() * 0.3, 0.5 + rnd.nextDouble() * 0.3),
        text: words,
      )..turn = (rnd.nextDouble() - 0.5) * 0.3;
      _bits.add(b);
      _picked = b;
    });
  }

  Future<void> _edit(_Bit b) async {
    switch (b.kind) {
      case _Kind.text:
        final t = await _write(b.title ? 'Title' : 'Writing', b.text ?? '');
        if (t == null) return;
        setState(() => t.isEmpty ? _delete(b) : b.text = t);
      case _Kind.photo:
        if (!b.instant) return;
        final t = await _write('Write on the print', b.note ?? '', max: 40);
        if (t == null) return;
        setState(() => b.note = t.isEmpty ? null : t);
      case _Kind.sticker:
        if (b.sticker != Sticker.note) return;
        final t = await _write('Sticky note', b.text ?? '', max: 40);
        if (t == null) return;
        setState(() => b.text = t);
    }
  }

  void _delete(_Bit b) {
    _bits.remove(b);
    if (identical(_picked, b)) _picked = null;
  }

  Future<void> _save() async {
    final box = _page.currentContext?.findRenderObject();
    if (box is! RenderRepaintBoundary) return;
    setState(() {
      _busy = true;
      _picked = null;
    });
    await WidgetsBinding.instance.endOfFrame;
    try {
      // a large picture: 2400 px across
      final image = await box.toImage(pixelRatio: 2400 / _width);
      final work = await StudioMake.saveImage(image, StudioKind.scrapbook);
      image.dispose();
      await ref.read(studioBookProvider.notifier).add(work);
      if (mounted) await popWithFlash(context, work);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't save it: $e")));
      }
    }
  }

  // ---- touch: one gesture for the page, the piece under the finger ----

  _Bit? _bitAt(Offset global) {
    for (final b in _bits.reversed) {
      final box = b.key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      if ((Offset.zero & box.size).inflate(8).contains(box.globalToLocal(global))) return b;
    }
    return null;
  }

  void _lift(_Bit b) {
    _picked = b;
    _bits
      ..remove(b)
      ..add(b);
  }

  void _scaleStart(ScaleStartDetails d) {
    final b = _bitAt(d.focalPoint) ?? (d.pointerCount > 1 ? _picked : null);
    _moving = b;
    if (b == null) return;
    _startScale = b.scale;
    _startTurn = b.turn;
    setState(() => _lift(b));
  }

  void _scaleUpdate(ScaleUpdateDetails d) {
    final b = _moving;
    if (b == null) {
      if (d.pointerCount > 1 && _picked != null) {
        _moving = _picked;
        _startScale = _picked!.scale / d.scale;
        _startTurn = _picked!.turn - d.rotation;
      }
      return;
    }
    setState(() {
      b.at += d.focalPointDelta / _width;
      b.scale = (_startScale * d.scale).clamp(0.25, 3.5);
      b.turn = _startTurn + d.rotation;
    });
  }

  // ---- the pieces ----

  Widget _photo(_Bit b, double w) {
    final m = b.item!;
    final path = m.outputPath;
    final picture = path == null
        ? const ColoredBox(color: Colors.black12)
        : Image.file(File(path), fit: BoxFit.cover, cacheWidth: 1200, gaplessPlayback: true);
    final wear = PaperWear.of(m.id, m.readyAt);
    if (b.instant) {
      return SizedBox(
        width: w * _photoWidth * 0.85,
        child: InstantPrint(
          note: b.note,
          wear: wear,
          style: InstantStyle.named(b.frame) ?? InstantStyle.classic,
          picture: picture,
        ),
      );
    }
    return SizedBox(
      width: w * _photoWidth,
      child: AspectRatio(
        aspectRatio: (m.width ?? 3) / (m.height ?? 2),
        child: FramedPrint(
          frame: PrintFrame.values.asNameMap()[b.frame] ?? PrintFrame.classic,
          photo: picture,
          seed: m.id.hashCode,
          wear: wear,
        ),
      ),
    );
  }

  Widget _text(_Bit b, double w) {
    final color = b.color ?? _ink;
    final size = w * (b.title ? 0.1 : 0.065);
    if (b.font == ScrapFont.label) {
      // embossed label tape: raised white letters on a coloured strip
      final tape = b.color ?? const Color(0xFF1C1C1F);
      final light = tape.computeLuminance() > 0.5;
      return Container(
        padding: EdgeInsets.symmetric(horizontal: size * 0.4, vertical: size * 0.12),
        decoration: BoxDecoration(
          color: tape,
          borderRadius: BorderRadius.circular(size * 0.12),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 2, offset: Offset(1, 1.5))],
        ),
        child: Text(
          (b.text ?? '').toUpperCase(),
          style: TextStyle(
            fontFamily: 'Dial',
            fontWeight: FontWeight.w600,
            fontSize: size * 0.62,
            letterSpacing: size * 0.08,
            color: light ? const Color(0xFF1C1C1F) : const Color(0xFFF5F2EA),
            shadows: const [Shadow(color: Color(0x66000000), offset: Offset(0, 1))],
          ),
        ),
      );
    }
    final (family, factor, weight) = switch (b.font) {
      ScrapFont.hand => ('Caveat', 1.0, FontWeight.w600),
      ScrapFont.type => ('Typewriter', 0.62, FontWeight.w400),
      ScrapFont.marker => ('Marker', 0.66, FontWeight.w400),
      ScrapFont.serif => ('BookSerif', 0.6, FontWeight.w400),
      ScrapFont.label => ('Dial', 0.6, FontWeight.w600),
    };
    return Text(
      b.text ?? '',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: family,
        fontWeight: weight,
        fontSize: size * factor,
        color: color,
        height: 1.1,
      ),
    );
  }

  Widget _bitView(_Bit b, double w) {
    final picked = identical(b, _picked);
    final look = switch (b.kind) {
      _Kind.photo => _photo(b, w),
      _Kind.text => _text(b, w),
      _Kind.sticker => StickerView(sticker: b.sticker!, width: w * b.sticker!.size, text: b.text),
    };
    return DecoratedBox(
      key: b.key,
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(border: picked ? Border.all(color: StudioInk.brass, width: 1.5) : null),
      child: look,
    );
  }

  // ---- the tools under the page (always the same height) ----

  static const _toolsHeight = 150.0;

  Widget _tools() {
    final b = _picked;
    Widget row(List<Widget> children) => Row(mainAxisAlignment: MainAxisAlignment.center, children: children);
    Widget action(IconData icon, String label, VoidCallback onTap, {bool danger = false}) => TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(foregroundColor: danger ? const Color(0xFFFF9A8F) : StudioInk.ink),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
    final remove = b == null
        ? null
        : action(Icons.delete_outline, 'Remove', () => setState(() => _delete(b)), danger: true);
    final Widget body;
    if (b == null) {
      body = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          row([
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _addText,
                style: OutlinedButton.styleFrom(foregroundColor: StudioInk.ink),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Writing'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _addSticker,
                style: OutlinedButton.styleFrom(foregroundColor: StudioInk.ink),
                icon: const Icon(Icons.star_outline, size: 18),
                label: const Text('Sticker'),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text('Page  ', style: TextStyle(color: StudioInk.muted, fontSize: 12)),
                for (final p in const [
                  StudioPaper.kraft,
                  StudioPaper.black,
                  StudioPaper.cream,
                  StudioPaper.white,
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(p.label),
                      selected: _paper == p,
                      onSelected: (_) => setState(() => _paper = p),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap a piece for its options · drag · pinch to size and turn',
            style: TextStyle(color: StudioInk.muted, fontSize: 11),
          ),
        ],
      );
    } else if (b.kind == _Kind.photo) {
      final m = b.item!;
      final thumb = m.thumbPath ?? m.outputPath;
      final preview = thumb == null
          ? const ColoredBox(color: Colors.black26)
          : Image.file(File(thumb), fit: BoxFit.cover, cacheWidth: 160);
      body = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          b.instant
              ? FramePicker(
                  options: [for (final f in InstantStyle.values) (f.name, f.label)],
                  current: b.frame,
                  onPick: (f) => setState(() => b.frame = f),
                  swatch: (f) => InstantPrint(style: InstantStyle.named(f)!, shadow: false, picture: preview),
                )
              : FramePicker(
                  options: [for (final f in PrintFrame.values) (f.name, f.label)],
                  current: b.frame,
                  onPick: (f) => setState(() => b.frame = f),
                  swatch: (f) => AspectRatio(
                    aspectRatio: (m.width ?? 3) / (m.height ?? 2),
                    child: FramedPrint(frame: PrintFrame.values.byName(f), photo: preview, shadow: false),
                  ),
                ),
          row([if (b.instant) action(Icons.edit_outlined, 'Write on it', () => _edit(b)), remove!]),
        ],
      );
    } else if (b.kind == _Kind.text) {
      body = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in ScrapFont.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                        f == ScrapFont.label ? 'LABEL' : f.title,
                        style: TextStyle(fontFamily: f.family, fontSize: f == ScrapFont.hand ? 18 : 13),
                      ),
                      selected: b.font == f,
                      onSelected: (_) => setState(() => b.font = f),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          row([
            for (final c in _inks)
              GestureDetector(
                onTap: () => setState(() => b.color = c),
                child: Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: (b.color ?? _ink) == c ? StudioInk.brass : StudioInk.card,
                      width: (b.color ?? _ink) == c ? 3 : 1.5,
                    ),
                  ),
                ),
              ),
          ]),
          row([
            action(Icons.edit_outlined, 'Edit', () => _edit(b)),
            Expanded(
              child: Slider(
                value: b.scale.clamp(0.25, 3.5),
                min: 0.25,
                max: 3.5,
                activeColor: StudioInk.brass,
                inactiveColor: StudioInk.card,
                onChanged: (v) => setState(() => b.scale = v),
              ),
            ),
            remove!,
          ]),
        ],
      );
    } else {
      body = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            b.sticker!.label,
            style: const TextStyle(color: StudioInk.label, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          row([
            if (b.sticker == Sticker.note) action(Icons.edit_outlined, 'Edit', () => _edit(b)),
            remove!,
            action(Icons.check, 'Done', () => setState(() => _picked = null)),
          ]),
        ],
      );
    }
    return SizedBox(
      height: _toolsHeight,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: body),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StudioInk.table,
      appBar: AppBar(
        backgroundColor: StudioInk.tableDark,
        foregroundColor: StudioInk.ink,
        title: const Text('Scrapbook'),
        actions: [
          if (_picked != null)
            TextButton(
              onPressed: () => setState(() => _picked = null),
              style: TextButton.styleFrom(foregroundColor: StudioInk.label),
              child: const Text('Done'),
            ),
        ],
      ),
      body: StudioTable(
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    // the biggest 3:4 page that fits, fixed for good
                    final w = math.min(box.maxWidth - 24, (box.maxHeight - 16) * 0.75);
                    _width = w;
                    return Center(
                      child: SizedBox(
                        width: w,
                        height: w / 0.75,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (d) => setState(() {
                            final b = _bitAt(d.globalPosition);
                            if (b == null) {
                              _picked = null;
                            } else {
                              _lift(b);
                            }
                          }),
                          onDoubleTapDown: (d) => _tapAt = d.globalPosition,
                          onDoubleTap: () {
                            final at = _tapAt;
                            final b = at == null ? null : _bitAt(at);
                            if (b != null) unawaited(_edit(b));
                          },
                          onScaleStart: _scaleStart,
                          onScaleUpdate: _scaleUpdate,
                          onScaleEnd: (_) => _moving = null,
                          child: RepaintBoundary(
                            key: _page,
                            child: ClipRect(
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned.fill(child: StudioPaperView(paper: _paper)),
                                  if (_laid)
                                    for (final b in _bits)
                                      Positioned(
                                        // (keyed: lifting a piece reorders the pile)
                                        key: ObjectKey(b),
                                        left: b.at.dx * w,
                                        top: b.at.dy * w,
                                        child: FractionalTranslation(
                                          translation: const Offset(-0.5, -0.5),
                                          child: Transform.rotate(
                                            angle: b.turn,
                                            child: Transform.scale(scale: b.scale, child: _bitView(b, w)),
                                          ),
                                        ),
                                      ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              _tools(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: StudioInk.brass,
                      foregroundColor: const Color(0xFF22150B),
                    ),
                    onPressed: _busy
                        ? null
                        : () {
                            unawaited(Haptics.selectionClick());
                            unawaited(_save());
                          },
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : const Text('Save scrapbook page'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
