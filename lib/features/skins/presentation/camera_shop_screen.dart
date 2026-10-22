import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/sfx.dart';
import '../../../core/device/haptics.dart';
import '../../../core/skins/camera_skins.dart';
import '../../cameras/domain/camera_spec.dart';

/// Settings > Camera Shop: the skins in a glass display case. The one you
/// look at sits on the counter under a spotlight; the rest wait on the
/// shelf with paper price tags. Skins you haven't earned say which mini
/// game wins them.
Future<void> showCameraShop(BuildContext context, {AppMode? mode}) => Navigator.of(context).push(
  PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, _, _) => CameraShopScreen(initialMode: mode ?? AppMode.film),
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
    return Scaffold(
      backgroundColor: _Shop.wall,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.35),
            radius: 1.1,
            colors: [Color(0xFF3B2A1E), _Shop.wall],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _TopBar(onClose: () => Navigator.of(context).pop()),
              const SizedBox(height: 6),
              const _Sign(),
              const SizedBox(height: 14),
              _ModeTags(mode: _mode, onPick: _setMode),
              Expanded(
                child: _Counter(skin: skin, locked: !has),
              ),
              _Caption(skin: skin, has: has, inUse: inUse),
              const SizedBox(height: 12),
              _Case(skins: _skins, looking: _looking, wearing: wearing, owns: owned.owns, onLook: _look),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                child: _BrassButton(
                  label: inUse
                      ? 'ON YOUR CAMERA'
                      : has
                      ? 'PUT IT ON'
                      : 'LOCKED',
                  enabled: has && !inUse,
                  onTap: () => unawaited(_use(skin)),
                ),
              ),
            ],
          ),
        ),
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

/// The counter top: the skin you're looking at, under a spotlight.
class _Counter extends StatelessWidget {
  const _Counter({required this.skin, required this.locked});

  final CameraSkin skin;
  final bool locked;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final w = math.min(box.maxWidth * 0.72, box.maxHeight * 1.25);
      return Stack(
        alignment: Alignment.center,
        children: [
          // spotlight on the counter
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, 0.25),
                  radius: 0.7,
                  colors: [const Color(0xFFFFE2B0).withValues(alpha: 0.16), Colors.transparent],
                ),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (c, a) => FadeTransition(
              opacity: a,
              child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(a), child: c),
            ),
            child: SizedBox(
              key: ValueKey('${skin.mode.name}.${skin.id}'),
              width: w,
              height: w * 0.62,
              child: CustomPaint(painter: SkinCameraPainter(skin, dim: locked)),
            ),
          ),
          if (locked)
            Positioned(
              top: box.maxHeight * 0.1,
              child: const Icon(Icons.lock_outline, color: Color(0x99F1E6CC), size: 22),
            ),
        ],
      );
    },
  );
}

class _Caption extends StatelessWidget {
  const _Caption({required this.skin, required this.has, required this.inUse});

  final CameraSkin skin;
  final bool has;
  final bool inUse;

  @override
  Widget build(BuildContext context) {
    final unlock = skin.unlock;
    return Padding(
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
            has || unlock == null
                ? skin.blurb
                : 'Win it: ${unlock.goal}. (Darkroom 98 > Run > ${unlock.game})',
            textAlign: TextAlign.center,
            maxLines: 2,
            style: TextStyle(color: _Shop.paper.withValues(alpha: 0.7), fontSize: 13, height: 1.3),
          ),
        ],
      ),
    );
  }
}

/// The glass display case: a shelf of every skin with a price tag each.
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
    return Container(
      height: 150,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _Shop.wood, width: 6),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2A1F18), Color(0xFF15100C)],
        ),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Stack(
        children: [
          // the glass shelf
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0x55BFE3E0),
                boxShadow: [BoxShadow(color: const Color(0xFFBFE3E0).withValues(alpha: 0.2), blurRadius: 4)],
              ),
            ),
          ),
          ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            itemCount: skins.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
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
          // glass front: a diagonal sheen over everything
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-1, -1),
                    end: Alignment(1, 1),
                    stops: [0, 0.3, 0.31, 0.5, 0.51, 1],
                    colors: [
                      Color(0x14FFFFFF),
                      Color(0x08FFFFFF),
                      Color(0x00FFFFFF),
                      Color(0x00FFFFFF),
                      Color(0x0AFFFFFF),
                      Color(0x00FFFFFF),
                    ],
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

/// A camera seen from the front in a skin's colours: a rangefinder for
/// film, a compact for digital. Used on the shop shelf and the counter.
class SkinCameraPainter extends CustomPainter {
  SkinCameraPainter(this.skin, {this.dim = false});

  final CameraSkin skin;

  /// Locked: drawn in shadow.
  final bool dim;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final film = skin.mode == AppMode.film;
    // body: ~1.6:1 rounded block
    final bodyH = math.min(h * 0.82, w / 1.75);
    final bodyW = bodyH * 1.75;
    final body = Rect.fromCenter(center: Offset(w / 2, h * 0.56), width: bodyW, height: bodyH);
    final r = Radius.circular(bodyH * (film ? 0.1 : 0.16));
    // shadow on the shelf
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w / 2, body.bottom + bodyH * 0.04),
        width: bodyW * 0.95,
        height: bodyH * 0.12,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    canvas.saveLayer(Offset.zero & size, Paint());
    // shell (sides) as a darker rim
    canvas.drawRRect(RRect.fromRectAndRadius(body.inflate(bodyH * 0.02), r), Paint()..color = skin.shell);
    if (film) {
      _filmFront(canvas, body, r);
    } else {
      _digitalFront(canvas, body, r);
    }
    if (dim) {
      canvas.drawPaint(
        Paint()
          ..color = const Color(0xFF0E0A07).withValues(alpha: 0.6)
          ..blendMode = BlendMode.srcATop,
      );
    }
    canvas.restore();
  }

  void _filmFront(Canvas canvas, Rect b, Radius r) {
    final plateH = b.height * 0.22;
    final top = Rect.fromLTWH(b.left, b.top, b.width, plateH);
    final bottom = Rect.fromLTWH(b.left, b.bottom - plateH * 0.6, b.width, plateH * 0.6);
    // leatherette band
    canvas.drawRRect(RRect.fromRectAndRadius(b, r), Paint()..color = skin.covering);
    _pebbles(canvas, Rect.fromLTRB(b.left, top.bottom, b.right, bottom.top), skin.covering);
    // plates (brushed: a vertical gradient)
    for (final plate in [top, bottom]) {
      final shape = RRect.fromRectAndCorners(
        plate,
        topLeft: plate == top ? r : Radius.zero,
        topRight: plate == top ? r : Radius.zero,
        bottomLeft: plate == bottom ? r : Radius.zero,
        bottomRight: plate == bottom ? r : Radius.zero,
      );
      canvas.drawRRect(
        shape,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_shade(skin.trim, 0.25), skin.trim, _shade(skin.trim, -0.25)],
          ).createShader(plate),
      );
    }
    if (skin.id == 'brassed') {
      // brass showing through on the plate edges
      final brass = Paint()..color = const Color(0xFFB8913F);
      for (var i = 0; i < 7; i++) {
        final x = b.left + b.width * (0.06 + i * 0.14);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, top.bottom - 2.2, b.width * 0.06, 2.2),
            const Radius.circular(1),
          ),
          brass,
        );
      }
    }
    // shutter dial and rewind knob on top
    final dial = Paint()..color = _shade(skin.trim, -0.1);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(b.left + b.width * 0.68, b.top - b.height * 0.08, b.width * 0.14, b.height * 0.1),
        const Radius.circular(2),
      ),
      dial,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(b.left + b.width * 0.12, b.top - b.height * 0.06, b.width * 0.1, b.height * 0.08),
        const Radius.circular(2),
      ),
      dial,
    );
    // rangefinder windows
    final glass = Paint()..color = const Color(0xFF1C2630);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(b.left + b.width * 0.08, top.top + plateH * 0.25, b.width * 0.16, plateH * 0.5),
        const Radius.circular(2),
      ),
      glass,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(b.left + b.width * 0.76, top.top + plateH * 0.3, b.width * 0.1, plateH * 0.42),
        const Radius.circular(2),
      ),
      glass,
    );
    // nameplate
    _label(canvas, 'DARKROOM', Offset(b.center.dx, top.center.dy), plateH * 0.32, skin.ink);
    // lens
    _lens(canvas, Offset(b.center.dx, b.center.dy + b.height * 0.06), b.height * 0.34);
  }

  void _digitalFront(Canvas canvas, Rect b, Radius r) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(b, r),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_shade(skin.covering, 0.18), skin.covering, _shade(skin.covering, -0.18)],
        ).createShader(b),
    );
    // brushing: faint horizontal lines
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 0.6;
    for (var y = b.top + 3; y < b.bottom - 2; y += 2.2) {
      canvas.drawLine(Offset(b.left + 4, y), Offset(b.right - 4, y), line);
    }
    // trim: a band across the top (two-tone) or a grip on the left
    if (skin.id == 'grip') {
      final grip = RRect.fromRectAndCorners(
        Rect.fromLTWH(b.left, b.top, b.width * 0.2, b.height),
        topLeft: r,
        bottomLeft: r,
      );
      canvas.drawRRect(grip, Paint()..color = skin.trim);
      _pebbles(canvas, grip.outerRect, skin.trim);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(b.left, b.top, b.width, b.height * 0.16),
          topLeft: r,
          topRight: r,
        ),
        Paint()..color = skin.trim,
      );
    }
    // flash window and label
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(b.left + b.width * 0.28, b.top + b.height * 0.24, b.width * 0.16, b.height * 0.13),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFFEDEBE3),
    );
    _label(
      canvas,
      'DARKROOM',
      Offset(b.left + b.width * 0.36, b.bottom - b.height * 0.16),
      b.height * 0.1,
      skin.ink,
    );
    _lens(canvas, Offset(b.left + b.width * 0.7, b.center.dy + b.height * 0.04), b.height * 0.3);
  }

  void _lens(Canvas canvas, Offset c, double radius) {
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEDEEF0), Color(0xFF8E9298), Color(0xFF2B2D30)],
        ).createShader(Rect.fromCircle(center: c, radius: radius)),
    );
    canvas.drawCircle(c, radius * 0.82, Paint()..color = const Color(0xFF141517));
    canvas.drawCircle(
      c,
      radius * 0.62,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.3),
          colors: [Color(0xFF3F4F6A), Color(0xFF0B0E14)],
        ).createShader(Rect.fromCircle(center: c, radius: radius * 0.62)),
    );
    canvas.drawCircle(
      c + Offset(-radius * 0.22, -radius * 0.22),
      radius * 0.12,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  void _pebbles(Canvas canvas, Rect area, Color base) {
    final dot = Paint()..color = _shade(base, 0.12).withValues(alpha: 0.55);
    final rnd = math.Random(area.width.round() * 31 + area.height.round());
    final n = (area.width * area.height / 14).clamp(0, 900).toInt();
    for (var i = 0; i < n; i++) {
      canvas.drawCircle(
        Offset(area.left + rnd.nextDouble() * area.width, area.top + rnd.nextDouble() * area.height),
        0.6,
        dot,
      );
    }
  }

  void _label(Canvas canvas, String text, Offset centre, double size, Color color) {
    if (size < 4) return;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w800,
          letterSpacing: size * 0.25,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
  }

  static Color _shade(Color c, double amount) =>
      amount >= 0 ? Color.lerp(c, Colors.white, amount)! : Color.lerp(c, Colors.black, -amount)!;

  @override
  bool shouldRepaint(SkinCameraPainter old) => old.skin != skin || old.dim != dim;
}
