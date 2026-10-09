import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vector_math/vector_math_64.dart' as v64 show Vector3;

import '../../cameras/domain/camera_spec.dart';
import '../../settings/application/settings_controllers.dart';

/// The 3D cameras (1.7): each body is a real 3D model (made in Blender by
/// tool/render/blender/export_glb.py: the path-traced materials baked into
/// textures, every moving piece its own node) drawn live with Flutter Scene,
/// lit by the renders' studio. Labels, the LCD, the gallery thumbnail and
/// the live viewfinder are the app's own widgets laid on its face; the
/// controls' moving parts (keys, dial, lever, flash tab, rocker, shutter)
/// move on the model (see [LivePart]).
///
/// Everything sits in one design space, 412 x 968 dp, scaled to the
/// screen's width. Phones less tall than that lose a band out of the middle
/// of the viewfinder ([DesignFit]); the model's middle piece squeezes (or
/// stretches) to match ([LiveBody.fit]).
class WholeArt {
  WholeArt._(this.design, this.cutY, this.dist, this.band, this.bodies);

  static const root = 'assets/body3d';

  final Size design;

  /// Design y the face is squeezed / stretched at (inside the viewfinder).
  final double cutY;

  /// Camera distance from the face, design dp.
  final double dist;

  /// Half-height of the model's stretchable middle piece, design dp.
  final double band;
  final Map<AppMode, WholeBody> bodies;

  /// The layout and, with [scenes] (needs Flutter GPU: not in tests or on
  /// phones without it, which get the classic bodies), the models.
  static Future<WholeArt?> load({bool scenes = true}) async {
    try {
      final j = jsonDecode(await rootBundle.loadString('$root/manifest.json')) as Map<String, dynamic>;
      final d = j['design'] as Map<String, dynamic>;
      final design = Size((d['w'] as num).toDouble(), (d['h'] as num).toDouble());
      final studio = j['studio'] as Map<String, dynamic>;
      fs.EnvironmentMap? env;
      if (scenes) {
        await fs.Scene.initializeStaticResources();
        env = await fs.EnvironmentMap.fromEquirectImageAsset(
          assetPath: '$root/studio.hdr',
          maxWidth: 1024,
          diffuseSphericalHarmonics: [
            for (final c in studio['diffuseSH'] as List<dynamic>)
              vm.Vector3(
                ((c as List<dynamic>)[0] as num).toDouble(),
                (c[1] as num).toDouble(),
                (c[2] as num).toDouble(),
              ),
          ],
        );
      }
      final bodies = <AppMode, WholeBody>{};
      for (final mode in AppMode.values) {
        final b = j[mode.name] as Map<String, dynamic>?;
        final lay = (j['layout'] as Map<String, dynamic>?)?[mode.name] as Map<String, dynamic>?;
        if (b == null || lay == null) continue;
        final lug = (b['lug'] as List<dynamic>).cast<num>();
        final body = WholeBody._(
          layout: WholeLayout._fromJson(lay),
          alt: b['alt'] as String,
          press: {
            for (final MapEntry(key: k, value: v) in (b['press'] as Map<String, dynamic>).entries)
              k: (v as num).toDouble(),
          },
          lug: vm.Vector3(lug[0].toDouble(), lug[1].toDouble(), lug[2].toDouble()),
        );
        if (scenes) {
          final node = await fs.loadScene('$root/${b['scene']}');
          body.live = LiveBody._(
            node,
            body,
            env!,
            exposure: (studio['exposure'] as num).toDouble(),
            design: design,
            cutY: (d['cutY'] as num).toDouble(),
            dist: (d['dist'] as num).toDouble(),
            band: (d['band'] as num).toDouble(),
          );
          // Compile its shaders now (behind the launch screen), not on the
          // first frame it's seen.
          try {
            await body.live!.scene.warmUp([
              fs.RenderView(
                camera: fs.PerspectiveCamera(
                  position: vm.Vector3(0, 0, -(d['dist'] as num).toDouble()),
                  target: vm.Vector3.zero(),
                ),
              ),
            ]);
          } catch (_) {}
        }
        bodies[mode] = body;
      }
      if (bodies.isEmpty) return null;
      return WholeArt._(
        design,
        (d['cutY'] as num).toDouble(),
        (d['dist'] as num).toDouble(),
        (d['band'] as num).toDouble(),
        bodies,
      );
    } catch (e, s) {
      // Not bundled, or no Flutter GPU here: the classic bodies.
      debugPrint('3D bodies unavailable: $e\n$s');
      return null;
    }
  }
}

class WholeBody {
  WholeBody._({required this.layout, required this.alt, required this.press, required this.lug});

  final WholeLayout layout;

  /// The other shutter on this body (Super 8 RUN / camcorder REC).
  final String alt;

  /// How far each pressed piece travels, in its own units.
  final Map<String, double> press;

  /// The strap lug, model space (x right, y up, z toward the viewer; the
  /// face's centre at the origin).
  final vm.Vector3 lug;

  /// The model, drawn live (null without Flutter GPU, e.g. in tests).
  LiveBody? live;
}

/// Where things are on the face, design dp.
class WholeLayout {
  WholeLayout._(this.frame, this.screenInset, this.label, this.parts);

  factory WholeLayout._fromJson(Map<String, dynamic> j) {
    Rect r(Object? v) {
      final l = (v! as List<dynamic>).cast<num>();
      return Rect.fromLTRB(l[0].toDouble(), l[1].toDouble(), l[2].toDouble(), l[3].toDouble());
    }

    return WholeLayout._(r(j['frame']), (j['screenInset'] as num).toDouble(), r(j['memo'] ?? j['lcd']), {
      for (final MapEntry(key: k, value: v) in (j['parts'] as Map<String, dynamic>).entries)
        k: Offset(((v as List<dynamic>)[0] as num).toDouble(), (v[1] as num).toDouble()),
    });
  }

  /// The viewfinder's frame; the live picture fills it less [screenInset].
  final Rect frame;
  final double screenInset;

  /// Memo holder (film) / LCD (digital).
  final Rect label;
  final Map<String, Offset> parts;

  Rect get screen => frame.deflate(screenInset);
}

/// Design space onto a screen: scaled to its width, and a band taken out of
/// the middle (at [WholeArt.cutY], inside the viewfinder) on phones less
/// tall than the design (added there, stretched, on taller ones).
class DesignFit {
  DesignFit(this.art, Size screen)
    : s = screen.width / art.design.width,
      trim = art.design.height - screen.height / (screen.width / art.design.width);

  final WholeArt art;

  /// Screen dp per design dp.
  final double s;

  /// Design dp taken out at the cut (negative: added).
  final double trim;

  double y(double dy) => (dy <= art.cutY ? dy : dy - trim) * s;
  Offset point(Offset d) => Offset(d.dx * s, y(d.dy));
  Rect rect(Rect d) => Rect.fromLTRB(d.left * s, y(d.top), d.right * s, y(d.bottom));

  /// The screen point the body turns about (the cut, mid-width).
  Offset get pivot => Offset(art.design.width / 2 * s, art.cutY * s);

  /// The screen's centre, where the camera looks.
  Offset get centre => Offset(art.design.width / 2 * s, (art.design.height - trim) / 2 * s);

  /// Screen space (dp; x right, y down, z into the screen) seen through the
  /// models' camera: perspective about the screen's centre from [WholeArt.dist].
  Matrix4 get camera {
    final c = centre;
    return Matrix4.translationValues(c.dx, c.dy, 0)
      ..multiply(Matrix4.identity()..setEntry(3, 2, 1 / (art.dist * s)))
      ..multiply(Matrix4.translationValues(-c.dx, -c.dy, 0));
  }
}

final wholeArtProvider = FutureProvider<WholeArt?>((ref) => WholeArt.load());

/// The 3D body for [mode] when 3D is on and it can be drawn here.
final wholeBodyProvider = Provider.family<WholeBody?, AppMode>((ref, mode) {
  final art = ref.watch(wholeArtProvider).value;
  final body = art?.bodies[mode];
  if (body == null) return null; // (settings untouched: tests run without them)
  return ref.watch(globalSettingsProvider.select((s) => s.controls3d)) ? body : null;
});

// ------------------------------------------------------------------ live

/// One body's model in its own scene: fitted to the phone, posed (the swap)
/// and with its moving pieces where the controls put them.
///
/// Model space is the export's: x right, y up, z toward the viewer, 1 =
/// one design dp, the face's centre at the origin. Flutter Scene's build-
/// time import turns glTF's z round (its view space is left-handed), so in
/// the scene the face looks down -z and the camera sits on that side.
class LiveBody extends ChangeNotifier {
  LiveBody._(
    this.node,
    this.body,
    fs.EnvironmentMap env, {
    required double exposure,
    required this.design,
    required this.cutY,
    required this.dist,
    required this.band,
  }) {
    scene
      ..environment = env
      // the studio map is made with x mirrored, the scene has z turned
      // round: half a turn about y between them
      ..environmentTransform = vm.Matrix3.rotationY(math.pi)
      ..exposure = exposure
      ..toneMapping = fs.ToneMappingMode.agx;
    scene.add(node);
    void index(fs.Node n) {
      _nodes[n.name] = n;
      _rest[n] = n.localTransform.clone();
      for (final c in n.children) {
        index(c);
      }
    }

    index(node);
    showShutter(false);
  }

  /// Model to scene: z turned round.
  static v64.Vector3 _scene(vm.Vector3 v) => v64.Vector3(v.x, v.y, -v.z);

  final fs.Node node;
  final WholeBody body;
  final fs.Scene scene = fs.Scene();
  final Size design;
  final double cutY;
  final double dist;
  final double band;
  final Map<String, fs.Node> _nodes = {};
  final Map<fs.Node, vm.Matrix4> _rest = {};

  double _trim = 0;
  bool? _alt;

  /// The controls' parts that move a piece of the model, and how.
  static const _moving = {
    'flashtab': ('mv.flashtab.slide', null),
    'aspecttop': ('mv.aspect.turn', null),
    'lensdot': ('mv.lensdot.turn', null),
    'menu': ('mv.menu.press', 'menu'),
    'pill': ('mv.pill.press', 'pill'),
    'pillwide': ('mv.pillwide.press', 'pillwide'),
    'pillsmall': ('mv.pillsmall.press', 'pillsmall'),
    'release': ('mv.shutter.press', 'shutter'),
    'lever': ('mv.shutter.lever', null),
    'shutter': ('mv.shutter.press', 'shutter'),
    'run': ('mv.shutteralt.press', 'shutteralt'),
    'rec': ('mv.shutteralt.press', 'shutteralt'),
    'rocker': ('mv.rocker.rock', null),
  };

  /// The body's other shutter (Super 8 RUN, camcorder REC) instead of its
  /// usual one.
  void showShutter(bool alt) {
    if (alt == _alt) return;
    final first = _alt == null;
    _alt = alt;
    _nodes['part.shutter']?.visible = !alt;
    _nodes['part.shutteralt']?.visible = alt;
    if (!first) _changed();
  }

  /// Squeezes (stretches) the middle piece by [trim] design dp, moving
  /// everything below it up (down) to match [DesignFit].
  void fit(double trim) {
    if (trim == _trim) return;
    _trim = trim;
    final k = math.max(0.04, (2 * band - trim) / (2 * band));
    final mid = _nodes['body.mid'];
    if (mid != null) {
      mid.localTransform = vm.Matrix4.translationValues(0, trim / 2, 0)
        ..multiply(_rest[mid]!)
        ..scaleByDouble(1, k, 1, 1);
    }
    final root = _nodes['body'];
    for (final c in root?.children ?? const <fs.Node>[]) {
      final rest = _rest[c]!;
      if (c.name == 'body.bot' || (c.name.startsWith('part.') && rest.getTranslation().y < 0)) {
        c.localTransform = vm.Matrix4.translationValues(0, trim, 0)..multiply(rest);
      }
    }
  }

  /// Scene space (y up, z away from the viewer) to screen space (dp; y
  /// down, z into the screen), for [s] screen dp per design dp.
  Matrix4 _toScreen(double s) =>
      Matrix4.diagonal3Values(s, -s, s)..setTranslationRaw(design.width / 2 * s, design.height / 2 * s, 0);

  /// Places the body by [screen]: a transform in screen space (dp, about
  /// whatever it likes; identity = at rest) for a screen [s] dp per design dp.
  void pose(Matrix4 screen, double s) {
    final a = _toScreen(s);
    final m = Matrix4.inverted(a)
      ..multiply(screen)
      ..multiply(a);
    node.localTransform = vm.Matrix4.fromList(m.storage)..multiply(_rest[node]!);
  }

  /// Where the strap lug is on screen, the body posed by [screenPose] and
  /// seen through [camera] (see [DesignFit.camera]).
  Offset lugAt(Matrix4 screenPose, Matrix4 camera, double s) {
    final p =
        (camera.clone()
              ..multiply(screenPose)
              ..multiply(_toScreen(s)))
            .perspectiveTransform(_scene(body.lug));
    return Offset(p.x, p.y);
  }

  /// A control's part moved: slid by ([dx], [dy]) and turned by [angle]
  /// (screen sense, radians) from its rest place, in [state] (pressed,
  /// rocked). Repaints on the next frame.
  void setPart(String name, {double dx = 0, double dy = 0, double angle = 0, String? state}) {
    final entry = _moving[name];
    if (entry == null) return;
    final n = _nodes[entry.$1];
    if (n == null) return;
    final travel = entry.$2 == null ? 0.0 : (body.press[entry.$2] ?? 0);
    final m = _rest[n]!.clone()
      // Screen y is down; pressed is into the body (+z in the scene); seen
      // from -z, a turn clockwise on screen is a turn about +z.
      ..translateByDouble(dx, -dy, state == 'down' ? travel : 0, 1)
      ..rotateZ(angle);
    // the rocker tips about its own y (turned round with z: so the angle)
    if (state == 'w' || state == 't') m.rotateY(state == 'w' ? 0.035 : -0.035);
    if (m == n.localTransform) return;
    n.localTransform = m;
    _changed();
  }

  bool _pending = false;

  void _changed() {
    if (_pending) return;
    _pending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _pending = false;
      notifyListeners();
    });
    SchedulerBinding.instance.scheduleFrame();
  }
}

/// The model drawn over the whole of this widget's box (a phone's screen):
/// fitted by [fit], posed by [pose] (screen space, null = at rest). Paints
/// only when something changes (no ticker).
class LiveBodyView extends StatefulWidget {
  const LiveBodyView({super.key, required this.body, required this.fit, this.pose});

  final LiveBody body;
  final DesignFit fit;
  final Matrix4? pose;

  @override
  State<LiveBodyView> createState() => _LiveBodyViewState();
}

class _LiveBodyViewState extends State<LiveBodyView> {
  int _version = 0;

  @override
  void initState() {
    super.initState();
    widget.body.addListener(_repaint);
  }

  @override
  void didUpdateWidget(LiveBodyView old) {
    super.didUpdateWidget(old);
    if (old.body != widget.body) {
      old.body.removeListener(_repaint);
      widget.body.addListener(_repaint);
    }
  }

  @override
  void dispose() {
    widget.body.removeListener(_repaint);
    super.dispose();
  }

  void _repaint() {
    if (mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    final fit = widget.fit;
    final body = widget.body
      ..fit(fit.trim)
      ..pose(widget.pose ?? Matrix4.identity(), fit.s);
    final visibleH = fit.art.design.height - fit.trim;
    // A fresh camera each build is what makes the (unticked) view repaint.
    final camera = fs.PerspectiveCamera(
      fovRadiansY: 2 * math.atan(visibleH / 2 / fit.art.dist),
      position: vm.Vector3(0, fit.trim / 2, -fit.art.dist),
      target: vm.Vector3(0, fit.trim / 2, 0),
      fovNear: fit.art.dist * 0.3,
      fovFar: fit.art.dist * 3,
    );
    return IgnorePointer(
      child: KeyedSubtree(
        key: ValueKey(body),
        child: fs.SceneView(body.scene, camera: camera, autoTick: false),
      ),
    );
  }
}

/// The face's layer of widgets (design dp, trimmed like [DesignFit]):
/// [LivePart]s report their place relative to it.
class LiveFace extends InheritedWidget {
  const LiveFace({super.key, required this.body, required this.rest, required super.child});

  final LiveBody body;

  /// Where a part sits at rest, in the face's coordinates.
  final Offset Function(String part) rest;

  static LiveFace? of(BuildContext context) => context.getInheritedWidgetOfExactType<LiveFace>();

  @override
  bool updateShouldNotify(LiveFace old) => old.body != body;
}

/// Marks the face's coordinate space for [LivePart].
class LiveFaceRoot extends SingleChildRenderObjectWidget {
  const LiveFaceRoot({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFaceRoot();
}

class _RenderFaceRoot extends RenderProxyBox {}

/// Stands in for a control's moving part when the body is the live model:
/// draws nothing, and tells the model where the part is now (the
/// control's own slides, turns and presses, read off its transform) and in
/// what [state].
class LivePart extends LeafRenderObjectWidget {
  const LivePart({super.key, required this.name, this.state});

  final String name;
  final String? state;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLivePart(name, state, LiveFace.of(context));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderLivePart)
        ..name = name
        ..state = state
        ..face = LiveFace.of(context);
}

class _RenderLivePart extends RenderBox {
  _RenderLivePart(this._name, this._state, this.face);

  String _name;
  String? _state;
  LiveFace? face;

  set name(String v) {
    if (v == _name) return;
    _name = v;
    markNeedsPaint();
  }

  set state(String? v) {
    if (v == _state) return;
    _state = v;
    markNeedsPaint();
  }

  @override
  void performLayout() => size = constraints.smallest;

  @override
  void paint(PaintingContext context, Offset offset) {
    final f = face;
    if (f == null) return;
    RenderObject? root = parent;
    while (root != null && root is! _RenderFaceRoot) {
      root = root.parent;
    }
    if (root == null) return;
    final m = getTransformTo(root);
    final at = MatrixUtils.transformPoint(m, size.center(Offset.zero));
    final rest = f.rest(_name);
    final angle = math.atan2(m.entry(1, 0), m.entry(0, 0));
    f.body.setPart(_name, dx: at.dx - rest.dx, dy: at.dy - rest.dy, angle: angle, state: _state);
  }
}
