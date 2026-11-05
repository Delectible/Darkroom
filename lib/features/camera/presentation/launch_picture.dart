import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../../core/app_info.dart';
import '../../../core/diagnostics/launch_timer.dart';
import '../../../core/diagnostics/perf_recorder.dart';
import '../../../core/performance/quality.dart';
import '../../cameras/domain/camera_spec.dart';

/// A picture of the 3D camera in hand, kept from the last run, so the app
/// can open on it while the real model loads.
///
/// At launch the camera's own picture (the live viewfinder) and its
/// controls are ready a second or so before the 3D body (a slow tablet:
/// camera 1.3-2.4 s, body 2.5-3.0 s). When the saved picture matches the
/// camera now (same body, skin, camera, quality steps, app version, and to
/// the pixel the same box), the launch curtain lifts on the real face and
/// live viewfinder over this picture of the body; the model takes its
/// place when it lands, fading in over it, pixel for pixel the same. Until
/// then touches wait (trying anything shows a note). Anything off: none of
/// this, the launch waits for the model as before.
///
/// Saved by the camera screen ([capture]) whenever the model has been drawn
/// anew and then stood still for a moment: a PNG of exactly what the model
/// drew (its box only, not the controls), and what it was of.
class LaunchPicture {
  LaunchPicture._();

  static File? _png, _json;
  static ui.Image? _image;
  static Map<String, Object?>? _meta;
  static Future<void>? _loading;
  static bool _off = false, _shown = false, _done = false, _capturing = false;
  static String? _savedSig;

  /// Where it's kept (main.dart, before the app starts: it loads alongside
  /// the rest of the launch).
  static void init(Directory dir) {
    _png = File('${dir.path}/launch_body.png');
    _json = File('${dir.path}/launch_body.json');
    _loading = _load();
  }

  /// Completes once the saved picture has been read (or there was none).
  static Future<void> get loaded => _loading ?? Future<void>.value();

  static Future<void> _load() async {
    try {
      final json = _json!, png = _png!;
      if (!json.existsSync() || !png.existsSync()) return;
      final meta = (jsonDecode(await json.readAsString()) as Map).cast<String, Object?>();
      if (meta['version'] != AppInfo.version) return;
      final codec = await ui.instantiateImageCodec(await png.readAsBytes());
      _image = (await codec.getNextFrame()).image;
      _meta = meta;
      _savedSig = null;
    } catch (_) {
      // unreadable: launches as before
    }
  }

  /// What the camera has on now, to match a picture against (the camera
  /// screen sets it as it builds; the 3D loader asks before it).
  static Map<String, Object?> want = const {};

  static Map<String, Object?> wantOf({
    required AppMode mode,
    required String? skin,
    required String? camera,
    required bool video,
  }) => {
    'mode': mode.name,
    'skin': skin ?? '',
    'camera': camera ?? '',
    'video': video,
    'gpu': Quality.gpu,
    'version': AppInfo.version,
  };

  static bool _matches(Map<String, Object?> w) {
    final m = _meta;
    if (m == null || w.isEmpty) return false;
    for (final e in w.entries) {
      if ('${m[e.key]}' != '${e.value}') return false;
    }
    return true;
  }

  /// Whether a launch can open on the picture for [w] (the 3D loader: it
  /// then lays the face out before the model is in).
  static bool candidate(Map<String, Object?> w) => !_off && !_done && _image != null && _matches(w);

  /// Whether the picture stands in for [mode]'s model now (the face leaves
  /// out its dark stand-in body).
  static bool covers(AppMode mode) =>
      !_off && !_done && _image != null && _meta?['mode'] == mode.name && _matches(want);

  /// The picture for the body's box ([px]: its size in pixels), or null if
  /// it isn't exactly that size. The first time: the launch can lift on it.
  static ui.Image? forBox(AppMode mode, Size px) {
    final image = _image;
    if (image == null || !covers(mode)) return null;
    if ((image.width - px.width).abs() > 2 || (image.height - px.height).abs() > 2) return null;
    if (!_shown) {
      _shown = true;
      LaunchTimer.once('launch picture up');
    }
    return image;
  }

  /// On show, waiting for the model.
  static bool get shown => _shown && !_done && !_off;

  /// Whether the launch curtain can lift on it: on show, and the body's
  /// moving parts ([poses]: WholeBody.poses; flash tab, dials, buttons up)
  /// are where they were in it. Else the curtain waits for the model.
  static bool liftOn(String poses) => shown && poses.isNotEmpty && _meta?['poses'] == poses;

  /// The picture fading out over the model that just landed (null when
  /// there's nothing to fade).
  static ui.Image? get fading => _shown && !_done && !_off ? _image : null;

  /// The model has taken over: the picture goes.
  static void done() {
    _done = true;
    _image = null;
  }

  /// Not this launch (the model failed to load): forgotten, and deleted.
  static void off() {
    _off = true;
    _image = null;
    try {
      _json?.deleteSync();
    } catch (_) {}
  }

  // ---- saving ------------------------------------------------------------

  static _RenderPictureSource? _source;

  /// Saves what the model in hand draws now ([renders]: how many times it
  /// has drawn, so the same drawing isn't saved twice; [poses]: where its
  /// moving parts are, WholeBody.poses).
  static Future<void> capture(double dpr, int renders, String poses) async {
    final src = _source, png = _png, json = _json;
    if (src == null || !src.attached || png == null || json == null || _capturing) return;
    if (want.isEmpty) return;
    // (the quality steps as they are now: they change without the camera
    // screen building)
    final meta = {...want, 'gpu': Quality.gpu, 'poses': poses};
    final sig = '${jsonEncode(meta)}|$renders';
    if (sig == _savedSig) return;
    _capturing = true;
    try {
      final image = await src.toImage(pixelRatio: dpr);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return;
      // the description goes first and comes back last: a half-written
      // pair never describes the wrong picture
      if (json.existsSync()) json.deleteSync();
      final tmp = File('${png.path}.tmp');
      await tmp.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
      await tmp.rename(png.path);
      await json.writeAsString(jsonEncode(meta), flush: true);
      _savedSig = sig;
    } catch (_) {
      // try again on the next change
    } finally {
      _capturing = false;
    }
  }
}

/// Around the model's view in the body's box: what [LaunchPicture.capture]
/// saves while [active] (the body in hand, at rest).
class LaunchPictureSource extends SingleChildRenderObjectWidget {
  const LaunchPictureSource({super.key, required this.active, super.child});

  final bool active;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderPictureSource(active);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderPictureSource).active = active;
}

class _RenderPictureSource extends RenderRepaintBoundary {
  _RenderPictureSource(this._active);

  bool _active;

  set active(bool v) {
    if (v == _active) return;
    _active = v;
    _claim();
  }

  void _claim() {
    if (attached && _active) {
      LaunchPicture._source = this;
    } else if (LaunchPicture._source == this) {
      LaunchPicture._source = null;
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _claim();
  }

  @override
  void detach() {
    if (LaunchPicture._source == this) LaunchPicture._source = null;
    super.detach();
  }
}

/// The picture over the model that just took its place, fading away (the
/// two are the same, pixel for pixel: a fade hides any last difference).
class LaunchPictureFade extends StatefulWidget {
  const LaunchPictureFade({super.key, required this.image});

  final ui.Image image;

  @override
  State<LaunchPictureFade> createState() => _LaunchPictureFadeState();
}

class _LaunchPictureFadeState extends State<LaunchPictureFade> with SingleTickerProviderStateMixin {
  late final _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 320), value: 1);

  /// The model's draws so far: the fade starts the frame after the model
  /// under it has drawn (its first draw can take a frame or two), so it
  /// never shows through half there. At most [_maxWait] frames.
  final int _drawn = PerfRecorder.scene3d;
  int _waited = 0;
  static const _maxWait = 30;

  @override
  void initState() {
    super.initState();
    _afterFrame();
  }

  void _afterFrame() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    if (PerfRecorder.scene3d == _drawn && ++_waited < _maxWait) {
      WidgetsBinding.instance.scheduleFrame();
      return _afterFrame();
    }
    _fade.reverse().whenComplete(() {
      LaunchPicture.done();
      if (mounted) setState(() {});
    });
  });

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _fade.value == 0
      ? const SizedBox.shrink()
      : FadeTransition(
          opacity: _fade,
          child: RawImage(image: widget.image, fit: BoxFit.fill, filterQuality: FilterQuality.none),
        );
}
