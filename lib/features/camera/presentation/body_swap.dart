import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/retro_theme.dart';
import '../../../core/theme/surfaces.dart';
import '../../cameras/domain/camera_spec.dart';

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
  });

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
        children: [SwapBody(key: liveKey, mode: leavingMode, face: leaving, capSide: 0, pose: BodyPose.rest)],
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
        ),
        SwapBody(
          key: liveArriving ? liveKey : null,
          mode: arrivingMode,
          face: arriving,
          capSide: dir,
          pose: come,
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
class SwapBody extends StatelessWidget {
  const SwapBody({
    super.key,
    required this.mode,
    required this.face,
    required this.capSide,
    required this.pose,
  });

  final AppMode mode;
  final Widget face;
  final int capSide;
  final BodyPose pose;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width, h = size.height;
    final geo = SwapGeometry(w);
    final moving = capSide != 0;
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
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.all(r),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.7),
                          blurRadius: 34,
                          offset: Offset(-capSide * 6.0, 22),
                        ),
                      ],
                    ),
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
                child: face,
              ),
              if (moving)
                // Strap from the lug, trailing behind the motion.
                Positioned(
                  left: end - 90,
                  width: 180,
                  top: lugY,
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
    // Strap lug: a metal eyelet.
    final c = Offset(size.width / 2, lugY);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: size.width * 0.55, height: 26),
        const Radius.circular(8),
      ),
      Paint()..color = Color.lerp(lug, Colors.black, 0.25)!,
    );
    canvas.drawCircle(
      c,
      7,
      Paint()
        ..color = lug
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
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
  });

  final bool film;
  final int side;
  final double swing;
  final Color color;
  final Color stitch;

  @override
  void paint(Canvas canvas, Size size) {
    final top = Offset(size.width / 2, 0);
    // Hangs outwards a little, and lags behind the body's motion.
    final lag = swing * 60;
    if (film) {
      final mid = Offset(top.dx + side * 26 + lag, size.height * 0.35);
      final bottom = Offset(top.dx + side * 10 + lag * 1.6, size.height * 0.9);
      final path = Path()
        ..moveTo(top.dx, top.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, bottom.dx, bottom.dy);
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 24
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 18,
      );
      // Stitching down both edges.
      for (final off in [-6.5, 6.5]) {
        final edge = Path()
          ..moveTo(top.dx + off, top.dy + 10)
          ..quadraticBezierTo(mid.dx + off, mid.dy, bottom.dx + off, bottom.dy);
        _dashed(
          canvas,
          edge,
          Paint()
            ..color = stitch.withValues(alpha: 0.5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
      // Metal ring at the lug.
      canvas.drawCircle(
        top,
        8,
        Paint()
          ..color = const Color(0xFFB9B4A8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    } else {
      // Wrist cord: a thin loop with a sliding bead.
      final bead = Offset(top.dx + side * 14 + lag * 0.8, size.height * 0.16);
      final loopEnd = Offset(top.dx + side * 18 + lag * 1.5, size.height * 0.4);
      final cord = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(top, bead, cord);
      final loop = Path()
        ..moveTo(bead.dx, bead.dy)
        ..cubicTo(bead.dx - 30, bead.dy + 60, loopEnd.dx - 28, loopEnd.dy, loopEnd.dx, loopEnd.dy)
        ..cubicTo(loopEnd.dx + 28, loopEnd.dy, bead.dx + 30, bead.dy + 60, bead.dx, bead.dy);
      canvas.drawPath(loop, cord);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: bead, width: 12, height: 16),
          const Radius.circular(4),
        ),
        Paint()..color = const Color(0xFF3A3D42),
      );
    }
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
      old.swing != swing || old.side != side || old.film != film || old.color != color;
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
