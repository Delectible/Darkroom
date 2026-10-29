import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/sfx.dart';
import '../../../core/device/haptics.dart';
import '../../../core/device/upright.dart';
import '../../../core/skins/camera_skins.dart';
import '../../cameras/domain/camera_spec.dart';
import 'skin_camera_painter.dart';

/// Settings > Camera Shop: a little camera shop at the back of the
/// darkroom. Red safelight, prints drying on a line, film on the back
/// shelf; on the counter a glass case with the skin you're looking at lit
/// on a velvet pad, the rest on the glass shelf below with paper price
/// tags. Skins you haven't earned say which game wins them, and how far
/// along you are.
Future<void> showCameraShop(BuildContext context, {AppMode? mode}) => Navigator.of(context).push(
  PageRouteBuilder<void>(
    // turns with the phone (the cabinet beside the counter, sideways)
    settings: UprightApp.landscape,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, _, _) => UprightPage(child: CameraShopScreen(initialMode: mode ?? AppMode.film)),
    transitionsBuilder: (_, a, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
      child: child,
    ),
  ),
);

class CameraShopScreen extends ConsumerStatefulWidget {
  const CameraShopScreen({super.key, this.initialMode = AppMode.film});

  final AppMode initialMode;

  @override
  ConsumerState<CameraShopScreen> createState() => _CameraShopScreenState();
}

class _CameraShopScreenState extends ConsumerState<CameraShopScreen> {
  late AppMode _mode = widget.initialMode;
  late String _looking = ref.read(cameraSkinProvider)[_mode]!;

  List<CameraSkin> get _skins => CameraSkins.forMode(_mode);

  void _setMode(AppMode m) {
    if (m == _mode) return;
    Sfx.keyDown.play();
    unawaited(Haptics.selectionClick());
    setState(() {
      _mode = m;
      _looking = ref.read(cameraSkinProvider)[m]!;
    });
  }

  void _look(CameraSkin s) {
    if (s.id == _looking) return;
    Sfx.cardSnap.play();
    unawaited(Haptics.selectionClick());
    setState(() => _looking = s.id);
  }

  Future<void> _use(CameraSkin s) async {
    Sfx.keyUp.play();
    unawaited(Haptics.mediumImpact());
    await ref.read(cameraSkinProvider.notifier).set(_mode, s.id);
  }

  @override
  Widget build(BuildContext context) {
    final wearing = ref.watch(cameraSkinProvider)[_mode]!;
    final owned = ref.watch(unlockedSkinsProvider.notifier);
    ref.watch(unlockedSkinsProvider);
    final skin = CameraSkins.byId(_mode, _looking);
    final has = owned.owns(skin);
    final inUse = skin.id == wearing;
    final progress = ref.watch(skinProgressProvider);
    return Scaffold(
      backgroundColor: _Shop.wall,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(child: CustomPaint(painter: _Backdrop())),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, box) {
                final cabinet = _Cabinet(
                  top: _Display(skin: skin, locked: !has),
                  shelf: _Case(
                    skins: _skins,
                    looking: _looking,
                    wearing: wearing,
                    owns: owned.owns,
                    onLook: _look,
                  ),
                );
                final button = _BrassButton(
                  label: inUse
                      ? 'ON YOUR CAMERA'
                      : has
                      ? 'PUT IT ON'
                      : 'LOCKED',
                  enabled: has && !inUse,
                  onTap: () => unawaited(_use(skin)),
                );
                if (box.maxWidth > box.maxHeight) {
                  // Held sideways: the cabinet on the left, the sign, tags,
                  // tag line and button beside it.
                  return Row(
                    children: [
                      Expanded(flex: 3, child: cabinet),
                      Expanded(
                        flex: 2,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(8, 4, 16, 12),
                          child: Column(
                            children: [
                              Align(
                                alignment: Alignment.centerRight,
                                child: IconButton(
                                  tooltip: 'Leave the shop',
                                  onPressed: () => Navigator.of(context).pop(),
                                  icon: const Icon(Icons.close, color: Color(0xCCF1E6CC)),
                                ),
                              ),
                              const _Sign(),
                              const SizedBox(height: 12),
                              _ModeTags(mode: _mode, onPick: _setMode),
                              const SizedBox(height: 12),
                              _Caption(skin: skin, has: has, progress: progress),
                              Padding(padding: const EdgeInsets.fromLTRB(8, 8, 8, 0), child: button),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    _TopBar(onClose: () => Navigator.of(context).pop()),
                    const _Sign(),
                    const SizedBox(height: 12),
                    _ModeTags(mode: _mode, onPick: _setMode),
                    const SizedBox(height: 12),
                    Expanded(child: cabinet),
                    const SizedBox(height: 10),
                    _Caption(skin: skin, has: has, progress: progress),
                    Padding(padding: const EdgeInsets.fromLTRB(24, 8, 24, 16), child: button),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The shop's colours.
abstract final class _Shop {
  static const wall = Color(0xFF1A120D);
  static const wood = Color(0xFF5A3A22);
  static const brass = Color(0xFFCFA85E);
  static const brassDark = Color(0xFF7C5F2C);
  static const paper = Color(0xFFF1E6CC);
  static const ink = Color(0xFF2A211A);
  static const neon = Color(0xFFFF7A4D);
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        tooltip: 'Leave the shop',
        onPressed: onClose,
        icon: const Icon(Icons.close, color: Color(0xCCF1E6CC)),
      ),
      const Spacer(),
    ],
  );
}

/// A warm neon sign over the counter.
class _Sign extends StatelessWidget {
  const _Sign();

  @override
  Widget build(BuildContext context) {
    TextStyle glow(double size, double spacing) => TextStyle(
      color: const Color(0xFFFFD8C2),
      fontSize: size,
      fontWeight: FontWeight.w800,
      letterSpacing: spacing,
      shadows: const [
        Shadow(color: _Shop.neon, blurRadius: 6),
        Shadow(color: _Shop.neon, blurRadius: 18),
      ],
    );
    return Column(
      children: [
        Text('DARKROOM', style: glow(13, 6)),
        const SizedBox(height: 2),
        Text('CAMERA EXCHANGE', style: glow(22, 3)),
      ],
    );
  }
}

/// FILM / DIGITAL as two paper tags on hooks.
class _ModeTags extends StatelessWidget {
  const _ModeTags({required this.mode, required this.onPick});

  final AppMode mode;
  final ValueChanged<AppMode> onPick;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (final m in AppMode.values) ...[
        GestureDetector(
          onTap: () => onPick(m),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
            decoration: BoxDecoration(
              color: m == mode ? _Shop.paper : _Shop.paper.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: _Shop.brass.withValues(alpha: m == mode ? 0.9 : 0.35)),
            ),
            child: Text(
              m == AppMode.film ? 'FILM' : 'DIGITAL',
              style: TextStyle(
                color: m == mode ? _Shop.ink : _Shop.paper.withValues(alpha: 0.7),
                fontWeight: FontWeight.w800,
                letterSpacing: 2.5,
                fontSize: 12,
              ),
            ),
          ),
        ),
        if (m != AppMode.values.last) const SizedBox(width: 12),
      ],
    ],
  );
}

/// The back of the darkroom behind the counter: a dark panelled wall, the
/// red safelight and its glow, prints drying on a line, film boxes and an
/// old camera or two on the back shelf. Drawn once (it never changes).
class _Backdrop extends CustomPainter {
  const _Backdrop();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final all = Offset.zero & size;
    canvas.drawRect(
      all,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1C110C), Color(0xFF140D09), Color(0xFF0C0806)],
        ).createShader(all),
    );
    // panelling
    final seam = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    final edge = Paint()
      ..color = Colors.white.withValues(alpha: 0.025)
      ..strokeWidth = 1;
    for (var x = w / 9; x < w; x += w / 4.5) {
      canvas.drawLine(Offset(x, 0), Offset(x, h * 0.72), seam);
      canvas.drawLine(Offset(x + 1.5, 0), Offset(x + 1.5, h * 0.72), edge);
    }
    // the back shelf, with film boxes and a camera on it
    final shelfY = h * 0.27;
    canvas.drawRect(Rect.fromLTWH(0, shelfY, w, 6), Paint()..color = const Color(0xFF3A2414));
    canvas.drawRect(Rect.fromLTWH(0, shelfY + 6, w, 4), Paint()..color = Colors.black.withValues(alpha: 0.4));
    final boxes = [
      (0.02, const Color(0xFF8C2A1E), 26.0, 34.0),
      (0.1, const Color(0xFFB8862B), 22.0, 30.0),
      (0.17, const Color(0xFF2D4F7A), 24.0, 32.0),
      (0.8, const Color(0xFF3F6B3A), 22.0, 30.0),
      (0.87, const Color(0xFFB8862B), 26.0, 36.0),
      (0.94, const Color(0xFF8C2A1E), 20.0, 28.0),
    ];
    for (final (fx, c, bw, bh) in boxes) {
      final r = Rect.fromLTWH(w * fx, shelfY - bh, bw, bh);
      canvas.drawRect(r, Paint()..color = Color.lerp(c, Colors.black, 0.45)!);
      canvas.drawRect(
        Rect.fromLTWH(r.left, r.top + bh * 0.35, bw, bh * 0.18),
        Paint()..color = const Color(0x22FFFFFF),
      );
    }
    // red safelight hanging top right, and the room's red glow
    final lamp = Offset(w * 0.86, h * 0.07);
    canvas.drawLine(Offset(lamp.dx, 0), lamp - const Offset(0, 10), Paint()..color = const Color(0xFF2A2A2A));
    canvas.drawCircle(
      lamp,
      h * 0.42,
      Paint()
        ..shader = RadialGradient(
          colors: [const Color(0xFFFF2A14).withValues(alpha: 0.2), const Color(0x00FF2A14)],
        ).createShader(Rect.fromCircle(center: lamp, radius: h * 0.42)),
    );
    final shade = Path()
      ..moveTo(lamp.dx - 16, lamp.dy)
      ..lineTo(lamp.dx - 7, lamp.dy - 10)
      ..lineTo(lamp.dx + 7, lamp.dy - 10)
      ..lineTo(lamp.dx + 16, lamp.dy)
      ..close();
    canvas.drawPath(shade, Paint()..color = const Color(0xFF26201C));
    canvas.drawOval(
      Rect.fromCenter(center: lamp + const Offset(0, 1), width: 26, height: 7),
      Paint()..color = const Color(0xFFFF4A2A),
    );
    // prints drying on a line, with pegs
    final lineY = h * 0.035;
    canvas.drawLine(
      Offset(0, lineY),
      Offset(w * 0.74, lineY + 6),
      Paint()
        ..color = const Color(0xFF5A4A3A)
        ..strokeWidth = 1,
    );
    final rnd = math.Random(3);
    for (final fx in [0.04, 0.16, 0.6]) {
      final x = w * fx, y = lineY + 6 * fx / 0.74;
      final pw = 30.0 + rnd.nextDouble() * 8, ph = pw * 1.25;
      final print = Rect.fromLTWH(x, y + 3, pw, ph);
      canvas.save();
      canvas.translate(print.center.dx, print.top);
      canvas.rotate((rnd.nextDouble() - 0.5) * 0.12);
      canvas.translate(-print.center.dx, -print.top);
      canvas.drawRect(print, Paint()..color = const Color(0xFFD9CFC0).withValues(alpha: 0.55));
      canvas.drawRect(
        print.deflate(3),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF4A3A30).withValues(alpha: 0.8),
              const Color(0xFF1E1612).withValues(alpha: 0.8),
            ],
          ).createShader(print),
      );
      canvas.restore();
      canvas.drawRect(
        Rect.fromLTWH(print.center.dx - 2, y - 2, 4, 9),
        Paint()..color = const Color(0xFF8A6A48),
      );
    }
    // the counter top the cabinet stands on, and the floor of shadow
    final counter = Rect.fromLTWH(0, h * 0.8, w, h * 0.2);
    canvas.drawRect(
      counter,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3B2617), Color(0xFF1E130B)],
        ).createShader(counter),
    );
    canvas.drawLine(
      counter.topLeft,
      counter.topRight,
      Paint()
        ..color = const Color(0xFFCFA85E).withValues(alpha: 0.35)
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_Backdrop old) => false;
}

/// The glass cabinet on the counter: a lit display box on top, the shelf
/// of every skin below, in a dark wood frame with brass corners.
class _Cabinet extends StatelessWidget {
  const _Cabinet({required this.top, required this.shelf});

  final Widget top;
  final Widget shelf;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: _Shop.wood, width: 7),
      color: const Color(0xFF120C08),
      boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 18, offset: Offset(0, 8))],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Column(
        children: [
          Expanded(child: top),
          Container(height: 6, color: _Shop.wood),
          shelf,
        ],
      ),
    ),
  );
}

/// The top of the cabinet: the skin you're looking at on a velvet pad
/// under a spotlight, behind glass.
class _Display extends StatelessWidget {
  const _Display({required this.skin, required this.locked});

  final CameraSkin skin;
  final bool locked;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final w = math.min(box.maxWidth * 0.9, box.maxHeight * 1.5);
      return Stack(
        alignment: Alignment.center,
        children: [
          // back of the case: dark velvet with the spotlight falling on it
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.2),
                  radius: 0.85,
                  colors: [
                    const Color(0xFF4A1E1A),
                    const Color(0xFF1C0D0B),
                    Colors.black.withValues(alpha: 0.9),
                  ],
                  stops: const [0, 0.55, 1],
                ),
              ),
            ),
          ),
          // the pad
          Positioned(
            bottom: box.maxHeight * 0.1,
            child: Container(
              width: w * 0.95,
              height: box.maxHeight * 0.12,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(100),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF5E2420), Color(0xFF2E100E)],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: box.maxHeight * 0.13,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(scale: Tween(begin: 0.95, end: 1.0).animate(a), child: c),
              ),
              child: SizedBox(
                key: ValueKey('${skin.mode.name}.${skin.id}'),
                width: w,
                height: math.min(w * 0.62, box.maxHeight * 0.8),
                child: CustomPaint(painter: SkinCameraPainter(skin, dim: locked)),
              ),
            ),
          ),
          // spotlight cone from the top of the case
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -1.2),
                    radius: 1.1,
                    colors: [Color(0x26FFE8C4), Color(0x00FFE8C4)],
                  ),
                ),
              ),
            ),
          ),
          if (locked)
            const Positioned(
              top: 12,
              right: 14,
              child: Icon(Icons.lock_outline, color: Color(0xAAF1E6CC), size: 20),
            ),
          // the glass front: a sheen and a bright top edge
          const Positioned.fill(child: IgnorePointer(child: _Glass())),
        ],
      );
    },
  );
}

/// A pane of glass: a couple of diagonal reflections and a lit top edge.
class _Glass extends StatelessWidget {
  const _Glass();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment(-1, -1),
        end: Alignment(1, 1),
        stops: [0, 0.22, 0.23, 0.3, 0.31, 0.62, 0.63, 0.66, 0.67, 1],
        colors: [
          Color(0x12FFFFFF),
          Color(0x06FFFFFF),
          Color(0x14FFFFFF),
          Color(0x14FFFFFF),
          Color(0x00FFFFFF),
          Color(0x00FFFFFF),
          Color(0x0CFFFFFF),
          Color(0x0CFFFFFF),
          Color(0x00FFFFFF),
          Color(0x00FFFFFF),
        ],
      ),
      border: Border(top: BorderSide(color: Color(0x40FFFFFF), width: 1.5)),
    ),
  );
}

/// The skin's name and what it is, or what wins it: always two lines'
/// room, so the cabinet above never moves.
class _Caption extends StatelessWidget {
  const _Caption({required this.skin, required this.has, required this.progress});

  final CameraSkin skin;
  final bool has;
  final Map<String, int> progress;

  @override
  Widget build(BuildContext context) {
    final unlock = skin.unlock;
    String text;
    if (has || unlock == null) {
      text = skin.blurb;
    } else {
      final done = math.min(progress[unlock.stat] ?? 0, unlock.target);
      final count = unlock.target > 1 ? ' ($done of ${unlock.target})' : '';
      text = '${unlock.goal}$count. Darkroom 98 > Start > Run > ${unlock.game}';
    }
    return SizedBox(
      height: 70,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          children: [
            Text(
              skin.name.toUpperCase(),
              style: const TextStyle(
                color: _Shop.paper,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _Shop.paper.withValues(alpha: 0.72), fontSize: 13, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

/// The glass shelf in the bottom of the cabinet: every skin, with a price
/// tag each.
class _Case extends StatelessWidget {
  const _Case({
    required this.skins,
    required this.looking,
    required this.wearing,
    required this.owns,
    required this.onLook,
  });

  final List<CameraSkin> skins;
  final String looking;
  final String wearing;
  final bool Function(CameraSkin) owns;
  final ValueChanged<CameraSkin> onLook;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF241812), Color(0xFF110B08)],
          ),
        ),
        child: Stack(
          children: [
            // the glass shelf and its lit edge
            Positioned(
              left: 0,
              right: 0,
              bottom: 36,
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0x66BFE3E0),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFFBFE3E0).withValues(alpha: 0.25), blurRadius: 5),
                  ],
                ),
              ),
            ),
            ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              itemCount: skins.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final s = skins[i];
                return _ShelfItem(
                  skin: s,
                  selected: s.id == looking,
                  wearing: s.id == wearing,
                  owned: owns(s),
                  onTap: () => onLook(s),
                );
              },
            ),
            const Positioned.fill(child: IgnorePointer(child: _Glass())),
          ],
        ),
      ),
    );
  }
}

class _ShelfItem extends StatelessWidget {
  const _ShelfItem({
    required this.skin,
    required this.selected,
    required this.wearing,
    required this.owned,
    required this.onTap,
  });

  final CameraSkin skin;
  final bool selected;
  final bool wearing;
  final bool owned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tag = wearing
        ? 'IN USE'
        : owned
        ? 'OWNED'
        : skin.unlock!.game;
    return Semantics(
      button: true,
      selected: selected,
      label: '${skin.name}${owned ? '' : ', locked'}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 86,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 66,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: selected ? _Shop.brass : Colors.transparent, width: 1.5),
                  color: selected ? const Color(0x22FFE2B0) : Colors.transparent,
                ),
                child: CustomPaint(
                  size: const Size(80, 58),
                  painter: SkinCameraPainter(skin, dim: !owned),
                ),
              ),
              const SizedBox(height: 14),
              _PriceTag(text: tag, locked: !owned, wearing: wearing),
            ],
          ),
        ),
      ),
    );
  }
}

/// A little paper tag on a string.
class _PriceTag extends StatelessWidget {
  const _PriceTag({required this.text, required this.locked, required this.wearing});

  final String text;
  final bool locked;
  final bool wearing;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: -0.05,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: wearing ? const Color(0xFFE9D27A) : _Shop.paper,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(8), right: Radius.circular(2)),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (locked) ...[const Icon(Icons.lock, size: 9, color: _Shop.ink), const SizedBox(width: 3)],
          Text(
            text,
            style: const TextStyle(
              color: _Shop.ink,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    ),
  );
}

class _BrassButton extends StatelessWidget {
  const _BrassButton({required this.label, required this.enabled, required this.onTap});

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: enabled,
    label: label,
    child: GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: enabled ? 1 : 0.45,
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFE8C77E), _Shop.brass, _Shop.brassDark],
              stops: [0, 0.5, 1],
            ),
            border: Border.all(color: const Color(0xFF5E4720)),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3))],
          ),
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF2B1F0E), fontWeight: FontWeight.w900, letterSpacing: 2.5),
          ),
        ),
      ),
    ),
  );
}
