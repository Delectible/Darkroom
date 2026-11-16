import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../core/db/media_repository.dart';
import '../../../../../core/device/haptics.dart';
import '../../../../../core/providers.dart';
import '../../../../studio/studio_render.dart';
import '../../../application/sd_card_controller.dart';
import '../pixel_icons.dart';
import '../win98_widgets.dart';
import 'photo_room_card.dart';
import 'photo_room_render.dart';

/// Photo Room: a wizard that makes something from the pictures on C:
/// (a collage, a contact sheet, a greeting card, an animated GIF or a booth
/// strip) and files it in C:\My Pictures\Photo Room. Returns true when the
/// folder should open afterwards.
Future<bool?> showPhotoRoom(BuildContext context) => showWin98Window<bool>(
  context,
  title: 'Photo Room Wizard',
  width: 2000,
  avoidKeyboard: false,
  icon: const PixelIconView(PixelIcon.photoRoom),
  builder: (context) => const PhotoRoomWizard(),
);

enum _Step { choose, pick, arrange, saving, done }

class PhotoRoomWizard extends ConsumerStatefulWidget {
  const PhotoRoomWizard({super.key});

  @override
  ConsumerState<PhotoRoomWizard> createState() => _PhotoRoomWizardState();
}

class _PhotoRoomWizardState extends ConsumerState<PhotoRoomWizard> {
  _Step _step = _Step.choose;
  PhotoRoomMake _make = PhotoRoomMake.collage;
  final _picked = <String>[];

  // the options
  Backdrop _back = Backdrop.white;
  bool _thick = false;
  bool _sheet = false;
  StripLook _strip = const StripLook();
  double _speed = 0.77; // 0 slow (2 s a photo) .. 1 fast
  GifSize _gifSize = GifSize.medium;
  GifTransition _transition = GifTransition.fade;
  List<ui.Image>? _gifFrames;
  int _gifLoads = 0;
  CardDraft? _card;
  final _cardBoundary = GlobalKey();
  final _cardEditor = GlobalKey<CardEditorState>();

  // the rendered piece (collage, sheet, strip), redrawn as options change
  ui.Image? _preview;
  int _renders = 0;
  final _photos = <String, ui.Image>{};

  MediaItem? _made;
  String? _error;
  bool _openFolder = true;

  int get _frameMs => (2000 - 1880 * _speed).round();

  @override
  void dispose() {
    for (final p in _photos.values) {
      p.dispose();
    }
    _preview?.dispose();
    for (final f in _gifFrames ?? const <ui.Image>[]) {
      f.dispose();
    }
    super.dispose();
  }

  List<MediaItem> _pictures() => [
    for (final m in ref.watch(darkroomFolderProvider))
      if (!m.isVideo && m.isReady && m.outputPath != null) m,
  ];

  List<MediaItem> _chosen() {
    final all = {for (final m in ref.read(darkroomFolderProvider)) m.id: m};
    return [for (final id in _picked) ?all[id]];
  }

  Future<List<ui.Image>> _load(List<MediaItem> items) async => [
    for (final m in items) _photos[m.id] ??= await loadStudioImage(m.outputPath!, maxSide: 1400),
  ];

  Future<void> _render() async {
    if (_make == PhotoRoomMake.card || _make == PhotoRoomMake.gif) return;
    final ticket = ++_renders;
    final ui.Image image;
    try {
      final items = _chosen();
      final photos = await _load(items);
      image = await switch (_make) {
        PhotoRoomMake.collage when _sheet => renderContactSheet(
          photos,
          [for (final m in items) m.fileName],
          _back,
          DateTime.now(),
        ),
        PhotoRoomMake.collage => renderRoomCollage(photos, _back, thick: _thick),
        _ => renderRoomStrip(photos, _strip, DateTime.now()),
      };
    } catch (e) {
      debugPrint('Photo Room: $e');
      if (mounted) setState(() => _error = "Couldn't draw it: $e");
      return;
    }
    if (!mounted || ticket != _renders) {
      image.dispose();
      return;
    }
    setState(() {
      _preview?.dispose();
      _preview = image;
    });
  }

  void _go(_Step s) {
    unawaited(Haptics.selectionClick());
    setState(() => _step = s);
    if (s == _Step.arrange) {
      if (_make == PhotoRoomMake.card) _card ??= CardDraft(_chosen());
      // (never the last piece's picture while this one draws)
      _preview?.dispose();
      _preview = null;
      unawaited(_render());
      if (_make == PhotoRoomMake.gif) unawaited(_loadGif());
    }
  }

  /// The picked photos as GIF frames, for the preview.
  Future<void> _loadGif() async {
    final ticket = ++_gifLoads;
    final frames = [for (final m in _chosen()) await gifFrameOf(m.outputPath!, 480, 360)];
    if (!mounted || ticket != _gifLoads) {
      for (final f in frames) {
        f.dispose();
      }
      return;
    }
    setState(() {
      for (final f in _gifFrames ?? const <ui.Image>[]) {
        f.dispose();
      }
      _gifFrames = frames;
    });
  }

  void _toggle(MediaItem m) {
    setState(() {
      if (!_picked.remove(m.id)) _picked.add(m.id);
      _card = null;
    });
  }

  bool _isSaving = false;

  Future<void> _save() async {
    // (one save at a time, however fast Save is tapped)
    if (_isSaving) return;
    _isSaving = true;
    try {
      await _saveOnce();
    } finally {
      _isSaving = false;
    }
  }

  Future<void> _saveOnce() async {
    // The card is captured as it is on screen, and its pixels read, before
    // the page changes to Saving (and it with it); the pick's outline off.
    StudioPixels? card;
    if (_make == PhotoRoomMake.card) {
      _cardEditor.currentState?.unpick();
      final onScreen = MediaQuery.devicePixelRatioOf(context);
      await WidgetsBinding.instance.endOfFrame;
      final box = _cardBoundary.currentContext?.findRenderObject();
      if (box is RenderRepaintBoundary && box.hasSize) {
        // (1500 px across; if that keeps coming back scrambled, as it is
        // on screen)
        for (final ratio in [1500 / box.size.width, onScreen]) {
          try {
            card = await drawStudioPixels(() => box.toImage(pixelRatio: ratio));
            break;
          } catch (_) {
            // (said below: the card could not be drawn)
          }
        }
      }
      if (!mounted) return;
    }
    setState(() {
      _step = _Step.saving;
      _error = null;
    });
    try {
      final repo = ref.read(sdCardRepositoryProvider);
      final existing = ref.read(photoRoomFolderProvider);
      final MediaItem made;
      switch (_make) {
        case PhotoRoomMake.gif:
          final items = _chosen();
          final bytes = await encodeGif(
            [for (final m in items) m.outputPath!],
            _frameMs,
            _gifSize,
            transition: _transition,
          );
          final thumb = await loadStudioImage(items.first.outputPath!, maxSide: 600);
          made = await keepOnC(
            repo: repo,
            existing: existing,
            make: _make,
            ext: 'GIF',
            write: (p) => File(p).writeAsBytes(bytes),
            width: thumb.width,
            height: thumb.height,
          );
          thumb.dispose();
        case PhotoRoomMake.card:
          // (the card as it looked, 1500 px across)
          final pixels = card;
          if (pixels == null) throw const StudioScrambled();
          made = await keepOnC(
            repo: repo,
            existing: existing,
            make: _make,
            ext: 'JPG',
            write: (p) => writeStudioPixels(pixels, p),
            width: pixels.width,
            height: pixels.height,
          );
        default:
          final image = _preview;
          if (image == null) throw StateError('Still drawing');
          made = await keepOnC(
            repo: repo,
            existing: existing,
            make: _make,
            ext: 'JPG',
            write: (p) => writeStudioJpeg(image, p),
            width: image.width,
            height: image.height,
          );
      }
      if (!mounted) return;
      unawaited(Haptics.lightImpact());
      setState(() {
        _made = made;
        _step = _Step.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _step = _Step.arrange;
      });
      await showWin98MessageBox(
        context,
        title: 'Photo Room',
        message: 'The picture could not be saved.\n\n$e',
        icon: Win98MessageIcon.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.sizeOf(context);
    // Sized like the explorer's window: the screen less a little desktop
    // round it and the taskbar's height, so it reads as a window on the PC.
    final height = math.min(mq.height - 96, 820.0);
    final pictures = _pictures();
    _picked.removeWhere((id) => !pictures.any((m) => m.id == id));
    final fits = _make.fits(_picked.length);
    final (back, next, nextLabel) = switch (_step) {
      _Step.choose => (null, () => _go(_Step.pick), 'Next >'),
      _Step.pick => (() => _go(_Step.choose), fits ? () => _go(_Step.arrange) : null, 'Next >'),
      _Step.arrange => (() => _go(_Step.pick), () => unawaited(_save()), 'Save'),
      _Step.saving => (null, null, 'Save'),
      _Step.done => (null, () => Navigator.of(context).pop(_openFolder), 'Finish'),
    };
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: switch (_step) {
              _Step.choose => _choose(),
              _Step.pick => _page(
                'Pick your photos',
                'Tap photos in the order you want them. Tap again to leave one out.',
                _pick(pictures),
              ),
              _Step.arrange => _page(
                switch (_make) {
                  PhotoRoomMake.card => 'Arrange your card',
                  PhotoRoomMake.gif => 'Set the speed',
                  _ => 'Choose the look',
                },
                'When it looks right, click Save.',
                _arrange(),
              ),
              _Step.saving => _page('Saving', 'Please wait while Photo Room saves your picture.', _saving()),
              _Step.done => _page('Completing the Photo Room Wizard', 'Your picture is ready.', _done()),
            },
          ),
          Container(height: 1, color: W98.shadow),
          Container(height: 1, color: W98.white),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Win98Button(minWidth: 72, onPressed: back, child: const Text('< Back')),
                const SizedBox(width: 4),
                Win98Button(minWidth: 72, onPressed: next, child: Text(nextLabel)),
                const SizedBox(width: 10),
                Win98Button(
                  minWidth: 72,
                  onPressed: _step == _Step.saving || _step == _Step.done
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- the pages ----

  /// An inside page: a white heading band, then [body].
  Widget _page(String title, String subtitle, Widget body) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ColoredBox(
        color: W98.window,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: W98.text.copyWith(color: W98.windowInk, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: W98.text.copyWith(color: W98.windowInk, fontSize: 11)),
                  ],
                ),
              ),
              const PixelIconView(PixelIcon.photoRoom, size: 32),
            ],
          ),
        ),
      ),
      Container(height: 1, color: W98.shadow),
      Container(height: 1, color: W98.white),
      Expanded(
        child: Padding(padding: const EdgeInsets.fromLTRB(8, 8, 8, 4), child: body),
      ),
    ],
  );

  Widget _choose() => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // the wizard's picture down the side
      Container(
        width: 66,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [W98.navy, W98.titleEnd],
          ),
        ),
        child: const Align(alignment: Alignment(0, -0.75), child: _Snapshots()),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // (a short window, or large fonts: this part scrolls)
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Welcome to the Photo Room Wizard',
                        style: W98.text.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Make something from the pictures in My Pictures. What would you like to make?',
                      ),
                      const SizedBox(height: 6),
                      for (final m in PhotoRoomMake.values)
                        Win98Radio(
                          selected: _make == m,
                          label: m.label,
                          onTap: () => setState(() {
                            _make = m;
                            _card = null;
                          }),
                        ),
                      const SizedBox(height: 4),
                      Win98GroupBox(
                        label: _make.label,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text('${_make.blurb}\n\nTakes ${_make.needs} photos.'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Text('To continue, click Next.', style: W98.text.copyWith(fontSize: 11)),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _pick(List<MediaItem> pictures) {
    if (pictures.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'There are no pictures in C:\\My Pictures\\Darkroom yet.\n\nTransfer some from the SD card first, '
            'then come back.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final n = _picked.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Win98Button(
              onPressed: () => setState(() {
                _picked
                  ..clear()
                  ..addAll(pictures.take(_make.max).map((m) => m.id));
                _card = null;
              }),
              child: const Text('Select All'),
            ),
            const SizedBox(width: 4),
            Win98Button(
              onPressed: n == 0
                  ? null
                  : () => setState(() {
                      _picked.clear();
                      _card = null;
                    }),
              child: const Text('Deselect All'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Win98Bevel(
            style: BevelStyle.sunken,
            color: W98.window,
            padding: const EdgeInsets.all(2),
            child: GridView.builder(
              padding: const EdgeInsets.all(4),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 96,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 0.86,
              ),
              itemCount: pictures.length,
              itemBuilder: (context, i) {
                final m = pictures[i];
                final at = _picked.indexOf(m.id);
                return _Thumb(item: m, order: at < 0 ? null : at + 1, onTap: () => _toggle(m));
              },
            ),
          ),
        ),
        const SizedBox(height: 4),
        Win98Bevel(
          style: BevelStyle.sunken,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(
            '$n of ${pictures.length} picked  ·  takes ${_make.needs}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: W98.text.copyWith(fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _backdrops(List<Backdrop> options) => Wrap(
    spacing: 8,
    children: [
      for (final b in options)
        Win98Radio(
          selected: _back == b,
          label: b.label,
          onTap: () {
            setState(() => _back = b);
            unawaited(_render());
          },
        ),
    ],
  );

  Widget _arrange() {
    switch (_make) {
      case PhotoRoomMake.card:
        return CardEditor(key: _cardEditor, draft: _card!, boundary: _cardBoundary, pictures: _pictures());
      case PhotoRoomMake.gif:
        return _beside(
          Win98Bevel(
            style: BevelStyle.sunken,
            color: W98.dark,
            padding: const EdgeInsets.all(6),
            child: _GifPreview(frames: _gifFrames, frameMs: _frameMs, transition: _transition),
          ),
          [
            Win98GroupBox(
              label: 'Speed',
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Row(
                  children: [
                    const Text('Slow'),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Win98Slider(value: _speed, onChanged: (v) => setState(() => _speed = v)),
                    ),
                    const SizedBox(width: 6),
                    const Text('Fast'),
                  ],
                ),
              ),
            ),
            Win98GroupBox(
              label: 'Change between photos',
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Wrap(
                  spacing: 10,
                  children: [
                    for (final t in GifTransition.values)
                      Win98Radio(
                        selected: _transition == t,
                        label: t.label,
                        onTap: () => setState(() => _transition = t),
                      ),
                  ],
                ),
              ),
            ),
            Win98GroupBox(
              label: 'Size',
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Wrap(
                  spacing: 10,
                  children: [
                    for (final s in GifSize.values)
                      Win98Radio(
                        selected: _gifSize == s,
                        label: '${s.label} (${s.side} × ${(s.side * 3 / 4).round()})',
                        onTap: () => setState(() => _gifSize = s),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      default:
        final p = _preview;
        return _beside(
          Win98Bevel(
            style: BevelStyle.sunken,
            color: W98.shadow,
            padding: const EdgeInsets.all(6),
            child: p == null
                ? const Center(child: Text('Drawing...'))
                // (pinch to look closer)
                : ClipRect(
                    child: InteractiveViewer(
                      maxScale: 6,
                      child: SizedBox.expand(
                        child: RawImage(image: p, fit: BoxFit.contain),
                      ),
                    ),
                  ),
          ),
          [
            if (_error != null) Text(_error!, maxLines: 2, style: W98.text.copyWith(fontSize: 11)),
            if (_make == PhotoRoomMake.strip)
              ..._stripOptions()
            else
              Win98GroupBox(
                label: 'Background',
                child: Padding(padding: const EdgeInsets.all(6), child: _backdrops(Backdrop.values)),
              ),
            if (_make == PhotoRoomMake.collage)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Win98Checkbox(
                        value: _sheet,
                        label: 'Contact sheet look',
                        onChanged: (v) {
                          setState(() => _sheet = v);
                          unawaited(_render());
                        },
                      ),
                    ),
                    Expanded(
                      child: Win98Checkbox(
                        value: _thick,
                        label: 'Wide border',
                        onChanged: _sheet
                            ? null
                            : (v) {
                                setState(() => _thick = v);
                                unawaited(_render());
                              },
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Pinch the picture to look closer.', style: W98.text.copyWith(fontSize: 10)),
            ),
          ],
        );
    }
  }

  /// The preview with its options: under it upright, beside it (scrolling
  /// if need be) when the window is wide.
  Widget _beside(Widget preview, List<Widget> options) => LayoutBuilder(
    builder: (context, box) {
      if (box.maxWidth > box.maxHeight * 1.3) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: preview),
            const SizedBox(width: 8),
            SizedBox(
              width: math.min(300, box.maxWidth * 0.48),
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: options),
              ),
            ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        // (upright: the options take what they need, up to two fifths, and
        // scroll past that on a short screen; the picture gets the rest)
        children: [
          Expanded(flex: 3, child: preview),
          const SizedBox(height: 6),
          Flexible(
            flex: 2,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: options),
            ),
          ),
        ],
      );
    },
  );

  void _restrip(StripLook look) {
    setState(() => _strip = look);
    unawaited(_render());
  }

  /// The doodled strip's options: its fill, caption, a fresh shuffle of
  /// the doodles, and what's shown.
  List<Widget> _stripOptions() => [
    Win98GroupBox(
      label: 'Background',
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final f in StripFill.values)
              GestureDetector(
                onTap: () => _restrip(_strip.copyWith(fill: f)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Win98Bevel(
                      style: _strip.fill == f ? BevelStyle.pressed : BevelStyle.sunken,
                      padding: const EdgeInsets.all(2),
                      child: Container(
                        width: 18,
                        height: 14,
                        decoration: BoxDecoration(
                          color: f.color,
                          border: _strip.fill == f ? Border.all(color: W98.windowInk) : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(f.label, style: W98.text.copyWith(fontSize: 11)),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
    const SizedBox(height: 4),
    // the lettering's colour, its own (Auto: one to suit the background)
    Row(
      children: [
        Text('Text:', style: W98.text.copyWith(fontSize: 11)),
        const SizedBox(width: 6),
        Expanded(
          child: Wrap(
            spacing: 3,
            runSpacing: 3,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final k in StripInk.values)
                Tooltip(
                  message: k.label,
                  child: GestureDetector(
                    onTap: () => _restrip(_strip.copyWith(ink: k)),
                    child: Win98Bevel(
                      style: _strip.ink == k ? BevelStyle.pressed : BevelStyle.sunken,
                      padding: const EdgeInsets.all(2),
                      child: Container(
                        width: k.color == null ? 32 : 18,
                        height: 14,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: k.color,
                          border: _strip.ink == k ? Border.all(color: W98.windowInk) : null,
                        ),
                        child: k.color == null
                            ? Text('Auto', style: W98.text.copyWith(fontSize: 10, height: 1))
                            : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
    const SizedBox(height: 4),
    Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        Win98Button(
          onPressed: () async {
            final t = await askWin98Text(context, 'Caption', _strip.caption, max: 24);
            if (t != null) _restrip(_strip.copyWith(caption: t));
          },
          child: const Text('Caption...'),
        ),
        Win98Button(
          onPressed: _strip.doodles
              ? () {
                  unawaited(Haptics.selectionClick());
                  _restrip(_strip.copyWith(seed: _strip.seed + 1));
                }
              : null,
          child: const Text('Shuffle doodles'),
        ),
      ],
    ),
    const SizedBox(height: 2),
    Row(
      children: [
        Expanded(
          child: Win98Checkbox(
            value: _strip.doodles,
            label: 'Doodles',
            onChanged: (v) => _restrip(_strip.copyWith(doodles: v)),
          ),
        ),
        Expanded(
          child: Win98Checkbox(
            value: _strip.crooked,
            label: 'Crooked',
            onChanged: (v) => _restrip(_strip.copyWith(crooked: v)),
          ),
        ),
        Expanded(
          child: Win98Checkbox(
            value: _strip.date,
            label: 'Date',
            onChanged: (v) => _restrip(_strip.copyWith(date: v)),
          ),
        ),
      ],
    ),
  ];

  Widget _saving() => const Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [Text('Saving to C:\\My Pictures\\Photo Room...'), SizedBox(height: 10), _Busy()],
  );

  Widget _done() {
    final m = _made!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Win98Bevel(
            style: BevelStyle.sunken,
            color: W98.shadow,
            padding: const EdgeInsets.all(6),
            child: Image.file(File(m.outputPath!), fit: BoxFit.contain),
          ),
        ),
        const SizedBox(height: 8),
        Text('You have successfully made ${m.fileName}.'),
        const SizedBox(height: 4),
        Text(
          'It is saved in C:\\My Pictures\\Photo Room and copied to your photo library (album Darkroom).',
          style: W98.text.copyWith(fontSize: 11),
        ),
        const SizedBox(height: 6),
        Win98Checkbox(
          value: _openFolder,
          label: 'Open the Photo Room folder',
          onChanged: (v) => setState(() => _openFolder = v),
        ),
        const SizedBox(height: 4),
        Text('To close this wizard, click Finish.', style: W98.text.copyWith(fontSize: 11)),
      ],
    );
  }
}

/// A picture in the picker: picked ones go navy, with their number.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.item, required this.order, required this.onTap});

  final MediaItem item;
  final int? order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final picked = order != null;
    final path = item.thumbPath ?? item.outputPath;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        unawaited(Haptics.selectionClick());
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(3),
        color: picked ? W98.navy : null,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(border: Border.all(color: W98.shadow)),
                    child: path == null
                        ? ColoredBox(color: W98.face)
                        : Image.file(File(path), fit: BoxFit.cover, cacheWidth: 200, gaplessPlayback: true),
                  ),
                  if (picked) ...[
                    // the selection's blue wash, like a picked icon
                    ColoredBox(color: W98.navy.withValues(alpha: 0.35)),
                    Positioned(
                      left: 2,
                      top: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        color: const Color(0xFFFFFF00),
                        child: Text('$order', style: W98.text.copyWith(color: const Color(0xFF000000))),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: W98.text.copyWith(fontSize: 10, color: picked ? W98.selectInk : W98.windowInk),
            ),
          ],
        ),
      ),
    );
  }
}

/// The GIF as it'll play: the photos one after another at [frameMs], each
/// change in [transition] (the pace changes with the slider, not the frame).
class _GifPreview extends StatefulWidget {
  const _GifPreview({required this.frames, required this.frameMs, required this.transition});

  /// The photos as GIF frames (null while they load).
  final List<ui.Image>? frames;
  final int frameMs;
  final GifTransition transition;

  @override
  State<_GifPreview> createState() => _GifPreviewState();
}

class _GifPreviewState extends State<_GifPreview> {
  late final Timer _tick;
  final _clock = Stopwatch()..start();
  double _pos = 0;
  int _last = 0;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 30), (_) {
      final now = _clock.elapsedMilliseconds;
      _pos += (now - _last) / widget.frameMs;
      _last = now;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frames = widget.frames;
    if (frames == null || frames.isEmpty) return const Center(child: Text('Loading...'));
    final whole = _pos.floor();
    final into = (_pos - whole) * widget.frameMs;
    final change = transitionMs(widget.transition, widget.frameMs);
    final hold = widget.frameMs - change;
    final a = frames[whole % frames.length];
    final b = frames[(whole + 1) % frames.length];
    final t = into <= hold || change == 0 ? 0.0 : (into - hold) / change;
    return Center(
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: ClipRect(child: CustomPaint(painter: _GifPainter(a, b, t, widget.transition))),
      ),
    );
  }
}

class _GifPainter extends CustomPainter {
  _GifPainter(this.a, this.b, this.t, this.transition);

  final ui.Image a, b;
  final double t;
  final GifTransition transition;

  @override
  void paint(Canvas canvas, Size size) => paintGifChange(canvas, size, a, b, t, transition);

  @override
  bool shouldRepaint(_GifPainter old) => true;
}

/// The 98 progress bar, filling and starting over while it works.
class _Busy extends StatefulWidget {
  const _Busy();

  @override
  State<_Busy> createState() => _BusyState();
}

class _BusyState extends State<_Busy> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) => Win98ProgressBar(value: _c.value),
  );
}

/// The wizard's side picture: two snapshots, one tilted.
class _Snapshots extends StatelessWidget {
  const _Snapshots();

  @override
  Widget build(BuildContext context) {
    Widget snap(List<Color> colors) => Container(
      width: 46,
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: W98.white,
        boxShadow: const [BoxShadow(color: Color(0xFF000000), offset: Offset(2, 2))],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        ),
      ),
    );
    return SizedBox(
      width: 60,
      height: 76,
      child: Stack(
        children: [
          Positioned(
            left: 2,
            top: 0,
            child: snap(const [Color(0xFF7AA0C4), Color(0xFFE0B48A), Color(0xFF3F4A3A)]),
          ),
          Positioned(
            left: 10,
            top: 32,
            child: Transform.rotate(
              angle: -0.14,
              child: snap(const [Color(0xFFF2D4A4), Color(0xFFC4685A), Color(0xFF4A2A30)]),
            ),
          ),
        ],
      ),
    );
  }
}
