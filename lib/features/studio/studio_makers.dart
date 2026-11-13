import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/db/media_repository.dart';
import 'studio_make.dart';
import 'studio_render.dart';
import 'studio_screen.dart';
import 'studio_store.dart';

/// Making one piece from [prints]: pops true once it's in the book.
class StudioMaker extends StatelessWidget {
  const StudioMaker({super.key, required this.kind, required this.prints});

  final StudioKind kind;
  final List<MediaItem> prints;

  @override
  Widget build(BuildContext context) => switch (kind) {
    StudioKind.strip || StudioKind.collage => _PictureMaker(kind: kind, prints: prints),
    StudioKind.flipbook => _FlipMaker(prints: prints),
    StudioKind.scrapbook => ScrapbookEditor(prints: prints),
  };
}

/// The maker's frame: a title bar, the piece, its options and the button.
class _MakerScaffold extends StatelessWidget {
  const _MakerScaffold({
    required this.title,
    required this.body,
    required this.options,
    required this.action,
    required this.onMake,
    this.busy = false,
  });

  final String title;
  final Widget body;
  final List<Widget> options;
  final String action;
  final VoidCallback? onMake;
  final bool busy;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: StudioInk.table,
    appBar: AppBar(backgroundColor: StudioInk.tableDark, foregroundColor: StudioInk.ink, title: Text(title)),
    body: StudioTable(
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Center(child: body),
              ),
            ),
            for (final o in options) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 10), child: o),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: StudioInk.brass,
                    foregroundColor: const Color(0xFF22150B),
                  ),
                  onPressed: busy ? null : onMake,
                  child: busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : Text(action),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A row of choices (chips).
class _Choices<T> extends StatelessWidget {
  const _Choices({
    required this.label,
    required this.values,
    required this.name,
    required this.value,
    required this.onPick,
  });

  final String label;
  final List<T> values;
  final String Function(T) name;
  final T value;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 58,
        child: Text(label, style: const TextStyle(color: StudioInk.muted, fontSize: 12)),
      ),
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final v in values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(name(v)),
                    selected: v == value,
                    onSelected: (_) => onPick(v),
                    selectedColor: StudioInk.brass,
                    backgroundColor: StudioInk.card,
                    labelStyle: TextStyle(color: v == value ? const Color(0xFF22150B) : StudioInk.ink),
                    showCheckmark: false,
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// Photo strips and collages: drawn whole, previewed as they'll be saved.
class _PictureMaker extends ConsumerStatefulWidget {
  const _PictureMaker({required this.kind, required this.prints});

  final StudioKind kind;
  final List<MediaItem> prints;

  @override
  ConsumerState<_PictureMaker> createState() => _PictureMakerState();
}

class _PictureMakerState extends ConsumerState<_PictureMaker> {
  List<ui.Image>? _photos;
  ui.Image? _preview;
  StudioPaper _paper = StudioPaper.black;
  CollageStyle _style = CollageStyle.grid;
  bool _busy = false;
  int _run = 0;

  bool get _strip => widget.kind == StudioKind.strip;

  @override
  void initState() {
    super.initState();
    if (!_strip) _paper = StudioPaper.white;
    unawaited(() async {
      final p = await StudioMake.photos(widget.prints);
      if (!mounted) return;
      _photos = p;
      await _draw();
    }());
  }

  @override
  void dispose() {
    _preview?.dispose();
    for (final p in _photos ?? const <ui.Image>[]) {
      p.dispose();
    }
    super.dispose();
  }

  Future<ui.Image> _render() =>
      _strip ? renderStrip(_photos!, _paper, DateTime.now()) : renderCollage(_photos!, _style, _paper);

  Future<void> _draw() async {
    if (_photos == null) return;
    final run = ++_run;
    final img = await _render();
    if (!mounted || run != _run) {
      img.dispose();
      return;
    }
    setState(() {
      _preview?.dispose();
      _preview = img;
    });
  }

  Future<void> _make() async {
    final preview = _preview;
    if (preview == null) return;
    setState(() => _busy = true);
    try {
      final work = await StudioMake.saveImage(preview, widget.kind);
      await ref.read(studioBookProvider.notifier).add(work);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't make it: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return _MakerScaffold(
      title: _strip ? 'Photo Strip' : 'Collage',
      body: preview == null
          ? const CircularProgressIndicator(color: StudioInk.brass)
          : DecoratedBox(
              decoration: const BoxDecoration(
                boxShadow: [BoxShadow(color: Color(0x99000000), blurRadius: 16, offset: Offset(0, 8))],
              ),
              child: RawImage(image: preview, fit: BoxFit.contain),
            ),
      options: [
        if (!_strip)
          _Choices<CollageStyle>(
            label: 'Style',
            values: CollageStyle.values,
            name: (s) => s.label,
            value: _style,
            onPick: (s) {
              setState(() => _style = s);
              unawaited(_draw());
            },
          ),
        _Choices<StudioPaper>(
          label: 'Paper',
          values: _strip
              ? const [StudioPaper.black, StudioPaper.white, StudioPaper.cream]
              : StudioPaper.values,
          name: (p) => p.label,
          value: _paper,
          onPick: (p) {
            setState(() => _paper = p);
            unawaited(_draw());
          },
        ),
      ],
      action: _strip ? 'Make strip' : 'Make collage',
      busy: _busy,
      onMake: preview == null ? null : _make,
    );
  }
}

/// The flip book: previewed as it plays (snap cuts, a white flash, a
/// handheld shake), made into a video.
class _FlipMaker extends ConsumerStatefulWidget {
  const _FlipMaker({required this.prints});

  final List<MediaItem> prints;

  @override
  ConsumerState<_FlipMaker> createState() => _FlipMakerState();
}

class _FlipMakerState extends ConsumerState<_FlipMaker> {
  StudioPaper _paper = StudioPaper.cream;
  late final Timer _tick;
  int _step = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (mounted) setState(() => _step++);
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  Future<void> _make() async {
    setState(() => _busy = true);
    try {
      final work = await StudioMake.flipBook(widget.prints, _paper);
      await ref.read(studioBookProvider.notifier).add(work);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't make it: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 3 shakes a page (360 ms), a flash as the page changes
    final page = (_step ~/ 3) % widget.prints.length;
    final flash = _step % 3 == 0;
    final rnd = math.Random(_step);
    final m = widget.prints[page];
    final path = m.outputPath;
    return _MakerScaffold(
      title: 'Flip Book',
      body: AspectRatio(
        aspectRatio: 4 / 5,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: _paper.color),
            Center(
              child: Transform.translate(
                offset: Offset((rnd.nextDouble() - 0.5) * 4, (rnd.nextDouble() - 0.5) * 4),
                child: Transform.rotate(
                  angle: (rnd.nextDouble() - 0.5) * 0.025,
                  child: FractionallySizedBox(
                    widthFactor: 0.86,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      color: const Color(0xFFF7F4EE),
                      child: path == null
                          ? const SizedBox(height: 120)
                          : Image.file(File(path), cacheWidth: 700, gaplessPlayback: true),
                    ),
                  ),
                ),
              ),
            ),
            if (flash) const ColoredBox(color: Color(0x99FFFFFF)),
          ],
        ),
      ),
      options: [
        Text(
          '${widget.prints.length} pages, about ${(widget.prints.length * 0.4).toStringAsFixed(1)} s. '
          'Saved as a video, ready for Instagram.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: StudioInk.muted, fontSize: 12),
        ),
        _Choices<StudioPaper>(
          label: 'Paper',
          values: StudioPaper.values,
          name: (p) => p.label,
          value: _paper,
          onPick: (p) => setState(() => _paper = p),
        ),
      ],
      action: _busy ? 'Making…' : 'Make flip book',
      busy: _busy,
      onMake: _make,
    );
  }
}

/// One thing on a scrapbook page: a print (frame and all) or some writing.
class _Piece {
  _Piece.photo(this.path, this.at) : text = null, title = false;
  _Piece.text(String this.text, this.at, {this.title = false}) : path = null;

  final String? path;
  String? text;
  final bool title;
  Offset at;
  double scale = 1;
  double turn = 0;
}

/// The scrapbook: each print dragged, turned and sized anywhere on the
/// page with one or two fingers, writing added, a title; saved as one
/// large picture.
class ScrapbookEditor extends ConsumerStatefulWidget {
  const ScrapbookEditor({super.key, required this.prints});

  final List<MediaItem> prints;

  @override
  ConsumerState<ScrapbookEditor> createState() => _ScrapbookEditorState();
}

class _ScrapbookEditorState extends ConsumerState<ScrapbookEditor> {
  final _page = GlobalKey();
  final _pieces = <_Piece>[];
  StudioPaper _paper = StudioPaper.kraft;
  _Piece? _selected;
  Size? _size;
  bool _busy = false;

  // (a gesture's start, for scale and turn)
  double _startScale = 1, _startTurn = 0;

  Color get _ink => _paper == StudioPaper.black ? const Color(0xFFF1E9DA) : const Color(0xFF2A1A10);

  Future<void> _lay(Size size) async {
    _size = size;
    final paths = await StudioMake.framedPaths(widget.prints);
    if (!mounted) return;
    final rnd = math.Random(paths.length);
    setState(() {
      _pieces.add(_Piece.text('My scrapbook', Offset(size.width / 2, size.height * 0.08), title: true));
      for (var i = 0; i < paths.length; i++) {
        final col = i % 2, row = i ~/ 2;
        _pieces.add(
          _Piece.photo(paths[i], Offset(size.width * (0.3 + col * 0.4), size.height * (0.26 + row * 0.2)))
            ..turn = (rnd.nextDouble() - 0.5) * 0.2
            ..scale = paths.length > 4 ? 0.8 : 1,
        );
      }
    });
  }

  Future<String?> _write(String title, String initial) => showDialog<String>(
    context: context,
    builder: (context) {
      final c = TextEditingController(text: initial);
      return AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, maxLength: 80, maxLines: 3, minLines: 1),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('OK')),
        ],
      );
    },
  );

  Future<void> _addText() async {
    final t = await _write('Add writing', '');
    if (t == null || t.isEmpty || _size == null) return;
    setState(() {
      final p = _Piece.text(t, Offset(_size!.width / 2, _size!.height * 0.85));
      _pieces.add(p);
      _selected = p;
    });
  }

  Future<void> _edit(_Piece p) async {
    final t = await _write(p.title ? 'Title' : 'Writing', p.text ?? '');
    if (t == null) return;
    setState(() {
      if (t.isEmpty && !p.title) {
        _pieces.remove(p);
        _selected = null;
      } else {
        p.text = t;
      }
    });
  }

  Future<void> _save() async {
    final box = _page.currentContext?.findRenderObject();
    if (box is! RenderRepaintBoundary || _size == null) return;
    setState(() {
      _busy = true;
      _selected = null;
    });
    await WidgetsBinding.instance.endOfFrame;
    try {
      // a large picture: 2400 px across
      final image = await box.toImage(pixelRatio: 2400 / _size!.width);
      final work = await StudioMake.saveImage(image, StudioKind.scrapbook);
      image.dispose();
      await ref.read(studioBookProvider.notifier).add(work);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't save it: $e")));
      }
    }
  }

  Widget _pieceView(_Piece p, double width) {
    final picked = identical(p, _selected);
    final Widget look = p.path != null
        ? Image.file(File(p.path!), width: width * 0.42, cacheWidth: 900, gaplessPlayback: true)
        : Text(
            p.text ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Caveat',
              fontWeight: FontWeight.w600,
              fontSize: width * (p.title ? 0.1 : 0.065),
              color: _ink,
              height: 1.05,
            ),
          );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        _selected = p;
        // (to the top of the pile)
        _pieces
          ..remove(p)
          ..add(p);
      }),
      onDoubleTap: p.text != null ? () => _edit(p) : null,
      onScaleStart: (_) {
        _startScale = p.scale;
        _startTurn = p.turn;
        setState(() {
          _selected = p;
          _pieces
            ..remove(p)
            ..add(p);
        });
      },
      onScaleUpdate: (d) => setState(() {
        p.at += d.focalPointDelta;
        p.scale = (_startScale * d.scale).clamp(0.3, 3.0);
        p.turn = _startTurn + d.rotation;
      }),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: picked ? Border.all(color: StudioInk.brass, width: 1.5) : null,
          boxShadow: p.path != null
              ? const [BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(2, 4))]
              : null,
        ),
        child: look,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final picked = _selected;
    return _MakerScaffold(
      title: 'Scrapbook',
      body: AspectRatio(
        aspectRatio: 3 / 4,
        child: LayoutBuilder(
          builder: (context, box) {
            if (_size == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_lay(box.biggest)));
            }
            return GestureDetector(
              onTap: () => setState(() => _selected = null),
              child: RepaintBoundary(
                key: _page,
                child: ClipRect(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(child: ColoredBox(color: _paper.color)),
                      for (final p in _pieces)
                        Positioned(
                          left: p.at.dx,
                          top: p.at.dy,
                          child: FractionalTranslation(
                            translation: const Offset(-0.5, -0.5),
                            child: Transform.rotate(
                              angle: p.turn,
                              child: Transform.scale(scale: p.scale, child: _pieceView(p, box.maxWidth)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      options: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _addText,
                style: OutlinedButton.styleFrom(foregroundColor: StudioInk.ink),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Add writing'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: picked?.text == null ? null : () => _edit(picked!),
                style: OutlinedButton.styleFrom(foregroundColor: StudioInk.ink),
                icon: const Icon(Icons.title, size: 18),
                label: Text(picked?.title == true ? 'Edit title' : 'Edit writing'),
              ),
            ),
          ],
        ),
        const Text(
          'Drag to move · pinch to size and turn · double-tap writing to change it',
          textAlign: TextAlign.center,
          style: TextStyle(color: StudioInk.muted, fontSize: 12),
        ),
        _Choices<StudioPaper>(
          label: 'Page',
          values: const [StudioPaper.kraft, StudioPaper.black, StudioPaper.cream, StudioPaper.white],
          name: (p) => p.label,
          value: _paper,
          onPick: (p) => setState(() => _paper = p),
        ),
      ],
      action: 'Save scrapbook page',
      busy: _busy,
      onMake: _size == null ? null : _save,
    );
  }
}
