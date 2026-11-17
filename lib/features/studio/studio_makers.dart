import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/db/media_repository.dart';
import 'studio_flip_frames.dart';
import 'studio_make.dart';
import 'studio_render.dart';
import 'studio_screen.dart';
import 'studio_scrapbook.dart';
import 'studio_snapshot.dart';
import 'studio_store.dart';
import 'studio_ui.dart';

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
    this.subtitle,
    required this.body,
    required this.options,
    required this.action,
    required this.onMake,
    this.busy = false,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> options;
  final String action;
  final VoidCallback? onMake;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: StudioInk.brass,
          foregroundColor: const Color(0xFF22150B),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.6, fontSize: 15),
        ),
        onPressed: busy ? null : onMake,
        child: busy
            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
            : Text(action),
      ),
    );
    final size = MediaQuery.sizeOf(context);
    // Sideways: the piece on the left as big as fits, its options beside it.
    final sideways = size.width > size.height * 1.2;
    return Scaffold(
      // (text boxes move up out of the keyboard's way; the screen stays put)

      resizeToAvoidBottomInset: false,
      backgroundColor: StudioInk.table,
      appBar: StudioTitleBar(title: title, subtitle: subtitle),
      body: StudioTable(
        child: SafeArea(
          top: false,
          child: sideways
              ? Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(child: body),
                      ),
                    ),
                    SizedBox(
                      width: math.min(400, size.width * 0.42),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 12, 16, 12),
                        child: Column(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                child: Column(
                                  children: [
                                    for (final o in options)
                                      Padding(padding: const EdgeInsets.only(bottom: 10), child: o),
                                  ],
                                ),
                              ),
                            ),
                            button,
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Center(child: body),
                      ),
                    ),
                    for (final o in options)
                      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 10), child: o),
                    Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 14), child: button),
                  ],
                ),
        ),
      ),
    );
  }
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
      SizedBox(width: 64, child: StudioLabel(label)),
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final v in values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: StudioChip(label: name(v), selected: v == value, onTap: () => onPick(v)),
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
  final _date = DateTime.now();

  // the strip's foot and edges
  StripDate _dateStyle = StripDate.booth;
  String _caption = 'DARKROOM';
  bool _sprockets = false;

  /// How each photo sits in its frame (moved and zoomed by hand).
  late final List<PhotoCrop> _crops = List.filled(widget.prints.length, PhotoCrop.middle);

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

  Future<ui.Image> _render() => _strip
      ? renderStrip(
          _photos!,
          _paper,
          _date,
          crops: _crops,
          dateStyle: _dateStyle,
          caption: _caption,
          sprockets: _sprockets,
        )
      : renderCollage(_photos!, _style, _paper, crops: _crops);

  /// The frames, where they are on the piece.
  List<Rect> get _cells => _strip
      ? stripCells(_crops.length, _date, sprockets: _sprockets).$1
      : collageCells(_crops.length, _style).$1;

  /// A tap at [at] on the piece (in its own pixels): that photo's framing.
  Future<void> _frameAt(Offset at) async {
    final photos = _photos;
    if (photos == null) return;
    final cells = _cells;
    var i = cells.indexWhere((r) => r.contains(at));
    // (loose prints are a little bigger and turned: near enough will do)
    if (i < 0) i = cells.indexWhere((r) => r.inflate(40).contains(at));
    if (i < 0) return;
    final cell = cells[i];
    final crop = await showModalBottomSheet<PhotoCrop>(
      context: context,
      isScrollControlled: true,
      backgroundColor: StudioInk.tableDark,
      builder: (context) => _CropSheet(photo: photos[i], aspect: cell.width / cell.height, crop: _crops[i]),
    );
    if (crop == null || !mounted) return;
    _crops[i] = crop;
    await _draw();
  }

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
        studioNote(context, "Couldn't make it: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return _MakerScaffold(
      title: _strip ? 'Photo Strip' : 'Collage',
      subtitle: _strip
          ? '${widget.prints.length} frames down a booth strip'
          : '${widget.prints.length} prints, cropped to fit',
      body: preview == null
          ? const CircularProgressIndicator(color: StudioInk.brass)
          : AspectRatio(
              aspectRatio: preview.width / preview.height,
              child: LayoutBuilder(
                builder: (context, box) => GestureDetector(
                  // (a photo tapped: move or zoom it in its frame)
                  onTapUp: (d) => unawaited(_frameAt(d.localPosition * (preview.width / box.maxWidth))),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      boxShadow: [BoxShadow(color: Color(0x99000000), blurRadius: 16, offset: Offset(0, 8))],
                    ),
                    child: RawImage(image: preview, fit: BoxFit.fill),
                  ),
                ),
              ),
            ),
      options: [
        const Text(
          'Tap a photo to move or zoom it in its frame.',
          textAlign: TextAlign.center,
          style: TextStyle(color: StudioInk.muted, fontSize: 12),
        ),
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
        if (_strip) ...[
          _Choices<StripDate>(
            label: 'Date',
            values: StripDate.values,
            name: (d) => d.label,
            value: _dateStyle,
            onPick: (d) {
              setState(() => _dateStyle = d);
              unawaited(_draw());
            },
          ),
          Row(
            children: [
              const SizedBox(width: 64, child: StudioLabel('Extras')),
              StudioChip(
                label: 'Film holes',
                selected: _sprockets,
                onTap: () {
                  setState(() => _sprockets = !_sprockets);
                  unawaited(_draw());
                },
              ),
              const SizedBox(width: 8),
              Flexible(
                child: StudioChip(
                  label: _caption.trim().isEmpty ? 'Add a caption' : 'Caption: $_caption',
                  selected: false,
                  onTap: () async {
                    final t = await studioWrite(context, 'Caption', _caption, max: 22);
                    if (t == null || !mounted) return;
                    setState(() => _caption = t);
                    unawaited(_draw());
                  },
                ),
              ),
            ],
          ),
        ],
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
  FlipStyle _style = FlipStyle.standard;
  int _pageMs = StudioMake.pageMsDefault;
  late final Timer _tick;
  final _clock = Stopwatch()..start();
  // where the book is, in pages: moved on by the time since the last tick
  // at the speed of the moment, so a new speed changes the pace, not the
  // page
  double _pos = 0;
  int _lastMs = 0;
  bool _busy = false;
  List<ui.Image>? _photos;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _tick = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final now = _clock.elapsedMilliseconds;
      _pos += (now - _lastMs) / _pageMs;
      _lastMs = now;
      if (mounted) setState(() {});
    });
  }

  Future<void> _load() async {
    final photos = await StudioMake.photos(widget.prints, maxSide: 800);
    if (!mounted) {
      for (final p in photos) {
        p.dispose();
      }
      return;
    }
    setState(() => _photos = photos);
  }

  @override
  void dispose() {
    _tick.cancel();
    clearStapledTextures();
    for (final p in _photos ?? const <ui.Image>[]) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _make() async {
    setState(() => _busy = true);
    try {
      final work = await StudioMake.flipBook(widget.prints, _paper, pageMs: _pageMs, style: _style);
      await ref.read(studioBookProvider.notifier).add(work);
      if (mounted) await popWithFlash(context, work);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        studioNote(context, "Couldn't make it: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = _photos;
    final seconds = widget.prints.length * _pageMs / 1000;
    // (the very frames the video will have: the same drawing)
    final frames = photos == null
        ? null
        : FlipFrames(photos: photos, paper: _paper, style: _style, pageMs: _pageMs);
    return _MakerScaffold(
      title: 'Flip Book',
      subtitle: '${widget.prints.length} pages',
      body: AspectRatio(
        aspectRatio: 4 / 5,
        child: frames == null
            ? const Center(child: CircularProgressIndicator(color: StudioInk.brass))
            : DecoratedBox(
                decoration: const BoxDecoration(
                  boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 6))],
                ),
                child: ClipRect(child: CustomPaint(painter: _FlipPreview(frames, _pos * _pageMs))),
              ),
      ),
      options: [
        Text(
          'About ${seconds.toStringAsFixed(1)} s',
          textAlign: TextAlign.center,
          style: const TextStyle(color: StudioInk.muted, fontSize: 12),
        ),
        Row(
          children: [
            const SizedBox(width: 64, child: StudioLabel('Speed')),
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
        _Choices<FlipStyle>(
          label: 'Change',
          values: FlipStyle.values,
          name: (f) => f.label,
          value: _style,
          onPick: (f) => setState(() => _style = f),
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

class _FlipPreview extends CustomPainter {
  _FlipPreview(this.frames, this.t);

  final FlipFrames frames;
  final double t;

  @override
  void paint(Canvas canvas, Size size) => frames.paint(canvas, size, t);

  @override
  bool shouldRepaint(_FlipPreview old) => true;
}

/// One photo in its frame: drag to move it, pinch to zoom in. Pops the new
/// framing (Done) or nothing.
class _CropSheet extends StatefulWidget {
  const _CropSheet({required this.photo, required this.aspect, required this.crop});

  final ui.Image photo;
  final double aspect;
  final PhotoCrop crop;

  @override
  State<_CropSheet> createState() => _CropSheetState();
}

class _CropSheetState extends State<_CropSheet> {
  late PhotoCrop _crop = widget.crop;
  double _startZoom = 1;

  void _move(Offset delta, double frameWidth) {
    final img = widget.photo;
    final src = coverSource(img, widget.aspect, _crop);
    // how much of the photo is left over each way to move into
    final spareX = (img.width - src.width) / 2, spareY = (img.height - src.height) / 2;
    final perPixel = src.width / frameWidth; // photo pixels per screen pixel
    setState(
      () => _crop = PhotoCrop(
        // (the photo follows the finger: the frame moves the other way)
        x: spareX <= 0 ? 0 : (_crop.x - delta.dx * perPixel / spareX).clamp(-1.0, 1.0),
        y: spareY <= 0 ? 0 : (_crop.y - delta.dy * perPixel / spareY).clamp(-1.0, 1.0),
        zoom: _crop.zoom,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final frameW = math.min(size.width - 48, (size.height * 0.5) * widget.aspect);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const StudioLabel('Frame the photo'),
            const SizedBox(height: 4),
            const Text(
              'Drag to move it · pinch to zoom',
              style: TextStyle(color: StudioInk.muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: frameW,
              height: frameW / widget.aspect,
              child: GestureDetector(
                onScaleStart: (_) => _startZoom = _crop.zoom,
                onScaleUpdate: (d) {
                  final zoom = (_startZoom * d.scale).clamp(1.0, 4.0);
                  if (zoom != _crop.zoom) _crop = PhotoCrop(x: _crop.x, y: _crop.y, zoom: zoom);
                  _move(d.focalPointDelta, frameW);
                },
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: StudioInk.brass, width: 2),
                    boxShadow: const [
                      BoxShadow(color: Color(0x99000000), blurRadius: 12, offset: Offset(0, 6)),
                    ],
                  ),
                  child: ClipRect(child: CustomPaint(painter: _CropPainter(widget.photo, _crop))),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: _crop.isMiddle ? null : () => setState(() => _crop = PhotoCrop.middle),
                  style: TextButton.styleFrom(foregroundColor: StudioInk.muted),
                  child: const Text('Reset'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _crop),
                  style: FilledButton.styleFrom(
                    backgroundColor: StudioInk.brass,
                    foregroundColor: const Color(0xFF22150B),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.photo, this.crop);

  final ui.Image photo;
  final PhotoCrop crop;

  @override
  void paint(Canvas canvas, Size size) => drawCover(
    canvas,
    photo,
    Offset.zero & size,
    crop: crop,
    paint: Paint()..filterQuality = FilterQuality.medium,
  );

  @override
  bool shouldRepaint(_CropPainter old) => old.crop != crop;
}
