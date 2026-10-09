import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../core/theme/retro_theme.dart';
import '../../../core/theme/surfaces.dart';
import '../../cameras/domain/camera_spec.dart';
import '../../../core/theme/soft_shadow.dart';
import 'whole_body.dart';

/// Film <-> Digital as two physical cameras on a desk.
///
/// The screen is the back of the body you are holding; the body carries on
/// past the screen edges (a rounded end, the side wall with its strap lug,
/// the strap). Swapping slides the held body away while the other one comes
/// in from the opposite edge, both on one "conveyor": [progress] 0 is the
/// old body in hand, 1 the new one. The leaving body tips away and sinks
/// onto the desk; the arriving one is lifted up and settles.
class SwapStage extends StatelessWidget {
  const SwapStage({
    super.key,
    required this.progress,
    required this.dir,
    required this.leaving,
    required this.leavingMode,
    required this.arriving,
    required this.arrivingMode,
    required this.liveArriving,
    this.rendered,
  });

  /// Whole-body renders (3D on): moving bodies are drawn from them.
  final RenderedSwap? rendered;

  /// 0 = leaving body in hand, 1 = arriving body in hand (may overshoot).
  final double progress;

  /// Direction the leaving body travels: -1 left, +1 right.
  final int dir;
  final Widget leaving;
  final AppMode leavingMode;

  /// Null when nothing is moving: only the live body is built.
  final Widget? arriving;
  final AppMode arrivingMode;

  /// Which of the two is the live camera UI (keeps its element, and the
  /// camera preview, when it changes slot).
  final bool liveArriving;

  static const liveKey = ValueKey('live-body');

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width, h = size.height;
    final geo = SwapGeometry(w);
    final p = progress;
    final arriving = this.arriving;
    if (arriving == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          SwapBody(
            key: liveKey,
            mode: leavingMode,
            face: leaving,
            capSide: 0,
            pose: BodyPose.rest,
            rendered: rendered?.forBody(leavingMode, live: true),
          ),
        ],
      );
    }
    // Leaving: tossed aside, the end that trails behind comes into view.
    final out = (p.clamp(-0.2, 1.2)).toDouble();
    final leave = BodyPose(
      dx: dir * geo.travel * p,
      dy: h * 0.035 * out,
      tilt: 0.85 * math.sin(math.pi / 2 * out.clamp(0.0, 1.0)),
      roll: dir * 0.05 * out,
      scale: 1 - 0.1 * out.clamp(0.0, 1.0),
      swing: math.sin(math.pi * out.clamp(0.0, 1.0)),
    );
    // Arriving: comes in from the other edge, leading with its end.
    final rest = 1 - p;
    final come = BodyPose(
      dx: -dir * geo.travel * rest,
      dy: h * 0.03 * rest.clamp(0.0, 1.0),
      tilt: 0.7 * math.sin(math.pi / 2 * rest.clamp(-0.3, 1.0)),
      roll: -dir * 0.035 * rest,
      scale: 1 - 0.08 * rest,
      swing: -math.sin(math.pi * rest.clamp(0.0, 1.0)),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        SwapBody(
          key: liveArriving ? null : liveKey,
          mode: leavingMode,
          face: leaving,
          capSide: -dir,
          pose: leave,
          rendered: rendered?.forBody(leavingMode, live: !liveArriving),
        ),
        SwapBody(
          key: liveArriving ? liveKey : null,
          mode: arrivingMode,
          face: arriving,
          capSide: dir,
          pose: come,
          rendered: rendered?.forBody(arrivingMode, live: liveArriving),
        ),
      ],
    );
  }
}

/// Sizes of the parts of a body that sit beyond the screen.
class SwapGeometry {
  SwapGeometry(this.width);

  final double width;

  /// The rounded end of the body past the screen edge.
  double get cap => width * 0.2;

  /// Depth of the side wall.
  double get thickness => width * 0.14;

  /// Desk showing between the two bodies as they pass.
  double get gap => width * 0.12;

  /// How far each body travels for a full swap.
  double get travel => width + 2 * cap + thickness + gap;
}

/// Where a body is and how it is tipped.
class BodyPose {
  const BodyPose({
    required this.dx,
    required this.dy,
    required this.tilt,
    required this.roll,
    required this.scale,
    required this.swing,
  });

  static const rest = BodyPose(dx: 0, dy: 0, tilt: 0, roll: 0, scale: 1, swing: 0);

  final double dx;
  final double dy;

  /// Turn about the vertical axis towards the end that shows (radians, >= 0).
  final double tilt;

  /// Turn in the screen plane (radians).
  final double roll;
  final double scale;

  /// How far the strap trails behind the motion (-1..1).
  final double swing;
}

/// One camera body: the screen-sized [face] plus, while moving, the end of
/// the body on [capSide] (-1 left, +1 right, 0 none), its side wall, lug and
/// strap, tipped in perspective about the screen centre.
/// The lug's slot sits this far below `lugY` (see _SideWallPainter).
const _lugSlot = 2.0;

/// How far the body is turned about its vertical axis (radians, as in
/// [SwapBody]'s rotateY). The shutter shows its turntable frame for it, so
/// it turns as a solid object while the body tips.
class BodyYaw extends InheritedWidget {
  const BodyYaw({super.key, required this.yaw, required super.child});

  final double yaw;

  /// 0 when there's no body around (e.g. tests).
  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<BodyYaw>()?.yaw ?? 0;

  @override
  bool updateShouldNotify(BodyYaw old) => old.yaw != yaw;
}

class SwapBody extends StatelessWidget {
  const SwapBody({
    super.key,
    required this.mode,
    required this.face,
    required this.capSide,
    required this.pose,
    this.rendered,
  });

  final AppMode mode;
  final Widget face;
  final int capSide;
  final BodyPose pose;

  /// Drawn from the whole-body renders while moving.
  final RenderedBody? rendered;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width, h = size.height;
    final geo = SwapGeometry(w);
    final moving = capSide != 0;
    final rendered = this.rendered;
    if (rendered != null) return _renderedBody(context, rendered, size, moving);
    // About the screen centre (Flutter flattens each Transform to 2D, so
    // anything out of the body's plane gets its own full matrix).
    final m = Matrix4.identity()
      ..translateByDouble(w / 2, h / 2, 0, 1)
      ..setEntry(3, 2, 0.0016)
      ..translateByDouble(pose.dx, pose.dy, 0, 1)
      ..rotateZ(pose.roll)
      ..rotateY(capSide * pose.tilt)
      ..scaleByDouble(pose.scale, pose.scale, 1, 1)
      ..translateByDouble(-w / 2, -h / 2, 0, 1);
    // Corners round off as the body leaves the screen's frame.
    final r = Radius.circular(30 * (pose.tilt * 3).clamp(0.0, 1.0));
    final faceRadius = capSide > 0 ? BorderRadius.horizontal(left: r) : BorderRadius.horizontal(right: r);
    final p = RetroPalette.forMode(mode);
    final capLeft = capSide > 0 ? w : -geo.cap;
    final end = capSide > 0 ? w + geo.cap : -geo.cap;
    final lugY = h * 0.24;
    // Side wall: turned 90 degrees at the end, running back into the desk.
    final wallTop = h * 0.03;
    final wall = m.clone()
      ..translateByDouble(end, wallTop, 0, 1)
      ..rotateY(-math.pi / 2);
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        if (moving)
          Transform(
            transform: wall,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: geo.thickness,
                height: h - 2 * wallTop,
                child: _SideWall(mode: mode, lugY: lugY - wallTop, outward: capSide),
              ),
            ),
          ),
        // Keyed: the wall comes and goes beside it without remounting the face.
        Transform(
          key: const ValueKey('body'),
          transform: m,
          child: Stack(
            clipBehavior: Clip.none,
            fit: StackFit.expand,
            children: [
              if (moving) ...[
                // Shadow on the desk.
                Positioned(
                  left: capSide > 0 ? 0 : -geo.cap,
                  width: w + geo.cap,
                  top: 0,
                  height: h,
                  child: SoftShadow(
                    color: Colors.black.withValues(alpha: 0.7),
                    blurRadius: 34,
                    offset: Offset(-capSide * 6.0, 22),
                    radius: r.x,
                  ),
                ),
                // The end of the body beyond the screen.
                Positioned(
                  left: capLeft,
                  width: geo.cap,
                  top: 0,
                  height: h,
                  child: _BodyEnd(mode: mode, side: capSide),
                ),
              ],
              ClipRRect(
                key: const ValueKey('body-face'),
                borderRadius: faceRadius,
                clipBehavior: moving ? Clip.antiAlias : Clip.none,
                child: BodyYaw(yaw: capSide * pose.tilt, child: face),
              ),
            ],
          ),
        ),
        if (moving)
          // The strap hangs from the lug, which sits half the wall's depth
          // back from the face: give it that depth (its own full matrix,
          // as Flutter flattens nested 3D transforms) so the ring goes
          // through the lug's slot instead of floating at the front edge.
          Transform(
            transform: m.clone()..translateByDouble(0, 0, geo.thickness / 2, 1),
            child: Stack(
              clipBehavior: Clip.none,
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: end - 90,
                  width: 180,
                  top: lugY + _lugSlot,
                  height: h,
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _StrapPainter(
                        film: mode == AppMode.film,
                        side: capSide,
                        swing: pose.swing,
                        color: mode == AppMode.film ? const Color(0xFF3A2416) : const Color(0xFF17181B),
                        stitch: p.bodyHighlight,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The rounded end of the body past the screen edge, in the body's own
/// material, shading off as it curves away.
class _BodyEnd extends StatelessWidget {
  const _BodyEnd({required this.mode, required this.side});

  final AppMode mode;
  final int side;

  @override
  Widget build(BuildContext context) {
    final p = RetroPalette.forMode(mode);
    final film = mode == AppMode.film;
    const r = Radius.circular(34);
    final radius = side > 0
        ? const BorderRadius.horizontal(right: r)
        : const BorderRadius.horizontal(left: r);
    final towardsEnd = side > 0 ? Alignment.centerRight : Alignment.centerLeft;
    final towardsFace = side > 0 ? Alignment.centerLeft : Alignment.centerRight;
    return ClipRRect(
      borderRadius: radius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SurfaceTexture(
            leather: film,
            base: film ? p.body : p.bodyHighlight,
            light: p.bodyHighlight,
            dark: p.bodyShadow,
          ),
          // Curvature: darker as the end turns away from the light.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: towardsFace,
                end: towardsEnd,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.18),
                  Colors.black.withValues(alpha: 0.5),
                ],
                stops: const [0, 0.6, 1],
              ),
            ),
          ),
          // Panel seam where the screen's frame meets the body.
          Align(
            alignment: towardsFace,
            child: Container(width: 1.5, color: Colors.black.withValues(alpha: 0.45)),
          ),
          // Light catching the very edge.
          Align(
            alignment: towardsEnd,
            child: Container(
              width: 2,
              margin: const EdgeInsets.symmetric(vertical: 30),
              color: p.bodyHighlight.withValues(alpha: 0.35),
            ),
          ),
          // Film bodies: the leather stops short of a metal end band.
          if (film)
            Align(
              alignment: towardsEnd,
              child: FractionallySizedBox(
                widthFactor: 0.16,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: towardsFace,
                      end: towardsEnd,
                      colors: [p.metal, p.metalDark],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The side of the body: plain dark material with the strap lug.
class _SideWall extends StatelessWidget {
  const _SideWall({required this.mode, required this.lugY, required this.outward});

  final AppMode mode;
  final double lugY;
  final int outward;

  @override
  Widget build(BuildContext context) {
    final p = RetroPalette.forMode(mode);
    final film = mode == AppMode.film;
    return CustomPaint(
      painter: _SideWallPainter(
        material: film ? p.metalDark : Color.lerp(p.bodyShadow, Colors.black, 0.25)!,
        edge: film ? p.metal : p.bodyHighlight,
        lug: film ? p.metal : const Color(0xFF8E9298),
        lugY: lugY,
      ),
    );
  }
}

class _SideWallPainter extends CustomPainter {
  _SideWallPainter({required this.material, required this.edge, required this.lug, required this.lugY});

  final Color material;
  final Color edge;
  final Color lug;
  final double lugY;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      Paint()
        ..shader = LinearGradient(
          colors: [
            Color.lerp(material, Colors.black, 0.2)!,
            material,
            Color.lerp(material, Colors.black, 0.45)!,
          ],
          stops: const [0, 0.35, 1],
        ).createShader(rect),
    );
    // Edges where the side meets the back and the front.
    final line = Paint()
      ..color = edge.withValues(alpha: 0.45)
      ..strokeWidth = 1.5;
    canvas.drawLine(const Offset(1, 12), Offset(1, size.height - 12), line);
    canvas.drawLine(Offset(size.width - 1, 12), Offset(size.width - 1, size.height - 12), line);
    // Strap lug: a machined boss standing off the wall, with a slot the
    // ring runs through and a highlight along its upper edge.
    final c = Offset(size.width / 2, lugY);
    final boss = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: size.width * 0.5, height: 30),
      const Radius.circular(9),
    );
    canvas.drawRRect(
      boss.shift(const Offset(0, 3)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawRRect(
      boss,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(lug, Colors.white, 0.45)!, lug, Color.lerp(lug, Colors.black, 0.45)!],
          stops: const [0, 0.4, 1],
        ).createShader(boss.outerRect),
    );
    canvas.drawRRect(
      boss.deflate(0.5),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final slot = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c.translate(0, _lugSlot), width: 9, height: 12),
      const Radius.circular(4),
    );
    canvas.drawRRect(slot, Paint()..color = const Color(0xFF0B0A09));
    canvas.drawLine(
      Offset(slot.left + 1, slot.bottom + 1),
      Offset(slot.right - 1, slot.bottom + 1),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_SideWallPainter old) =>
      old.material != material || old.edge != edge || old.lug != lug || old.lugY != lugY;
}

/// Neck strap (film) or wrist cord (digital) hanging from the lug at the
/// top centre of the box, trailing behind as the body moves.
class _StrapPainter extends CustomPainter {
  _StrapPainter({
    required this.film,
    required this.side,
    required this.swing,
    required this.color,
    required this.stitch,
    this.rope,
    this.repaint,
  }) : super(repaint: repaint);

  final bool film;
  final int side;
  final double swing;
  final Color color;
  final Color stitch;

  /// Hangs along these points (a simulated rope, from the lug; see
  /// [_HangingStrap]) instead of a fixed curve.
  final List<Offset>? rope;
  final Listenable? repaint;

  @override
  void paint(Canvas canvas, Size size) {
    final rope = this.rope;
    if (rope != null && rope.length > 2) {
      return film
          ? _leatherStrap(canvas, size, rope.first, 0, rope)
          : _wristCord(canvas, size, rope.first, 0, rope);
    }
    final top = Offset(size.width / 2, 0);
    // Hangs outwards a little, and lags behind the body's motion.
    final lag = swing * 60;
    if (film) {
      _leatherStrap(canvas, size, top, lag);
    } else {
      _wristCord(canvas, size, top, lag);
    }
  }

  /// A leather neck strap: split ring, a folded end tab through a keeper,
  /// the strap itself (rounded, stitched both edges) and a buckle further
  /// down.
  void _leatherStrap(Canvas canvas, Size size, Offset top, double lag, [List<Offset>? rope]) {
    final ringC = top; // threaded through the lug's slot
    final start = ringC.translate(0, 7);
    final mid = Offset(top.dx + side * 26 + lag, size.height * 0.35);
    final bottom = Offset(top.dx + side * 10 + lag * 1.6, size.height * 0.9);
    final path = rope != null
        ? _smooth([start, ...rope.skip(1)])
        : (Path()
            ..moveTo(start.dx, start.dy)
            ..quadraticBezierTo(mid.dx, mid.dy, bottom.dx, bottom.dy));
    final metric = path.computeMetrics().first;
    softStroke(canvas, path.shift(Offset(-side * 4.0, 10)), 24, 9, Colors.black.withValues(alpha: 0.4));
    final dark = Color.lerp(color, Colors.black, 0.35)!;
    final light = Color.lerp(color, const Color(0xFFE0B48A), 0.28)!;
    // The end tab: narrower, doubled back from the ring to the keeper.
    final tab = metric.extractPath(0, 52);
    canvas.drawPath(
      tab,
      Paint()
        ..color = dark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round,
    );
    // The strap, with a soft highlight down one side so it reads round.
    final strap = metric.extractPath(36, metric.length);
    canvas.drawPath(
      strap,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 20,
    );
    canvas.drawPath(
      _parallel(metric, -4.5, 36, metric.length),
      Paint()
        ..color = light.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    canvas.drawPath(
      _parallel(metric, 7.5, 36, metric.length),
      Paint()
        ..color = dark.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    for (final off in [-7.0, 7.0]) {
      _dashed(
        canvas,
        _parallel(metric, off, 44, metric.length),
        Paint()
          ..color = stitch.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    // Keeper loop across the strap where the tab tucks in.
    _across(canvas, metric, 48, 26, 9, (rect, paint) {
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), paint..color = dark);
      canvas.drawLine(
        rect.topLeft.translate(2, 2),
        rect.topRight.translate(-2, 2),
        Paint()
          ..color = light.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
    });
    // Buckle: a metal frame with its bar, the strap running under it.
    _across(canvas, metric, metric.length * 0.48, 28, 15, (rect, paint) {
      final frame = RRect.fromRectAndRadius(rect, const Radius.circular(3));
      canvas.drawRRect(
        frame.shift(const Offset(0, 1.5)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
      final metal = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..shader = const LinearGradient(
          colors: [Color(0xFFEDE9E0), Color(0xFF9C978C), Color(0xFFD9D4CA)],
        ).createShader(rect);
      canvas.drawRRect(frame, metal);
      canvas.drawLine(rect.topCenter, rect.bottomCenter, metal);
    });
    // Triangular split ring through the lug.
    final ring = Path()
      ..moveTo(ringC.dx, ringC.dy - 5)
      ..lineTo(ringC.dx + 8, ringC.dy + 7)
      ..lineTo(ringC.dx - 8, ringC.dy + 7)
      ..close();
    canvas.drawPath(
      ring,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      ring,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF2EFE8), Color(0xFF8F8A80)],
        ).createShader(Rect.fromCircle(center: ringC, radius: 9))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// A braided wrist cord: a thin connector loop through the lug, the cord
  /// (with a woven texture), a cord lock, and the loop.
  void _wristCord(Canvas canvas, Size size, Offset top, double lag, [List<Offset>? rope]) {
    var bead = Offset(top.dx + side * 14 + lag * 0.8, size.height * 0.16);
    final loopEnd = Offset(top.dx + side * 18 + lag * 1.5, size.height * 0.4);
    final Path cord;
    if (rope != null) {
      // The cord to the lock along the rope, then the loop: two strands
      // either side of the rest of it, widest half way down.
      final k = (rope.length * 0.38).round().clamp(2, rope.length - 2);
      bead = rope[k];
      final tail = rope.sublist(k);
      final left = <Offset>[], right = <Offset>[];
      for (var i = 0; i < tail.length; i++) {
        final a = tail[math.max(0, i - 1)], b = tail[math.min(tail.length - 1, i + 1)];
        final d = b - a;
        final n = d.distance == 0 ? const Offset(1, 0) : Offset(-d.dy, d.dx) / d.distance;
        final w = 15 * math.sin(math.pi * math.min(1.0, i / (tail.length - 1) * 1.08));
        left.add(tail[i] + n * w);
        right.add(tail[i] - n * w);
      }
      cord = _smooth([top.translate(0, 6), ...rope.sublist(1, k + 1)])
        ..addPath(_smooth([...left, ...right.reversed]), Offset.zero);
    } else {
      cord = Path()
        ..moveTo(top.dx, top.dy + 6)
        ..quadraticBezierTo(top.dx + side * 4, (top.dy + bead.dy) / 2, bead.dx, bead.dy)
        ..cubicTo(bead.dx - 30, bead.dy + 60, loopEnd.dx - 28, loopEnd.dy, loopEnd.dx, loopEnd.dy)
        ..cubicTo(loopEnd.dx + 28, loopEnd.dy, bead.dx + 30, bead.dy + 60, bead.dx, bead.dy);
    }
    softStroke(canvas, cord.shift(Offset(-side * 3.0, 6)), 6, 4, Colors.black.withValues(alpha: 0.4));
    canvas.drawPath(
      cord,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    // Woven texture: short slanted ticks along the cord.
    final weave = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1.1;
    for (final m in cord.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 3.2) {
        final tan = m.getTangentForOffset(d)!;
        final n = Offset(-tan.vector.dy, tan.vector.dx);
        canvas.drawLine(
          tan.position + n * 2 - tan.vector * 1.2,
          tan.position - n * 2 + tan.vector * 1.2,
          weave,
        );
      }
    }
    // Connector: a thin loop through the lug.
    canvas.drawOval(
      Rect.fromCenter(center: top, width: 9, height: 12),
      Paint()
        ..color = const Color(0xFF2A2C30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Cord lock: a little barrel with ridges and a sheen.
    final lock = RRect.fromRectAndRadius(
      Rect.fromCenter(center: bead, width: 13, height: 18),
      const Radius.circular(5),
    );
    canvas.drawRRect(
      lock,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF55595F), Color(0xFF2A2C30), Color(0xFF16171A)],
        ).createShader(lock.outerRect),
    );
    final ridge = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (var y = lock.top + 4; y < lock.bottom - 3; y += 3) {
      canvas.drawLine(Offset(lock.left + 2, y), Offset(lock.right - 2, y), ridge);
    }
  }

  /// A smooth curve through [p] (Catmull-Rom).
  static Path _smooth(List<Offset> p) {
    final path = Path()..moveTo(p.first.dx, p.first.dy);
    for (var i = 0; i < p.length - 1; i++) {
      final p0 = p[math.max(0, i - 1)], p1 = p[i], p2 = p[i + 1], p3 = p[math.min(p.length - 1, i + 2)];
      final c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  /// A path running alongside [m] at [off] px (positive = right of travel).
  Path _parallel(PathMetric m, double off, double from, double to) {
    final out = Path();
    var first = true;
    for (var d = from; d <= to; d += 4) {
      final tan = m.getTangentForOffset(d);
      if (tan == null) break;
      final p = tan.position + Offset(-tan.vector.dy, tan.vector.dx) * off;
      if (first) {
        out.moveTo(p.dx, p.dy);
        first = false;
      } else {
        out.lineTo(p.dx, p.dy);
      }
    }
    return out;
  }

  /// Draws a [w] x [h] piece lying across the strap at [at] along it.
  void _across(Canvas canvas, PathMetric m, double at, double w, double h, void Function(Rect, Paint) draw) {
    final tan = m.getTangentForOffset(at);
    if (tan == null) return;
    canvas.save();
    canvas.translate(tan.position.dx, tan.position.dy);
    canvas.rotate(tan.angle * -1 + math.pi / 2);
    draw(Rect.fromCenter(center: Offset.zero, width: w, height: h), Paint());
    canvas.restore();
  }

  void _dashed(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 4.5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_StrapPainter old) =>
      old.rope != null || old.swing != swing || old.side != side || old.film != film || old.color != color;
}

/// Stand-in for a body that hasn't been seen yet this session (no picture
/// of it to slide in): its material, the viewfinder window and the shutter.
class BodyStandIn extends StatelessWidget {
  const BodyStandIn({super.key, required this.mode});

  final AppMode mode;

  @override
  Widget build(BuildContext context) {
    final p = RetroPalette.forMode(mode);
    final film = mode == AppMode.film;
    final pad = MediaQuery.paddingOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        SurfaceTexture(
          leather: film,
          base: film ? p.body : p.bodyHighlight,
          light: p.bodyHighlight,
          dark: p.bodyShadow,
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(14, pad.top + 60, 14, pad.bottom + 200),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(film ? 14 : 8),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: film ? [p.metal, p.metalDark] : [const Color(0xFF3A3F46), const Color(0xFF1A1D21)],
              ),
            ),
            child: Padding(
              padding: EdgeInsets.all(film ? 8 : 10),
              child: DecoratedBox(
                decoration: BoxDecoration(color: p.screen, borderRadius: BorderRadius.circular(film ? 8 : 4)),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: pad.bottom + 40),
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.metal,
                border: Border.all(color: p.metalDark, width: 4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

extension on SwapBody {
  /// The live 3D body: the model drawn posed (at rest, or slid, tipped and
  /// turned by the swap), and over it the face's widgets (labels, LCD,
  /// viewfinder) turned with it in the same perspective, the strap hanging
  /// from the model's lug. The face keeps its place in the tree either way,
  /// so the camera and its state carry on.
  Widget _renderedBody(BuildContext context, RenderedBody r, Size size, bool moving) {
    final live = r.body.live;
    if (live == null) return face;
    final fit = DesignFit(r.art, size);
    final pivot = fit.pivot;
    // The pose in screen space (dp, y down, z into the screen).
    final m = moving
        ? (Matrix4.translationValues(pivot.dx + pose.dx, pivot.dy + pose.dy, 0)
            ..rotateZ(pose.roll)
            ..scaleByDouble(pose.scale, pose.scale, pose.scale, 1)
            ..rotateY(capSide * pose.tilt)
            ..translateByDouble(-pivot.dx, -pivot.dy, 0, 1))
        : Matrix4.identity();
    final flat = Matrix4.identity()
      ..translateByDouble(pivot.dx + pose.dx, pivot.dy + pose.dy, 0, 1)
      ..rotateZ(pose.roll)
      ..scaleByDouble(pose.scale, pose.scale, 1, 1)
      ..translateByDouble(-pivot.dx, -pivot.dy, 0, 1);
    live.showShutter(r.shutter != 'shutter');
    final camera = fit.camera;
    final film = mode == AppMode.film;
    final p = RetroPalette.forMode(mode);
    final geo = SwapGeometry(size.width);
    final lug = live.lugAt(m, camera, fit.s);
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        if (moving)
          // Shadow on the desk.
          Transform(
            transform: flat,
            child: Stack(
              clipBehavior: Clip.none,
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: capSide > 0 ? 0 : -geo.cap,
                  width: size.width + geo.cap,
                  top: 0,
                  height: size.height,
                  child: SoftShadow(
                    color: Colors.black.withValues(alpha: 0.7),
                    blurRadius: 34,
                    offset: Offset(-capSide * 6.0, 22),
                    radius: 30,
                  ),
                ),
              ],
            ),
          ),
        LiveBodyView(key: const ValueKey('model'), body: live, fit: fit, pose: m),
        Transform(
          key: const ValueKey('face'),
          // (at rest too: the face plane is unchanged, labels lifted onto
          // key tops get the model's perspective)
          transform: camera.clone()..multiply(m),
          child: BodyYaw(yaw: capSide * pose.tilt, child: face),
        ),
        if (moving)
          Positioned.fill(
            child: IgnorePointer(
              child: _HangingStrap(
                anchor: lug + Offset(0, _lugSlot * fit.s),
                film: film,
                side: capSide,
                color: film ? const Color(0xFF3A2416) : const Color(0xFF17181B),
                stitch: p.bodyHighlight,
                length: size.height * (film ? 0.95 : 0.42),
              ),
            ),
          ),
      ],
    );
  }
}

/// What a whole-body swap needs for each body.
class RenderedBody {
  const RenderedBody({
    required this.art,
    required this.body,
    required this.shutter,
    required this.viewfinder,
  });

  final WholeArt art;
  final WholeBody body;

  /// Which shutter the body has on now (film release, Super 8 RUN, key, REC).
  final String shutter;

  /// The viewfinder's picture while it moves (a still: live, or as it was).
  final Widget viewfinder;
}

/// Builds [RenderedBody] for either body; [live] is the slot holding the
/// live camera UI.
class RenderedSwap {
  const RenderedSwap({required this.art, required this.shutter, required this.viewfinder});

  final WholeArt art;
  final String Function(AppMode mode) shutter;
  final Widget Function(AppMode mode, bool live) viewfinder;

  RenderedBody? forBody(AppMode mode, {required bool live}) {
    final body = art.bodies[mode];
    if (body == null) return null;
    return RenderedBody(art: art, body: body, shutter: shutter(mode), viewfinder: viewfinder(mode, live));
  }
}

/// The strap (film) or wrist cord (digital) as a rope: a chain of points
/// hanging from the lug under gravity, the real way down by the phone's
/// accelerometer, so it trails and swings as the body is tossed and sways
/// as the phone moves. Verlet steps, the lug pinned, links kept their
/// length.
class _HangingStrap extends StatefulWidget {
  const _HangingStrap({
    required this.anchor,
    required this.film,
    required this.side,
    required this.color,
    required this.stitch,
    required this.length,
  });

  final Offset anchor;
  final bool film;
  final int side;
  final Color color;
  final Color stitch;

  /// Rope length, dp.
  final double length;

  @override
  State<_HangingStrap> createState() => _HangingStrapState();
}

class _HangingStrapState extends State<_HangingStrap> with SingleTickerProviderStateMixin {
  static const _links = 18;
  late final Ticker _ticker = createTicker(_tick);
  final _frame = ValueNotifier<int>(0);
  late List<Offset> _p;
  late List<Offset> _was;
  Duration? _last;

  /// Gravity on the screen, dp/s² (from the accelerometer).
  Offset _g = const Offset(0, 2200);
  StreamSubscription<AccelerometerEvent>? _sub;

  double get _seg => widget.length / _links;

  @override
  void initState() {
    super.initState();
    // Hangs out from the end, a little curved, as it was lying.
    _p = [
      for (var i = 0; i <= _links; i++)
        widget.anchor + Offset(widget.side * i * _seg * 0.25, i * _seg * 0.95),
    ];
    _was = List.of(_p);
    _sub = accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen((e) {
      // The phone reads the push against gravity: gravity on the screen is
      // its opposite (screen y runs down, the phone's y up).
      final g = Offset(-e.x, e.y);
      final len = g.distance;
      if (len > 0.5) _g = g / len * (2200 * (len / 9.81).clamp(0.6, 1.8));
    }, onError: (Object _) {});
    unawaited(_ticker.start());
  }

  @override
  void dispose() {
    _ticker.dispose();
    unawaited(_sub?.cancel());
    _frame.dispose();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = _last == null ? 1 / 60 : ((now - _last!).inMicroseconds / 1e6).clamp(1 / 240, 1 / 30);
    _last = now;
    // Verlet: carry on as it was going (a little drag), plus gravity.
    for (var i = 1; i < _p.length; i++) {
      final v = (_p[i] - _was[i]) * 0.985;
      _was[i] = _p[i];
      _p[i] = _p[i] + v + _g * (dt * dt);
    }
    _p[0] = widget.anchor;
    _was[0] = widget.anchor;
    // Links keep their length (a few passes, from the lug down).
    for (var k = 0; k < 8; k++) {
      _p[0] = widget.anchor;
      for (var i = 0; i < _p.length - 1; i++) {
        final d = _p[i + 1] - _p[i];
        final len = d.distance;
        if (len == 0) continue;
        final diff = (len - _seg) / len;
        if (i == 0) {
          _p[i + 1] -= d * diff;
        } else {
          _p[i] += d * (diff * 0.5);
          _p[i + 1] -= d * (diff * 0.5);
        }
      }
    }
    _frame.value++;
  }

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _RopeStrap(this));
}

class _RopeStrap extends CustomPainter {
  _RopeStrap(this.s) : super(repaint: s._frame);

  final _HangingStrapState s;

  @override
  void paint(Canvas canvas, Size size) {
    final w = s.widget;
    _StrapPainter(
      film: w.film,
      side: w.side,
      swing: 0,
      color: w.color,
      stitch: w.stitch,
      rope: List.of(s._p),
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(_RopeStrap old) => true;
}
