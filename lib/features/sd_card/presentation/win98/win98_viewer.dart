import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../../../core/db/media_repository.dart';
import '../../../../core/providers.dart';
import '../../../cameras/domain/camera_catalog.dart';
import '../../../viewer/presentation/media_actions.dart';
import 'explorer_dialogs.dart';
import 'pixel_icons.dart';
import 'win98_media_player.dart';
import 'win98_widgets.dart';

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
      unawaited(HapticFeedback.selectionClick());
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
    return Win98Scale(
      child: Scaffold(
        backgroundColor: W98.desktop,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Win98Window(
              title: '${item.isVideo ? 'Media Player' : 'Imaging'} - ${item.fileName}',
              icon: PixelIconView(item.isVideo ? PixelIcon.videoFile : PixelIcon.imageFile),
              onClose: () => Navigator.of(context).pop(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        _NavButton(glyph: '◀', onPressed: _index > 0 ? () => _go(-1) : null),
                        const SizedBox(width: 3),
                        _NavButton(glyph: '▶', onPressed: _index < _items.length - 1 ? () => _go(1) : null),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${_index + 1} of ${_items.length}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: W98.text,
                          ),
                        ),
                        Builder(
                          builder: (anchor) => Win98Button(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            onPressed: () => unawaited(shareMedia(anchor, item)),
                            child: const Text('Send To'),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Win98Button(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          onPressed: _delete,
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: path == null
                        ? const Win98Bevel(
                            style: BevelStyle.sunken,
                            color: Colors.black,
                            child: SizedBox.expand(),
                          )
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
                          ),
                  ),
                  if (!item.isVideo) ...[
                    const SizedBox(height: 4),
                    // Full-width trackbar: the long throw makes fine zooming easy.
                    Win98Slider(value: _sliderValue, onChanged: (v) => _zoomTo(_scaleFor(v))),
                    Row(
                      children: [
                        Text('Zoom: ${(_scale * 100).round()}%'),
                        const Spacer(),
                        Win98Button(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          onPressed: _scale > 1.01 ? () => _zoom.value = Matrix4.identity() : null,
                          child: const Text('Reset Zoom'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 3),
                  _StatusBar(item: item),
                ],
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
    final fallback = CameraCatalog.byId(item.cameraId).name;
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

/// Chunky arrow button for the toolbar (big enough for a thumb).
class _NavButton extends StatelessWidget {
  const _NavButton({required this.glyph, this.onPressed});

  final String glyph;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 32,
      child: Win98Button(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        child: Text(glyph, style: W98.text.copyWith(fontSize: 16, height: 1)),
      ),
    );
  }
}
