import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/db/media_repository.dart';
import 'studio_make.dart';
import 'studio_render.dart';
import 'studio_screen.dart';
import 'studio_scrapbook.dart';
import 'studio_snapshot.dart';
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
      if (mounted) await popWithFlash(context, work);
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
  int _pageMs = StudioMake.pageMsDefault;
  late final Timer _tick;
  final _clock = Stopwatch()..start();
  // where the book is, in pages: moved on by the time since the last tick
  // at the speed of the moment, so a new speed changes the pace, not the
  // page
  double _pos = 0;
  int _lastMs = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // (a steady 25 frames a second; the page and shake follow the clock)
    _tick = Timer.periodic(const Duration(milliseconds: 40), (_) {
      final now = _clock.elapsedMilliseconds;
      _pos += (now - _lastMs) / _pageMs;
      _lastMs = now;
      if (mounted) setState(() {});
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
      final work = await StudioMake.flipBook(widget.prints, _paper, pageMs: _pageMs);
      await ref.read(studioBookProvider.notifier).add(work);
      if (mounted) await popWithFlash(context, work);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't make it: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final whole = _pos.floor();
    final page = whole % widget.prints.length;
    final into = ((_pos - whole) * _pageMs).round();
    // the print flashes white for a moment as each page turns
    final flash = into < 40 && whole > 0;
    final rnd = math.Random(page * 9 + into ~/ 120);
    final m = widget.prints[page];
    final path = m.outputPath;
    final seconds = widget.prints.length * _pageMs / 1000;
    return _MakerScaffold(
      title: 'Flip Book',
      body: AspectRatio(
        aspectRatio: 4 / 5,
        child: Stack(
          fit: StackFit.expand,
          children: [
            StudioPaperView(paper: _paper),
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
                      child: Stack(
                        children: [
                          if (path == null)
                            const SizedBox(height: 120)
                          else
                            Image.file(File(path), cacheWidth: 700, gaplessPlayback: true),
                          // (only the print flashes, not the paper round it)
                          if (flash) const Positioned.fill(child: ColoredBox(color: Color(0xFFFFFFFF))),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      options: [
        Text(
          '${widget.prints.length} pages, about ${seconds.toStringAsFixed(1)} s. '
          'Saved as a video, ready for Instagram.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: StudioInk.muted, fontSize: 12),
        ),
        Row(
          children: [
            const SizedBox(
              width: 58,
              child: Text('Speed', style: TextStyle(color: StudioInk.muted, fontSize: 12)),
            ),
            const Text('Slow', style: TextStyle(color: StudioInk.muted, fontSize: 11)),
            Expanded(
              child: Slider(
                // (right = faster: the slider runs from the longest page to the shortest)
                value: (StudioMake.pageMsMax + StudioMake.pageMsMin - _pageMs).toDouble(),
                min: StudioMake.pageMsMin.toDouble(),
                max: StudioMake.pageMsMax.toDouble(),
                activeColor: StudioInk.brass,
                inactiveColor: StudioInk.card,
                onChanged: (v) =>
                    setState(() => _pageMs = StudioMake.pageMsMax + StudioMake.pageMsMin - v.round()),
              ),
            ),
            const Text('Fast', style: TextStyle(color: StudioInk.muted, fontSize: 11)),
          ],
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
