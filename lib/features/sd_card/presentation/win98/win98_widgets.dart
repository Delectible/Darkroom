import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Classic 9x-era system palette.
class W98 {
  const W98._();

  static const face = Color(0xFFC0C0C0);
  static const light = Color(0xFFDFDFDF);
  static const white = Color(0xFFFFFFFF);
  static const shadow = Color(0xFF808080);
  static const dark = Color(0xFF0A0A0A);
  static const navy = Color(0xFF000080);
  static const titleEnd = Color(0xFF1084D0);
  static const desktop = Color(0xFF008080);
  static const inactiveTitle = Color(0xFF808080);
  static const inactiveTitleEnd = Color(0xFFB5B5B5);

  static const text = TextStyle(
    fontSize: 12,
    color: Colors.black,
    fontWeight: FontWeight.w400,
    height: 1.2,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  static const disabledText = TextStyle(
    fontSize: 12,
    color: shadow,
    height: 1.2,
    decoration: TextDecoration.none,
    shadows: [Shadow(color: white, offset: Offset(1, 1))],
  );
}

enum BevelStyle { raised, pressed, window, sunken, shallow }

/// Two-ring 3D border exactly like the 9x control frames.
class _BevelPainter extends CustomPainter {
  const _BevelPainter(this.style);

  final BevelStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final (outerTL, outerBR, innerTL, innerBR) = switch (style) {
      BevelStyle.raised => (W98.white, W98.dark, W98.light, W98.shadow),
      BevelStyle.pressed => (W98.dark, W98.white, W98.shadow, W98.light),
      BevelStyle.window => (W98.light, W98.dark, W98.white, W98.shadow),
      BevelStyle.sunken => (W98.shadow, W98.white, W98.dark, W98.light),
      BevelStyle.shallow => (W98.shadow, W98.white, null, null),
    };
    void ring(double inset, Color tl, Color br) {
      final r = Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2);
      final p = Paint()..strokeWidth = 1;
      p.color = tl;
      canvas.drawLine(r.topLeft + const Offset(0, 0.5), r.topRight + const Offset(-1, 0.5), p);
      canvas.drawLine(r.topLeft + const Offset(0.5, 0), r.bottomLeft + const Offset(0.5, -1), p);
      p.color = br;
      canvas.drawLine(r.bottomLeft + const Offset(0, -0.5), r.bottomRight + const Offset(0, -0.5), p);
      canvas.drawLine(r.topRight + const Offset(-0.5, 0), r.bottomRight + const Offset(-0.5, 0), p);
    }

    ring(0, outerTL, outerBR);
    if (innerTL != null && innerBR != null) ring(1, innerTL, innerBR);
  }

  @override
  bool shouldRepaint(_BevelPainter old) => old.style != style;
}

class Win98Bevel extends StatelessWidget {
  const Win98Bevel({
    super.key,
    required this.child,
    this.style = BevelStyle.raised,
    this.color = W98.face,
    this.padding = const EdgeInsets.all(2),
  });

  final Widget child;
  final BevelStyle style;
  final Color color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _BevelPainter(style),
      child: ColoredBox(
        color: color,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class Win98Button extends StatefulWidget {
  const Win98Button({
    super.key,
    required this.child,
    this.onPressed,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    this.toggled = false,
    this.minWidth = 0,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final EdgeInsets padding;
  final bool toggled;
  final double minWidth;

  @override
  State<Win98Button> createState() => _Win98ButtonState();
}

class _Win98ButtonState extends State<Win98Button> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final pressed = (_down && enabled) || widget.toggled;
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: enabled
            ? (_) {
                setState(() => _down = false);
                widget.onPressed!();
              }
            : null,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: widget.minWidth),
          child: Win98Bevel(
            style: pressed ? BevelStyle.pressed : BevelStyle.raised,
            padding: widget.padding + (pressed ? const EdgeInsets.only(left: 1, top: 1) : EdgeInsets.zero),
            child: DefaultTextStyle(
              style: enabled ? W98.text : W98.disabledText,
              textAlign: TextAlign.center,
              child: Opacity(
                opacity: enabled ? 1 : 0.55,
                child: Center(widthFactor: 1, heightFactor: 1, child: widget.child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small square caption button (_ □ X).
class Win98CaptionButton extends StatelessWidget {
  const Win98CaptionButton({super.key, required this.glyph, this.onPressed});

  final String glyph;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 16,
      child: Win98Button(
        onPressed: onPressed ?? () {},
        padding: EdgeInsets.zero,
        child: Text(glyph, style: W98.text.copyWith(fontSize: 11, fontWeight: FontWeight.w900, height: 1)),
      ),
    );
  }
}

class Win98TitleBar extends StatelessWidget {
  const Win98TitleBar({super.key, required this.title, this.icon, this.onClose, this.active = true});

  final String title;
  final Widget? icon;
  final VoidCallback? onClose;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: active ? const [W98.navy, W98.titleEnd] : const [W98.inactiveTitle, W98.inactiveTitleEnd],
        ),
      ),
      child: Row(
        children: [
          if (icon != null) ...[SizedBox(width: 16, height: 16, child: icon), const SizedBox(width: 4)],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: W98.text.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
          const Win98CaptionButton(glyph: '_'),
          const Win98CaptionButton(glyph: '□'),
          const SizedBox(width: 2),
          Win98CaptionButton(glyph: '×', onPressed: onClose),
        ],
      ),
    );
  }
}

class Win98Window extends StatelessWidget {
  const Win98Window({super.key, required this.title, required this.child, this.icon, this.onClose});

  final String title;
  final Widget child;
  final Widget? icon;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Win98Bevel(
      style: BevelStyle.window,
      padding: const EdgeInsets.all(3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Win98TitleBar(title: title, icon: icon, onClose: onClose),
          const SizedBox(height: 2),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Menus
// ---------------------------------------------------------------------------

class Win98MenuItem {
  const Win98MenuItem(this.label, {this.onSelected, this.checked = false, this.radio = false})
    : separator = false;

  const Win98MenuItem.separator()
    : label = '',
      onSelected = null,
      checked = false,
      radio = false,
      separator = true;

  final String label;
  final VoidCallback? onSelected;
  final bool checked;

  /// Radio-style bullet instead of a check mark.
  final bool radio;
  final bool separator;
}

Future<void> showWin98Menu(BuildContext anchor, List<Win98MenuItem> items) async {
  final box = anchor.findRenderObject()! as RenderBox;
  final topLeft = box.localToGlobal(Offset(0, box.size.height));
  final selected = await showGeneralDialog<Win98MenuItem>(
    context: anchor,
    barrierDismissible: true,
    barrierLabel: 'menu',
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, _) {
      final screen = MediaQuery.sizeOf(context);
      return Stack(
        children: [
          Positioned(
            left: math.min(topLeft.dx, screen.width - 200),
            top: topLeft.dy,
            child: _MenuPanel(items: items),
          ),
        ],
      );
    },
  );
  selected?.onSelected?.call();
}

class _MenuPanel extends StatefulWidget {
  const _MenuPanel({required this.items});

  final List<Win98MenuItem> items;

  @override
  State<_MenuPanel> createState() => _MenuPanelState();
}

class _MenuPanelState extends State<_MenuPanel> {
  int? _hot;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 170, maxWidth: 240),
        child: IntrinsicWidth(
          child: Win98Bevel(
            style: BevelStyle.window,
            padding: const EdgeInsets.all(3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < widget.items.length; i++)
                  if (widget.items[i].separator)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 3, horizontal: 1),
                      child: Column(
                        children: [
                          Divider(height: 1, thickness: 1, color: W98.shadow),
                          Divider(height: 1, thickness: 1, color: W98.white),
                        ],
                      ),
                    )
                  else
                    GestureDetector(
                      onTapDown: (_) => setState(() => _hot = i),
                      onTapCancel: () => setState(() => _hot = null),
                      onTap: widget.items[i].onSelected == null
                          ? null
                          : () => Navigator.of(context).pop(widget.items[i]),
                      child: Container(
                        color: _hot == i ? W98.navy : Colors.transparent,
                        padding: const EdgeInsets.fromLTRB(4, 5, 16, 5),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 18,
                              child: widget.items[i].checked
                                  ? Text(
                                      widget.items[i].radio ? '•' : '✓',
                                      style: W98.text.copyWith(
                                        color: _hot == i ? Colors.white : Colors.black,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    )
                                  : null,
                            ),
                            Text(
                              widget.items[i].label,
                              style: widget.items[i].onSelected == null
                                  ? W98.disabledText
                                  : W98.text.copyWith(color: _hot == i ? Colors.white : Colors.black),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class Win98MenuBar extends StatelessWidget {
  const Win98MenuBar({super.key, required this.menus});

  final Map<String, List<Win98MenuItem> Function()> menus;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Row(
        children: [
          for (final e in menus.entries)
            Builder(
              builder: (anchor) => GestureDetector(
                onTap: () => unawaited(showWin98Menu(anchor, e.value())),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: e.key[0],
                          style: const TextStyle(decoration: TextDecoration.underline),
                        ),
                        TextSpan(text: e.key.substring(1)),
                      ],
                    ),
                    style: W98.text,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tabs, progress, scrollbar, dialogs
// ---------------------------------------------------------------------------

class Win98Tab {
  const Win98Tab(this.label, {this.enabled = true, this.icon});

  final String label;
  final bool enabled;
  final Widget? icon;
}

class Win98TabStrip extends StatelessWidget {
  const Win98TabStrip({super.key, required this.tabs, required this.selected, required this.onSelect});

  final List<Win98Tab> tabs;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 26,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < tabs.length; i++)
            GestureDetector(
              onTap: tabs[i].enabled ? () => onSelect(i) : null,
              child: Transform.translate(
                offset: Offset(0, i == selected ? 2 : 0),
                child: Container(
                  height: i == selected ? 26 : 22,
                  margin: EdgeInsets.only(left: i == 0 ? 2 : 0),
                  child: CustomPaint(
                    painter: _TabPainter(selected: i == selected),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (tabs[i].icon != null) ...[
                            Opacity(opacity: tabs[i].enabled ? 1 : 0.4, child: tabs[i].icon),
                            const SizedBox(width: 4),
                          ],
                          Text(tabs[i].label, style: tabs[i].enabled ? W98.text : W98.disabledText),
                        ],
                      ),
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

class _TabPainter extends CustomPainter {
  _TabPainter({required this.selected});

  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = W98.face);
    final p = Paint()..strokeWidth = 1;
    p.color = W98.white;
    canvas.drawLine(const Offset(0.5, 2), Offset(0.5, size.height), p);
    canvas.drawLine(const Offset(2, 0.5), Offset(size.width - 2, 0.5), p);
    canvas.drawLine(const Offset(0.5, 2), const Offset(2, 0.5), p);
    p.color = W98.dark;
    canvas.drawLine(Offset(size.width - 0.5, 2), Offset(size.width - 0.5, size.height), p);
    p.color = W98.shadow;
    canvas.drawLine(Offset(size.width - 1.5, 1), Offset(size.width - 1.5, size.height), p);
    if (!selected) {
      p.color = W98.white;
      canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), p);
    }
  }

  @override
  bool shouldRepaint(_TabPainter old) => old.selected != selected;
}

/// Segmented "blocks" progress bar.
class Win98ProgressBar extends StatelessWidget {
  const Win98ProgressBar({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: Win98Bevel(
        style: BevelStyle.sunken,
        color: W98.face,
        padding: const EdgeInsets.all(3),
        child: LayoutBuilder(
          builder: (context, box) {
            const block = 9.0, gap = 2.0;
            final count = ((box.maxWidth + gap) / (block + gap)).floor();
            final lit = (count * value.clamp(0.0, 1.0)).round();
            return Row(
              children: [
                for (var i = 0; i < lit; i++)
                  Container(
                    width: block,
                    margin: const EdgeInsets.only(right: gap),
                    color: W98.navy,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Classic scrollbar: arrow buttons, dithered track, bevelled thumb.
class Win98Scrollbar extends StatefulWidget {
  const Win98Scrollbar({super.key, required this.controller, required this.child});

  final ScrollController controller;
  final Widget child;

  @override
  State<Win98Scrollbar> createState() => _Win98ScrollbarState();
}

class _Win98ScrollbarState extends State<Win98Scrollbar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(Win98Scrollbar old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() => setState(() {});

  void _nudge(double by) {
    final c = widget.controller;
    if (!c.hasClients) return;
    final p = c.position;
    c.animateTo(
      (c.offset + by).clamp(p.minScrollExtent, p.maxScrollExtent),
      duration: const Duration(milliseconds: 80),
      curve: Curves.linear,
    );
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
        return false;
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: widget.child),
          SizedBox(
            width: 16,
            child: Column(
              children: [
                SizedBox(
                  height: 16,
                  child: Win98Button(
                    onPressed: () => _nudge(-40),
                    padding: EdgeInsets.zero,
                    child: const _Arrow(up: true),
                  ),
                ),
                Expanded(child: _track()),
                SizedBox(
                  height: 16,
                  child: Win98Button(
                    onPressed: () => _nudge(40),
                    padding: EdgeInsets.zero,
                    child: const _Arrow(up: false),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _track() {
    return LayoutBuilder(
      builder: (context, box) {
        final c = widget.controller;
        final h = box.maxHeight;
        var thumbH = h, thumbTop = 0.0;
        var scrollable = false;
        if (c.hasClients && c.position.hasContentDimensions) {
          final p = c.position;
          final total = p.maxScrollExtent - p.minScrollExtent + p.viewportDimension;
          scrollable = p.maxScrollExtent > 0;
          thumbH = math.max(18, h * p.viewportDimension / total);
          final frac = p.maxScrollExtent == 0 ? 0.0 : (p.pixels / p.maxScrollExtent).clamp(0.0, 1.0);
          thumbTop = (h - thumbH) * frac;
        }
        return GestureDetector(
          onTapUp: (d) => _nudge(d.localPosition.dy < thumbTop ? -h * 0.9 : h * 0.9),
          onVerticalDragUpdate: scrollable
              ? (d) {
                  final p = c.position;
                  final perPx = p.maxScrollExtent / math.max(1, h - thumbH);
                  c.jumpTo((c.offset + d.delta.dy * perPx).clamp(p.minScrollExtent, p.maxScrollExtent));
                }
              : null,
          child: CustomPaint(
            painter: const _DitherPainter(),
            child: Stack(
              children: [
                if (scrollable)
                  Positioned(
                    top: thumbTop,
                    left: 0,
                    right: 0,
                    height: thumbH,
                    child: const Win98Bevel(child: SizedBox.expand()),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.up});

  final bool up;

  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(8, 5), painter: _ArrowPainter(up));
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.up);

  final bool up;

  @override
  void paint(Canvas canvas, Size size) {
    final path = up
        ? (Path()
            ..moveTo(size.width / 2, 0)
            ..lineTo(size.width, size.height)
            ..lineTo(0, size.height))
        : (Path()
            ..moveTo(0, 0)
            ..lineTo(size.width, 0)
            ..lineTo(size.width / 2, size.height));
    canvas.drawPath(path..close(), Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.up != up;
}

/// 50% checkerboard of the classic scrollbar track, drawn from a cached 2x2
/// image shader instead of one rect per pixel.
class _DitherPainter extends CustomPainter {
  const _DitherPainter();

  static ui.Image? _tile;

  static ui.Image _pattern() {
    if (_tile != null) return _tile!;
    final r = ui.PictureRecorder();
    final c = Canvas(r);
    c.drawRect(const Rect.fromLTWH(0, 0, 2, 2), Paint()..color = W98.white);
    final p = Paint()..color = W98.face;
    c.drawRect(const Rect.fromLTWH(0, 0, 1, 1), p);
    c.drawRect(const Rect.fromLTWH(1, 1, 1, 1), p);
    return _tile = r.endRecording().toImageSync(2, 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.ImageShader(
          _pattern(),
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.identity().storage,
        )
        ..filterQuality = FilterQuality.none,
    );
  }

  @override
  bool shouldRepaint(_DitherPainter old) => false;
}

enum Win98MessageIcon { info, warning, error, question }

/// Modal message box. Returns the index of the pressed button.
Future<int?> showWin98MessageBox(
  BuildContext context, {
  required String title,
  required String message,
  Win98MessageIcon icon = Win98MessageIcon.info,
  List<String> buttons = const ['OK'],
  Widget Function(Win98MessageIcon)? iconBuilder,
}) {
  return showGeneralDialog<int>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, _) => Center(
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: math.min(320, MediaQuery.sizeOf(context).width - 32),
          child: Win98Bevel(
            style: BevelStyle.window,
            padding: const EdgeInsets.all(3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Win98TitleBar(title: title, onClose: () => Navigator.of(context).pop()),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (iconBuilder != null) ...[
                        SizedBox(width: 32, height: 32, child: iconBuilder(icon)),
                        const SizedBox(width: 12),
                      ],
                      Expanded(child: Text(message, style: W98.text)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < buttons.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Win98Button(
                          minWidth: 76,
                          onPressed: () => Navigator.of(context).pop(i),
                          child: Text(buttons[i]),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Form controls & generic dialogs
// ---------------------------------------------------------------------------

/// Sunken white box with a black tick.
class Win98Checkbox extends StatelessWidget {
  const Win98Checkbox({super.key, required this.value, required this.label, this.onChanged});

  final bool value;
  final String label;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => onChanged!(!value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 13,
              height: 13,
              child: Win98Bevel(
                style: BevelStyle.sunken,
                color: enabled ? Colors.white : W98.face,
                padding: EdgeInsets.zero,
                child: value
                    ? const Center(
                        child: Text(
                          '✓',
                          style: TextStyle(fontSize: 10, height: 1, fontWeight: FontWeight.w900),
                        ),
                      )
                    : const SizedBox.expand(),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(child: Text(label, style: enabled ? W98.text : W98.disabledText)),
          ],
        ),
      ),
    );
  }
}

/// Round option button.
class Win98Radio extends StatelessWidget {
  const Win98Radio({super.key, required this.selected, required this.label, this.onTap});

  final bool selected;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(size: const Size(12, 12), painter: _RadioPainter(selected)),
            const SizedBox(width: 6),
            Text(label, style: onTap == null ? W98.disabledText : W98.text),
          ],
        ),
      ),
    );
  }
}

class _RadioPainter extends CustomPainter {
  _RadioPainter(this.selected);

  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = Colors.white);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = Rect.fromCircle(center: c, radius: r - 0.5);
    canvas.drawArc(rect, math.pi * 0.75, math.pi, false, arc..color = W98.shadow);
    canvas.drawArc(rect, -math.pi * 0.25, math.pi, false, arc..color = W98.white);
    final inner = Rect.fromCircle(center: c, radius: r - 1.5);
    canvas.drawArc(inner, math.pi * 0.75, math.pi, false, arc..color = W98.dark);
    canvas.drawArc(inner, -math.pi * 0.25, math.pi, false, arc..color = W98.light);
    if (selected) canvas.drawCircle(c, 2, Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(_RadioPainter old) => old.selected != selected;
}

/// Labelled etched group box ("frame" in VB terms).
class Win98GroupBox extends StatelessWidget {
  const Win98GroupBox({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
            decoration: BoxDecoration(
              border: Border.all(color: W98.shadow),
              boxShadow: const [BoxShadow(color: W98.white, offset: Offset(1, 1))],
              color: W98.face,
            ),
            child: child,
          ),
          Positioned(
            left: 8,
            top: 0,
            child: ColoredBox(
              color: W98.face,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Text(label, style: W98.text),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A modal 9x window with arbitrary content. The window "zooms" out of the
/// centre like the animated windows setting (120 ms, an outline first).
Future<T?> showWin98Window<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext context) builder,
  Widget? icon,
  double width = 320,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    transitionBuilder: (context, a, _, child) => Win98ZoomTransition(animation: a, child: child),
    pageBuilder: (context, _, _) => Center(
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: math.min(width, MediaQuery.sizeOf(context).width - 24),
          child: Win98Bevel(
            style: BevelStyle.window,
            padding: const EdgeInsets.all(3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Win98TitleBar(title: title, icon: icon, onClose: () => Navigator.of(context).pop()),
                DefaultTextStyle(style: W98.text, child: builder(context)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// The 9x "animate windows" effect: a dotted outline grows from the centre,
/// then the window appears.
class Win98ZoomTransition extends StatelessWidget {
  const Win98ZoomTransition({super.key, required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = animation.value;
        if (t >= 0.999) return child!;
        return Stack(
          children: [
            Center(
              child: FractionallySizedBox(
                widthFactor: 0.15 + 0.7 * t,
                heightFactor: 0.08 + 0.5 * t,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: W98.dark.withValues(alpha: 0.7), width: 2),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
