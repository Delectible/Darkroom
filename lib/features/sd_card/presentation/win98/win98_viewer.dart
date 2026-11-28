import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../../../core/db/media_repository.dart';
import '../../../../core/db/favourites.dart';
import '../../../../core/diagnostics/sample_feed.dart';
import '../../../../core/providers.dart';
import '../../../cameras/domain/camera_catalog.dart';
import '../../../viewer/presentation/media_actions.dart';
import '../../application/sd_card_controller.dart';
import 'explorer_dialogs.dart';
import 'pixel_icons.dart';
import 'win98_media_player.dart';
import 'win98_display.dart';
import 'win98_widgets.dart';
import '../../../../core/device/haptics.dart';

/// "Imaging" / "Media Player"-style window for files on Local Disk (C:).
/// ◀ ▶ flip through the folder in its current sort order (no swiping, like
/// the real thing); pictures zoom with the trackbar or a pinch.
class Win98ViewerScreen extends ConsumerStatefulWidget {
  const Win98ViewerScreen({super.key, required this.items, required this.initialIndex});

  final List<MediaItem> items;
  final int initialIndex;

  @override
  ConsumerState<Win98ViewerScreen> createState() => _Win98ViewerScreenState();
}

class _Win98ViewerScreenState extends ConsumerState<Win98ViewerScreen> {
  static const _maxZoom = 6.0;

  late final List<MediaItem> _items = [...widget.items];
  late int _index = widget.initialIndex.clamp(0, _items.length - 1);
  final _zoom = TransformationController();
  Size _viewport = Size.zero;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(_onZoom);
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  void _onZoom() => setState(() {});

  MediaItem get _item => _items[_index];

  double get _scale => _zoom.value.getMaxScaleOnAxis();

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= _items.length) {
      unawaited(Haptics.selectionClick());
      return;
    }
    setState(() {
      _index = next;
      _zoom.value = Matrix4.identity();
    });
  }

  /// Zooms to [scale] about the centre of what is currently on screen.
  void _zoomTo(double scale) {
    final s = scale.clamp(1.0, _maxZoom);
    final centre = _viewport.center(Offset.zero);
    final scene = _zoom.toScene(centre);
    var m = Matrix4.identity()
      ..translateByDouble(centre.dx, centre.dy, 0, 1)
      ..scaleByDouble(s, s, 1, 1)
      ..translateByDouble(-scene.dx, -scene.dy, 0, 1);
    // Keep the picture covering the viewport (no panning past its edges).
    final tx = m.getTranslation();
    final maxX = 0.0, minX = _viewport.width * (1 - s);
    final maxY = 0.0, minY = _viewport.height * (1 - s);
    m = Matrix4.identity()
      ..translateByDouble(tx.x.clamp(minX, maxX), tx.y.clamp(minY, maxY), 0, 1)
      ..scaleByDouble(s, s, 1, 1);
    _zoom.value = m;
  }

  // Trackbar position is logarithmic, like a zoom lens.
  double get _sliderValue => math.log(_scale) / math.log(_maxZoom);
  double _scaleFor(double v) => math.pow(_maxZoom, v).toDouble();

  Future<void> _rename() async {
    final renamed = await renameWithDialog(context, ref, _item);
    if (renamed == null || !mounted) return;
    setState(() => _items[_index] = renamed);
  }

  /// Opening a C: file takes its blue dot off the C: tab.
  void _see() {
    final item = _item;
    if (!item.onSdCard) {
      Future.microtask(() => ref.read(cSeenProvider.notifier).see(item.id));
    }
  }

  Future<void> _delete() async {
    final r = await win98Box(
      context,
      'Confirm File Delete',
      "Are you sure you want to delete '${_item.fileName}'?\n\nThe copy in your phone's photo library is not affected.",
      icon: Win98MessageIcon.question,
      buttons: const ['Yes', 'No'],
    );
    if (r != 0) return;
    await deleteMedia(ref.read(sdCardRepositoryProvider), _item);
    if (!mounted) return;
    setState(() {
      _items.removeAt(_index);
      if (_index >= _items.length) _index = _items.length - 1;
      _zoom.value = Matrix4.identity();
    });
    if (_items.isEmpty) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final item = _item;
    final path = item.outputPath;
    _see();
    final actions = <Widget>[
      Builder(
        builder: (anchor) => Win98Button(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          onPressed: () => unawaited(shareMedia(anchor, item)),
          child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Send')),
        ),
      ),
      Win98Button(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        onPressed: _rename,
        child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Rename')),
      ),
      Win98Button(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        onPressed: _delete,
        child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Delete')),
      ),
      Win98Button(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        toggled: ref.watch(favouritesProvider).contains(item.id),
        onPressed: () => ref.read(favouritesProvider.notifier).toggle(item.id),
        child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Favourite')),
      ),
      if (ref.watch(sampleFeedButtonProvider) && !item.isVideo && item.outputPath != null) ...[
        Win98Button(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          onPressed: () {
            final on = ref.read(sampleFeedProvider) == item.outputPath;
            ref.read(sampleFeedProvider.notifier).use(on ? null : item.outputPath);
          },
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(ref.watch(sampleFeedProvider) == item.outputPath ? 'Unfeed' : 'Feed'),
          ),
        ),
      ],
    ];
    final picture = path == null
        ? const Win98Bevel(style: BevelStyle.sunken, color: Colors.black, child: SizedBox.expand())
        : item.isVideo
        ? Win98MediaPlayer(
            key: ValueKey(item.id),
            path: path,
            onPrevious: _index > 0 ? () => _go(-1) : null,
            onNext: _index < _items.length - 1 ? () => _go(1) : null,
          )
        : Win98Bevel(
            style: BevelStyle.sunken,
            color: Colors.black,
            padding: const EdgeInsets.all(2),
            child: LayoutBuilder(
              builder: (context, box) {
                _viewport = box.biggest;
                return ClipRect(
                  child: InteractiveViewer(
                    key: ValueKey(item.id),
                    transformationController: _zoom,
                    maxScale: _maxZoom,
                    child: SizedBox.expand(
                      child: Image.file(
                        File(path),
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                );
              },
            ),
          );
    final zoomLabel = Text('Zoom: ${(_scale * 100).round()}%', maxLines: 1, softWrap: false);
    final reset = Win98Button(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      onPressed: _scale > 1.01 ? () => _zoom.value = Matrix4.identity() : null,
      child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Reset Zoom')),
    );
    // (as well as the title bar's ×: in easy reach of a thumb)
    final close = Win98Button(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Close'),
    );
    final previous = _index > 0 ? () => _go(-1) : null;
    final next = _index < _items.length - 1 ? () => _go(1) : null;
    final position = '${_index + 1} of ${_items.length}';
    // (Imaging is part of the desktop too: the resolution's pixels)
    return ValueListenableBuilder<Win98Display>(
      valueListenable: Win98Display.current,
      builder: (context, d, child) => Win98Pixels(pixel: d.res.pixel, child: child!),
      child: Win98Scale(
        child: Scaffold(
          backgroundColor: W98.desktop,
          body: DefaultTextStyle(
            style: W98.text,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Win98Window(
                title: '${item.isVideo ? 'Media Player' : 'Imaging'} - ${item.fileName}',
                icon: PixelIconView(item.isVideo ? PixelIcon.videoFile : PixelIcon.imageFile),
                onClose: () => Navigator.of(context).pop(),
                // Landscape: the controls in columns down both sides, so the
                // picture gets the full height (portrait: rows above and below).
                child: LayoutBuilder(
                  builder: (context, box) {
                    if (box.maxWidth > box.maxHeight * 1.25) {
                      return _SideLayout(
                        previous: previous,
                        next: next,
                        position: position,
                        actions: actions,
                        picture: picture,
                        zoom: item.isVideo
                            ? null
                            : (
                                label: zoomLabel,
                                slider: Win98Slider(
                                  value: _sliderValue,
                                  onChanged: (v) => _zoomTo(_scaleFor(v)),
                                ),
                                reset: reset,
                              ),
                        close: close,
                        status: _StatusBar(item: item),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: _Toolbar(
                            previous: previous,
                            next: next,
                            position: position,
                            actions: actions,
                          ),
                        ),
                        Expanded(child: picture),
                        if (!item.isVideo) ...[
                          const SizedBox(height: 4),
                          // Full-width trackbar: the long throw makes fine zooming easy.
                          Win98Slider(value: _sliderValue, onChanged: (v) => _zoomTo(_scaleFor(v))),
                        ] else
                          const SizedBox(height: 4),
                        Row(
                          children: [
                            if (!item.isVideo) zoomLabel,
                            const Spacer(),
                            if (!item.isVideo) ...[reset, const SizedBox(width: 6)],
                            close,
                          ],
                        ),
                        const SizedBox(height: 3),
                        _StatusBar(item: item),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Size, length and the camera that took it (read from the file's EXIF;
/// older files without it fall back to the catalog).
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.item});

  final MediaItem item;

  static final _cache = <String, String?>{};

  static Future<String?> _cameraFromExif(MediaItem item) async {
    final path = item.outputPath;
    if (item.isVideo || path == null) return null;
    if (_cache.containsKey(item.id)) return _cache[item.id];
    String? model;
    try {
      final exif = img.decodeJpgExif(await File(path).readAsBytes());
      model = exif?.imageIfd.model?.trim();
      if (model != null && model.isEmpty) model = null;
    } catch (_) {
      model = null;
    }
    return _cache[item.id] = model;
  }

  @override
  Widget build(BuildContext context) {
    final fallback = CameraCatalog.isPhotoRoom(item.cameraId)
        ? 'Photo Room'
        : CameraCatalog.byId(item.cameraId).name;
    return FutureBuilder<String?>(
      key: ValueKey(item.id),
      future: _cameraFromExif(item),
      builder: (context, snap) {
        final camera = snap.data ?? fallback;
        return Row(
          children: [
            Expanded(
              flex: 3,
              child: Win98Bevel(
                style: BevelStyle.shallow,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  '${item.width ?? '?'} x ${item.height ?? '?'}   ${formatBytes(item.bytes)}'
                  '${item.isVideo ? '   ${formatDuration(item.durationMs)}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              flex: 3,
              child: Win98Bevel(
                style: BevelStyle.shallow,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text('Camera: $camera', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The viewer's toolbar. Wide enough (landscape): the arrows, the count
/// and the actions in one row. Otherwise (portrait, large fonts, 640 x 480)
/// the arrows and count on top and the actions in a row of their own
/// underneath (each sized to its label), each a full-height button (their labels shrink a little if
/// they must, never the buttons).
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.previous, required this.next, required this.position, required this.actions});

  final VoidCallback? previous, next;
  final String position;
  final List<Widget> actions;

  /// The actions' labels at full size, in a row (for the one-row test).
  static double _labelsWidth(BuildContext context, List<Widget> actions) {
    var w = 0.0;
    final scaler = MediaQuery.textScalerOf(context);
    final style = DefaultTextStyle.of(context).style;
    const labels = ['Send', 'Rename', 'Delete', 'Favourite', 'Unfeed'];
    for (final label in labels.take(actions.length)) {
      final tp = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      w += tp.width + 24; // the button's padding and bevel
    }
    return w + 3 * (actions.length - 1);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final arrows = [
        _NavButton(glyph: Win98Glyph.left, onPressed: previous),
        const SizedBox(width: 3),
        _NavButton(glyph: Win98Glyph.right, onPressed: next),
        const SizedBox(width: 8),
        Text(position, maxLines: 1, softWrap: false),
      ];
      final count = TextPainter(
        text: TextSpan(text: position, style: DefaultTextStyle.of(context).style),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final oneRow = 46 * 2 + 3 + 8 + count.width + 12 + _labelsWidth(context, actions) <= box.maxWidth;
      if (oneRow) {
        return Row(
          children: [
            ...arrows,
            const Spacer(),
            for (final (i, a) in actions.indexed) ...[if (i > 0) const SizedBox(width: 3), a],
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: arrows),
          const SizedBox(height: 4),
          Row(
            children: [
              // (each as wide as its label needs: Favourite gets the most)
              for (final (i, a) in actions.indexed) ...[
                if (i > 0) const SizedBox(width: 3),
                Expanded(flex: const [4, 6, 6, 9, 6][i.clamp(0, 4)] + 3, child: a),
              ],
            ],
          ),
        ],
      );
    },
  );
}

/// The landscape viewer: arrows, count and actions in a column on the
/// left, the zoom (a tall trackbar), Reset and Close on the right, the
/// picture the full height between them, the status bar underneath.
class _SideLayout extends StatelessWidget {
  const _SideLayout({
    required this.previous,
    required this.next,
    required this.position,
    required this.actions,
    required this.picture,
    required this.zoom,
    required this.close,
    required this.status,
  });

  final VoidCallback? previous, next;
  final String position;
  final List<Widget> actions;
  final Widget picture;
  final ({Widget label, Widget slider, Widget reset})? zoom;
  final Widget close;
  final Widget status;

  @override
  Widget build(BuildContext context) {
    // as wide as the longest label needs (large fonts, 640 x 480 included)
    final tp = TextPainter(
      text: TextSpan(text: 'Reset Zoom', style: DefaultTextStyle.of(context).style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final side = math.max(46 * 2 + 3.0, tp.width + 24);
    final z = zoom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 3),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: side,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _NavButton(glyph: Win98Glyph.left, onPressed: previous),
                          _NavButton(glyph: Win98Glyph.right, onPressed: next),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(position, textAlign: TextAlign.center, maxLines: 1),
                      const SizedBox(height: 6),
                      for (final (i, a) in actions.indexed) ...[if (i > 0) const SizedBox(height: 3), a],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(child: picture),
              const SizedBox(width: 6),
              SizedBox(
                width: side,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (z != null) ...[
                      Center(child: z.label),
                      const SizedBox(height: 4),
                      // the trackbar stood on end: up zooms in
                      Expanded(child: RotatedBox(quarterTurns: 3, child: z.slider)),
                      const SizedBox(height: 4),
                      z.reset,
                      const SizedBox(height: 3),
                    ] else
                      const Spacer(),
                    close,
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        status,
      ],
    );
  }
}

/// Chunky arrow button for the toolbar (big enough for a thumb).
class _NavButton extends StatelessWidget {
  const _NavButton({required this.glyph, this.onPressed});

  final Win98Glyph glyph;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 32,
      child: Win98Button(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        child: Win98GlyphView(glyph, dot: 2, color: onPressed == null ? W98.shadow : W98.ink),
      ),
    );
  }
}
