import 'dart:async';
import 'dart:io';

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/note_box.dart';
import '../../../core/device/device_memory.dart';
import '../../../core/db/media_repository.dart';
import '../../../core/providers.dart';
import '../../cameras/domain/camera_catalog.dart';
import '../../viewer/presentation/media_actions.dart';
import '../../viewer/presentation/zoomable.dart';
import '../../../core/processing/instant_frame.dart';
import 'instant_print.dart';
import 'print_frames.dart';
import '../../studio/studio_screen.dart';
import '../../studio/studio_store.dart';
import '../application/sample_prints.dart';
import '../../camera/application/camera_ui_state.dart';
import '../../../core/device/haptics.dart';
import '../../../core/device/upright.dart';
import '../../../core/processing/paper_wear.dart';

/// Inspecting prints on a dark light-table: swipe between them, pinch to
/// look closer, Save copies one to the phone's photo library.
class PrintViewerScreen extends ConsumerStatefulWidget {
  const PrintViewerScreen({super.key, required this.items, required this.initialIndex, this.originOf});

  final List<MediaItem> items;
  final int initialIndex;

  /// Where a print sits on the board (global), so the viewer can lift it
  /// off and put it back there; null when it isn't on screen.
  final PrintSpot? Function(String id)? originOf;

  /// Held up in front of the corkboard: the board stays behind, dimmed.
  /// With [originOf], the print zooms up from its spot on the board and the
  /// rest fades in round it (back the same way); else the page fades in.
  static Route<void> route(List<MediaItem> items, int index, {PrintSpot? Function(String id)? originOf}) =>
      PageRouteBuilder<void>(
        settings: UprightApp.landscape,
        opaque: false,
        transitionDuration: Duration(milliseconds: originOf == null ? 260 : 340),
        reverseTransitionDuration: Duration(milliseconds: originOf == null ? 200 : 280),
        pageBuilder: (_, _, _) => UprightPage(
          child: PrintViewerScreen(items: items, initialIndex: index < 0 ? 0 : index, originOf: originOf),
        ),
        transitionsBuilder: (context, a, _, child) => originOf != null
            ? child
            : FadeTransition(
                opacity: a,
                child: ScaleTransition(
                  scale: Tween(
                    begin: 0.96,
                    end: 1.0,
                  ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(a),
                  child: child,
                ),
              ),
      );

  @override
  ConsumerState<PrintViewerScreen> createState() => _PrintViewerScreenState();
}

class _PrintViewerScreenState extends ConsumerState<PrintViewerScreen> {
  late final List<String> _ids = widget.items.map((m) => m.id).toList();
  late int _index = widget.initialIndex.clamp(0, _ids.length - 1);
  late final PageController _pages = PageController(initialPage: _index);
  final _printKeys = <String, GlobalKey>{};
  bool _saving = false;
  Animation<double>? _route;

  /// The frames tray is open (print_frames.dart).
  bool _framing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The pager clips again once the print has landed (and stops as it
    // leaves).
    final route = ModalRoute.of(context)?.animation;
    if (route == _route || widget.originOf == null) return;
    _route?.removeStatusListener(_flown);
    _route = route?..addStatusListener(_flown);
  }

  void _flown(AnimationStatus _) {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _route?.removeStatusListener(_flown);
    _pages.dispose();
    super.dispose();
  }

  /// Saved, but its copy isn't on the phone now (PrefKeys.galleryGone).
  bool _gone(MediaItem item) => item.isSaved && (_goneIds?.contains(item.id) ?? false);

  List<String>? get _goneIds {
    try {
      return ref.read(sharedPrefsProvider).getStringList(PrefKeys.galleryGone);
    } catch (_) {
      return null; // (tests: no prefs)
    }
  }

  Future<void> _save(MediaItem item) async {
    if (_saving || (item.isSaved && !_gone(item))) return;
    setState(() => _saving = true);
    final again = _gone(item);
    final err = await keepMedia(ref.read(filmRepositoryProvider), item, album: filmAlbum);
    if (err == null && again) {
      await ref.read(sharedPrefsProvider).setStringList(PrefKeys.galleryGone, [
        ...?_goneIds?.where((id) => id != item.id),
      ]);
    }
    if (!mounted) return;
    setState(() => _saving = false);
    unawaited(Haptics.lightImpact());
    Notes.show(err ?? 'Saved to your photo library ($filmAlbum).');
  }

  /// Instant prints: write (or change) the note on the bottom border.
  Future<void> _writeNote(MediaItem item) async {
    final text = TextEditingController(text: item.note ?? '');
    // The box is the print's own off-white paper with felt-tip ink, so the
    // writing reads the same in light and dark mode.
    const paper = InstantFrame.paper, ink = InstantFrame.ink;
    final note = await showDialog<String>(
      context: context,
      builder: (context) => Theme(
        data: ThemeData.light(useMaterial3: true).copyWith(
          colorScheme: const ColorScheme.light(
            primary: ink,
            onPrimary: paper,
            surface: paper,
            onSurface: ink,
          ),
          textSelectionTheme: TextSelectionThemeData(
            cursorColor: ink,
            selectionColor: ink.withValues(alpha: 0.2),
            selectionHandleColor: ink,
          ),
        ),
        child: AlertDialog(
          backgroundColor: paper,
          title: const Text('Write on the print', style: TextStyle(color: ink)),
          content: TextField(
            controller: text,
            autofocus: true,
            maxLength: InstantFrame.maxNoteLength,
            textCapitalization: TextCapitalization.sentences,
            style: InstantFrame.noteStyle(260).copyWith(fontSize: 26),
            decoration: InputDecoration(
              hintText: 'summer \'26, the lake…',
              hintStyle: InstantFrame.noteStyle(260)
                  .copyWith(fontSize: 26, color: ink.withValues(alpha: 0.3)),
              counterStyle: TextStyle(color: ink.withValues(alpha: 0.6)),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ink.withValues(alpha: 0.4))),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: ink, width: 1.6)),
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, text.text), child: const Text('Done')),
          ],
        ),
      ),
    );
    text.dispose();
    if (note == null || !mounted) return;
    final repo = ref.read(filmRepositoryProvider);
    if (note == (item.note ?? '')) return;
    await repo.setNote(item.id, note);
    // Already in the photo library: that copy can't be changed, so offer a
    // new one with the note on it.
    if (!item.isSaved || !mounted) return;
    final again = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save a copy with the note?'),
        content: const Text(
          'This print is already in your photo library without it. A new copy is added; the old one stays.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save copy')),
        ],
      ),
    );
    if (again != true || !mounted) return;
    final fresh = await repo.byId(item.id);
    if (fresh == null || !mounted) return;
    final err = await saveToGallery(fresh, album: filmAlbum);
    if (!mounted) return;
    unawaited(Haptics.lightImpact());
    Notes.show(err ?? 'Saved a copy with the note ($filmAlbum).');
  }

  Future<void> _delete(MediaItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Throw this print away?'),
        content: Text(
          SamplePrints.isSample(item)
              ? "It's a sample print: it will be removed from the corkboard."
              : item.isSaved
              ? "It will be removed from the corkboard. The copy in your photo library stays."
              : 'It has not been saved to your photo library. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Throw away')),
        ],
      ),
    );
    if (ok != true) return;
    await deleteMedia(ref.read(filmRepositoryProvider), item);
    if (!mounted) return;
    setState(() {
      _ids.remove(item.id);
      if (_index >= _ids.length) _index = _ids.length - 1;
    });
    if (_ids.isEmpty) Navigator.of(context).pop();
  }

  /// The frames tray for [item]: frames for a 35 mm print, papers for an
  /// instant one, each a small preview of the print itself.
  Widget _framesFor(MediaItem item, bool instant, Map<String, String> frames) {
    final thumb = item.thumbPath;
    final preview = thumb == null
        ? const ColoredBox(color: Colors.black26)
        : Image.file(File(thumb), fit: BoxFit.cover, cacheWidth: 160);
    void pick(String name) {
      unawaited(Haptics.selectionClick());
      ref.read(printFramesProvider.notifier).set(item.id, name);
    }

    if (instant) {
      return FramePicker(
        options: [for (final f in InstantStyle.values) (f.name, f.label)],
        current: PrintFrames.styleOf(frames, item.id).name,
        onPick: pick,
        swatch: (name) => InstantPrint(style: InstantStyle.named(name)!, shadow: false, picture: preview),
      );
    }
    return FramePicker(
      options: [for (final f in PrintFrame.values) (f.name, f.label)],
      current: PrintFrames.frameOf(frames, item.id).name,
      onPick: pick,
      swatch: (name) => AspectRatio(
        aspectRatio: (item.width ?? 3) / (item.height ?? 2),
        child: FramedPrint(frame: PrintFrame.values.byName(name), photo: preview, shadow: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Live rows (saved state changes while we look).
    final live = {for (final m in ref.watch(filmItemsProvider).value ?? widget.items) m.id: m};
    final items = [for (final id in _ids) live[id] ?? widget.items.firstWhere((m) => m.id == id)];
    if (items.isEmpty) return const SizedBox.shrink();
    final item = items[_index];
    final spec = CameraCatalog.byId(item.cameraId);
    // Sideways the buttons stand in a column on the right, so the print
    // gets the height.
    final mq = MediaQuery.of(context);
    final landscape = mq.size.width > mq.size.height;
    // Lifted off the board: the print flies, everything else fades round it.
    final route = ModalRoute.of(context)?.animation;
    final fly = widget.originOf == null || route == null
        ? null
        : CurvedAnimation(parent: route, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    Widget faded(Widget child) => fly == null
        ? child
        : FadeTransition(
            opacity: CurvedAnimation(parent: route!, curve: Curves.easeOut, reverseCurve: Curves.easeIn),
            child: child,
          );
    final actions = _ActionBar(
      vertical: landscape,
      onWrite: spec.isInstant ? () => _writeNote(item) : null,
      saved: item.isSaved,
      gone: _gone(item),
      sample: SamplePrints.isSample(item),
      saving: _saving,
      onSave: () => _save(item),
      onDelete: () => _delete(item),
      onShare: (anchor) => shareMedia(anchor, item),
      framing: _framing,
      onFrame: () => setState(() => _framing = !_framing),
      onStudio: () {
        // (off the board to the Studio: its spot shows "In studio")
        unawaited(ref.read(studioProvider.notifier).add(item.id));
        Navigator.of(context).pop();
      },
    );
    final frames = ref.watch(printFramesProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // The corkboard behind, dimmed (a little more towards the edges).
          Positioned.fill(
            child: faded(
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(radius: 0.9, colors: [Color(0xB3100D0B), Color(0xE6100D0B)]),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      faded(
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back, color: Colors.white70),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.fileName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      '${spec.name} · ${MaterialLocalizations.of(context).formatMediumDate(item.capturedAt)}',
                                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${_index + 1} / ${items.length}',
                                style: const TextStyle(color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: PhotoPager(
                          controller: _pages,
                          clip: fly == null || fly.isCompleted,
                          itemCount: items.length,
                          onPageChanged: (i) => setState(() => _index = i),
                          // A tap off the print (on the dimmed board) puts it down;
                          // so does a swipe up or down.
                          onTap: (at) {
                            // (it fires late, after the double-tap window: by
                            // then a tap on the note may have opened the write
                            // box, whose keyboard moved the print; never close it)
                            if (ModalRoute.of(context)?.isCurrent != true) return;
                            final box =
                                _printKeys[items[_index].id]?.currentContext?.findRenderObject()
                                    as RenderBox?;
                            final on =
                                box != null && (Offset.zero & box.size).contains(box.globalToLocal(at));
                            if (!on) unawaited(Navigator.of(context).maybePop());
                          },
                          onDismiss: () => Navigator.of(context).maybePop(),
                          itemBuilder: (context, i) => _Print(
                            printKey: _printKeys.putIfAbsent(items[i].id, GlobalKey.new),
                            item: items[i],
                            frames: frames,
                            onWrite: () => _writeNote(items[i]),
                            fly: i == _index ? fly : null,
                            current: i == _index,
                            origin: () => widget.originOf?.call(items[i].id),
                          ),
                        ),
                      ),
                      // The frames for the print in view: a tap puts one on.
                      faded(
                        AnimatedSize(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          child: _framing
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 8, bottom: 6),
                                  child: _framesFor(item, spec.isInstant, frames),
                                )
                              : const SizedBox(width: double.infinity),
                        ),
                      ),
                      if (!landscape) faded(actions),
                    ],
                  ),
                ),
                if (landscape) faded(actions),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Print extends StatelessWidget {
  const _Print({
    required this.printKey,
    required this.item,
    required this.frames,
    required this.onWrite,
    required this.current,
    this.fly,
    this.origin,
  });

  /// The print in view (only it ever decodes at full size, when zoomed).
  final bool current;

  /// On the print itself (taps off it put it down: see [PhotoPager.onTap]).
  final GlobalKey printKey;
  final MediaItem item;

  /// Each print's chosen frame (printFramesProvider).
  final Map<String, String> frames;
  final VoidCallback onWrite;

  /// The route's progress, while this print is lifted off the board (and
  /// put back) from [origin].
  final Animation<double>? fly;
  final PrintSpot? Function()? origin;

  Widget _held(Widget print) => Center(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: KeyedSubtree(
        key: printKey,
        child: fly == null ? print : _FlyFrom(progress: fly!, origin: origin!, child: print),
      ),
    ),
  );

  /// The photo; until it has decoded (a big print takes a moment the
  /// first time), the board's small copy of it, already in memory.
  ///
  /// Decoded at the screen's size (a full 8192 px print is ~180 MB once
  /// decoded, ten times what the screen can show), and at full size only
  /// while it's zoomed in (capped at 4096 on phones with little RAM).
  Widget _photo(BuildContext context, String path) {
    final thumb = item.thumbPath;
    final mq = MediaQuery.of(context);
    final screen = (mq.size.longestSide * mq.devicePixelRatio).round();
    return ValueListenableBuilder<double>(
      valueListenable: PhotoPager.zoom,
      builder: (context, zoom, _) {
        final detail = current && zoom > 1.15;
        final cap = detail ? (DeviceMemory.low ? 4096 : null) : screen;
        final ImageProvider file = FileImage(File(path));
        return Image(
          image: cap == null
              ? file
              : ResizeImage(
                  file,
                  width: cap,
                  height: cap,
                  policy: ResizeImagePolicy.fit,
                  allowUpscaling: false,
                ),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, sync) => frame == null && !sync && thumb != null
              // (the board's size, so it's the copy it already decoded)
              ? Image.file(File(thumb), fit: BoxFit.cover, cacheWidth: 420, gaplessPlayback: true)
              : child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final path = item.outputPath;
    if (CameraCatalog.byId(item.cameraId).isInstant) {
      return _held(
        InstantPrint(
          note: item.note,
          onNoteTap: onWrite,
          wear: PaperWear.of(item.id, item.readyAt),
          style: PrintFrames.styleOf(frames, item.id),
          picture: path == null ? const ColoredBox(color: Colors.black12) : _photo(context, path),
        ),
      );
    }
    final aspect = (item.width ?? 3) / (item.height ?? 2);
    return _held(
      AspectRatio(
        aspectRatio: aspect,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: FramedPrint(
            key: ValueKey(PrintFrames.frameOf(frames, item.id)),
            frame: PrintFrames.frameOf(frames, item.id),
            number: RegExp(r'_(\d+)\.').firstMatch(item.fileName)?.group(1),
            seed: item.id.hashCode,
            wear: PaperWear.of(item.id, item.readyAt),
            photo: path == null ? const ColoredBox(color: Colors.black12) : _photo(context, path),
          ),
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    this.vertical = false,
    this.onWrite,
    required this.saved,
    required this.saving,
    required this.onSave,
    required this.onDelete,
    required this.onShare,
    this.framing = false,
    this.onFrame,
    this.gone = false,
    this.sample = false,
    this.onStudio,
  });

  /// Off the board to the Studio.
  final VoidCallback? onStudio;

  /// A sample print: never leaves the app (no Share, no Save).
  final bool sample;

  /// Saved, but the copy isn't on the phone now: Save again.
  final bool gone;

  /// A column down the right edge (landscape) instead of a row.
  final bool vertical;

  /// Frames (not instant prints: their frame is the film's own).
  final bool framing;
  final VoidCallback? onFrame;
  final VoidCallback? onWrite;
  final bool saved;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onDelete;
  final Future<void> Function(BuildContext anchor) onShare;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: vertical ? const EdgeInsets.fromLTRB(4, 12, 16, 12) : const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Flex(
        direction: vertical ? Axis.vertical : Axis.horizontal,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (!sample) ...[
            Builder(
              builder: (anchor) => _RoundAction(
                icon: Icons.ios_share,
                label: 'Share',
                onTap: () => unawaited(onShare(anchor)),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: saved && !gone
                  ? const _RoundAction(
                      key: ValueKey('s'),
                      icon: Icons.check,
                      label: 'Saved',
                      highlighted: true,
                    )
                  : saved
                  ? _RoundAction(
                      key: const ValueKey('g'),
                      icon: Icons.download,
                      label: saving ? 'Saving…' : 'Save again',
                      onTap: saving ? null : onSave,
                    )
                  : _RoundAction(
                      key: const ValueKey('u'),
                      icon: Icons.download,
                      label: saving ? 'Saving…' : 'Save',
                      onTap: saving ? null : onSave,
                      primary: true,
                    ),
            ),
          ],
          if (onWrite != null) _RoundAction(icon: Icons.edit_outlined, label: 'Write', onTap: onWrite),
          if (onStudio != null)
            _RoundAction(glyph: const StudioHouseIcon(size: 22), label: 'Add to Studio', onTap: onStudio),
          if (onFrame != null)
            _RoundAction(
              icon: Icons.filter_frames_outlined,
              label: 'Frame',
              onTap: onFrame,
              highlighted: framing,
            ),
          _RoundAction(icon: Icons.delete_outline, label: 'Throw away', onTap: onDelete),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    super.key,
    this.icon,
    this.glyph,
    required this.label,
    this.onTap,
    this.primary = false,
    this.highlighted = false,
  });

  final IconData? icon;

  /// Drawn instead of [icon] (the Studio's house).
  final Widget? glyph;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final bg = primary
        ? const Color(0xFFF3E3C8)
        : (highlighted ? const Color(0xFF2F4A2A) : const Color(0x22FFFFFF));
    final fg = primary ? const Color(0xFF3B2A1A) : (highlighted ? const Color(0xFFB9E3A0) : Colors.white);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: IconTheme(
              data: IconThemeData(color: fg, size: 24),
              child: Center(child: glyph ?? Icon(icon)),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Where a print hangs on the board: its untilted rect (global) and tilt.
typedef PrintSpot = ({Rect rect, double angle});

/// Paints its child moved and scaled from [origin] (a global rect, e.g. the
/// print on the board) to where it's laid out, by [progress]. Read at paint
/// time, so it follows a board that scrolled meanwhile; worked out in local
/// coordinates, so it holds while the page is laid out turned.
class _FlyFrom extends SingleChildRenderObjectWidget {
  const _FlyFrom({required this.progress, required this.origin, required super.child});

  final Animation<double> progress;
  final PrintSpot? Function() origin;

  @override
  _RenderFlyFrom createRenderObject(BuildContext context) => _RenderFlyFrom(progress, origin);

  @override
  void updateRenderObject(BuildContext context, _RenderFlyFrom renderObject) => renderObject
    ..progress = progress
    ..origin = origin;
}

class _RenderFlyFrom extends RenderProxyBox {
  _RenderFlyFrom(this._progress, this.origin);

  Animation<double> _progress;
  PrintSpot? Function() origin;

  set progress(Animation<double> v) {
    if (v == _progress) return;
    if (attached) _progress.removeListener(markNeedsPaint);
    _progress = v;
    if (attached) _progress.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _progress.removeListener(markNeedsPaint);
    super.detach();
  }

  /// The board's rect in our own coordinates, or null (no fly).
  Matrix4? _matrix() {
    final t = _progress.value;
    if (t >= 1 || size.isEmpty) return null;
    final from = origin();
    if (from == null) return null;
    final a = globalToLocal(from.rect.topLeft), b = globalToLocal(from.rect.bottomRight);
    final r = Rect.fromPoints(a, b);
    // One scale for both sides (the print keeps its shape), turned straight
    // from its tilt on the board as it comes up.
    final s0 = math.sqrt(r.width * r.height / (size.width * size.height));
    final scale = ui.lerpDouble(s0, 1, t)!;
    final centre = Offset.lerp(r.center, size.center(Offset.zero), t)!;
    return Matrix4.identity()
      ..translateByDouble(centre.dx, centre.dy, 0, 1)
      ..rotateZ(from.angle * (1 - t))
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-size.width / 2, -size.height / 2, 0, 1);
  }

  final _transform = LayerHandle<TransformLayer>();
  final _opacity = LayerHandle<OpacityLayer>();

  @override
  void paint(PaintingContext context, Offset offset) {
    final t = _progress.value;
    final m = t < 1 ? _matrix() : null;
    if (m != null) {
      _opacity.layer = null;
      _transform.layer = context.pushTransform(
        needsCompositing,
        offset,
        m,
        super.paint,
        oldLayer: _transform.layer,
      );
    } else if (t < 1 && origin() == null) {
      // No spot on the board (scrolled off, or another print): fade instead.
      _transform.layer = null;
      _opacity.layer = context.pushOpacity(offset, (t * 255).round(), super.paint, oldLayer: _opacity.layer);
    } else {
      _transform.layer = null;
      _opacity.layer = null;
      super.paint(context, offset);
    }
  }

  @override
  void dispose() {
    _transform.layer = null;
    _opacity.layer = null;
    super.dispose();
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      _progress.value >= 1 && super.hitTestChildren(result, position: position);
}
