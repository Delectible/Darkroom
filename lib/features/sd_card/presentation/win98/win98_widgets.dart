import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/audio/sfx.dart';
import '../../../../core/diagnostics/perf_recorder.dart';

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
    fontFamily: 'W98',
    fontSize: 12,
    color: Colors.black,
    fontWeight: FontWeight.w400,
    height: 1.2,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  static const disabledText = TextStyle(
    fontFamily: 'W98',
    fontSize: 12,
    color: shadow,
    height: 1.2,
    decoration: TextDecoration.none,
    shadows: [Shadow(color: white, offset: Offset(1, 1))],
  );
}

enum BevelStyle { raised, pressed, window, sunken, shallow }

/// Two-ring 3D border exactly like the 9x control frames.
/// Draws a Win98 screen, dialog or menu uniformly larger, so the 9x look
/// keeps its exact proportions but is comfortable to touch: the subtree lays
/// out on a smaller virtual screen and is scaled up to fill the real one
/// (text and pixel art stay sharp; hit testing follows the scale).
/// SafeArea for the Win98 screens. Upright it's the usual one; turned to
/// landscape the status bar is hidden and the sides only keep clear of the
/// camera cutout itself (a whole status-bar-wide strip down the side wasted
/// a tenth of the screen), less [covered] (a bezel already round it).
class Win98Safe extends StatelessWidget {
  const Win98Safe({super.key, required this.child, this.covered = 0});

  final Widget child;
  final double covered;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (mq.size.width <= mq.size.height) return SafeArea(child: child);
    var left = 0.0, right = 0.0;
    final cutouts = mq.displayFeatures.where((f) => f.type == ui.DisplayFeatureType.cutout).toList();
    if (cutouts.isEmpty) {
      left = mq.padding.left;
      right = mq.padding.right;
    }
    for (final f in cutouts) {
      if (f.bounds.center.dx < mq.size.width / 2) {
        left = math.max(left, f.bounds.right);
      } else {
        right = math.max(right, mq.size.width - f.bounds.left);
      }
    }
    return SafeArea(
      left: false,
      right: false,
      child: Padding(
        padding: EdgeInsets.only(left: math.max(0, left - covered), right: math.max(0, right - covered)),
        child: child,
      ),
    );
  }
}

class Win98Scale extends StatelessWidget {
  const Win98Scale({super.key, required this.child});

  /// Portrait: 1.3x so the pixel UI is easy to hit. Landscape is short
  /// (about 410 dp), so it lays out 1:1 and gets the room back.
  static const factor = 1.3;

  static double factorFor(Size s) => s.width > s.height ? 1.0 : factor;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth.isFinite ? box.maxWidth : mq.size.width;
        final h = box.maxHeight.isFinite ? box.maxHeight : mq.size.height;
        final factor = factorFor(mq.size);
        return SizedBox(
          width: w,
          height: h,
          child: FittedBox(
            fit: BoxFit.fill,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: w / factor,
              height: h / factor,
              child: MediaQuery(
                data: mq.copyWith(
                  size: mq.size / factor,
                  padding: mq.padding / factor,
                  viewPadding: mq.viewPadding / factor,
                  viewInsets: mq.viewInsets / factor,
                  systemGestureInsets: mq.systemGestureInsets / factor,
                ),
                // Anything without its own style still gets the pixel font.
                child: DefaultTextStyle.merge(
                  style: const TextStyle(fontFamily: 'W98'),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

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
                Sfx.w98Click.play();
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
    // The button looks 18x16 like the real one, but the touch target is the
    // whole slot around it.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Sfx.w98Click.play();
        (onPressed ?? () {})();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        child: SizedBox(
          width: 18,
          height: 16,
          child: Win98Button(
            onPressed: onPressed ?? () {},
            padding: EdgeInsets.zero,
            child: switch (glyph) {
              '_' => const Win98GlyphView(Win98Glyph.minimize, dot: 1.2),
              '□' => const Win98GlyphView(Win98Glyph.maximize, dot: 1.1),
              '×' => const Win98GlyphView(Win98Glyph.close, dot: 1.2),
              _ => Text(glyph, style: W98.text.copyWith(fontSize: 11, height: 1)),
            },
          ),
        ),
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

/// Opens a drop-down menu under [anchor]. [siblings] are the other titles
/// of the same menu bar: touching one while this menu is open switches
/// straight to it ([onSwitch] gets its index), like the real thing, instead
/// of needing one tap to close and another to open.
Future<void> showWin98Menu(
  BuildContext anchor,
  List<Win98MenuItem> items, {
  List<GlobalKey> siblings = const [],
  ValueChanged<int>? onSwitch,
}) async {
  PerfRecorder.mark('win98 menu', hold: const Duration(milliseconds: 600));
  final box = anchor.findRenderObject()! as RenderBox;
  // In the navigator's own frame (the UI may be turned to landscape).
  final frame = Navigator.of(anchor).overlay?.context.findRenderObject() as RenderBox?;
  final topLeft = box.localToGlobal(Offset(0, box.size.height), ancestor: frame);
  final f = Win98Scale.factorFor(MediaQuery.sizeOf(anchor));
  final picked = await showGeneralDialog<Object>(
    context: anchor,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, _) => Stack(
      children: [
        // Our own barrier: closes the menu, or hands over to another title.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              for (var i = 0; i < siblings.length; i++) {
                final r = siblings[i].currentContext?.findRenderObject();
                if (r is RenderBox && r.attached) {
                  if ((Offset.zero & r.size).contains(r.globalToLocal(d.globalPosition))) {
                    Navigator.of(context).pop(i);
                    return;
                  }
                }
              }
              Navigator.of(context).pop();
            },
          ),
        ),
        Win98Scale(
          child: Builder(
            builder: (context) {
              // Anchor is in real screen pixels; the menu lays out scaled.
              final screen = MediaQuery.sizeOf(context);
              return Stack(
                children: [
                  Positioned(
                    left: math.min(topLeft.dx / f, screen.width - 200),
                    top: topLeft.dy / f,
                    child: _MenuPanel(items: items),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
  if (picked is int) {
    onSwitch?.call(picked);
    return;
  }
  if (picked is Win98MenuItem) {
    if (picked.onSelected != null) Sfx.w98Click.play();
    picked.onSelected?.call();
  }
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
                        padding: const EdgeInsets.fromLTRB(4, 8, 18, 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 18,
                              child: widget.items[i].checked && !widget.items[i].radio
                                  ? Center(
                                      child: Win98GlyphView(
                                        Win98Glyph.check,
                                        color: _hot == i ? Colors.white : Colors.black,
                                      ),
                                    )
                                  : widget.items[i].checked
                                  ? Text(
                                      '•',
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

class Win98MenuBar extends StatefulWidget {
  const Win98MenuBar({super.key, required this.menus});

  final Map<String, List<Win98MenuItem> Function()> menus;

  @override
  State<Win98MenuBar> createState() => _Win98MenuBarState();
}

class _Win98MenuBarState extends State<Win98MenuBar> {
  final List<GlobalKey> _keys = [];
  int? _open;

  Future<void> _show(int i) async {
    final entries = widget.menus.entries.toList();
    final ctx = _keys[i].currentContext;
    if (ctx == null) return;
    Sfx.w98Click.play();
    setState(() => _open = i);
    int? next;
    await showWin98Menu(ctx, entries[i].value(), siblings: _keys, onSwitch: (j) => next = j == i ? null : j);
    if (!mounted) return;
    setState(() => _open = null);
    if (next != null) await _show(next!);
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.menus.entries.toList();
    while (_keys.length < entries.length) {
      _keys.add(GlobalKey());
    }
    return SizedBox(
      height: 30,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < entries.length; i++)
              GestureDetector(
                key: _keys[i],
                behavior: HitTestBehavior.opaque,
                // Opens on touch-down: no waiting for the finger to lift.
                onTapDown: (_) => unawaited(_show(i)),
                child: Container(
                  height: 30,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: _MenuTitle(
                    open: _open == i,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: entries[i].key[0],
                            style: const TextStyle(decoration: TextDecoration.underline),
                          ),
                          TextSpan(text: entries[i].key.substring(1)),
                        ],
                      ),
                      style: W98.text,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A menu-bar title: sunk in while its menu is open.
class _MenuTitle extends StatelessWidget {
  const _MenuTitle({required this.open, required this.child});

  final bool open;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const pad = EdgeInsets.symmetric(horizontal: 3, vertical: 2);
    if (!open) return Padding(padding: pad + const EdgeInsets.all(1), child: child);
    return Win98Bevel(style: BevelStyle.shallow, padding: pad, child: child);
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
          // Tabs shrink to share the strip (labels scale down rather than
          // running past the window edge).
          for (var i = 0; i < tabs.length; i++)
            Flexible(
              // Share by natural width: short tabs (A:, C:) don't hold space
              // the long ones need.
              flex: 4 + tabs[i].label.length,
              child: GestureDetector(
                onTap: tabs[i].enabled ? () => onSelect(i) : null,
                child: Transform.translate(
                  offset: Offset(0, i == selected ? 2 : 0),
                  child: Container(
                    height: i == selected ? 26 : 22,
                    margin: EdgeInsets.only(left: i == 0 ? 2 : 0),
                    child: CustomPaint(
                      painter: _TabPainter(selected: i == selected),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(5, 4, 5, 2),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
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
  // Errors bong, warnings ding; questions and notes stay quiet so the
  // everyday prompts never get tiresome.
  switch (icon) {
    case Win98MessageIcon.error:
      Sfx.w98Error.play();
    case Win98MessageIcon.warning:
      Sfx.w98Ding.play();
    case Win98MessageIcon.info || Win98MessageIcon.question:
      break;
  }
  return showGeneralDialog<int>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, _) => Win98Scale(
      child: Center(
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
                    ? const Center(child: Win98GlyphView(Win98Glyph.check, dot: 1.2))
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
  PerfRecorder.mark('win98 window: $title', hold: const Duration(milliseconds: 800));
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    transitionBuilder: (context, a, _, child) => Win98ZoomTransition(animation: a, child: child),
    pageBuilder: (context, _, _) => Win98Scale(
      child: Center(
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

/// 9x trackbar: sunken groove, raised pointer thumb, tick marks underneath.
class Win98Slider extends StatelessWidget {
  const Win98Slider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.ticks = 10,
    this.enabled = true,
  });

  /// 0..1
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final int ticks;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    const thumbW = 11.0, thumbH = 20.0;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final track = w - thumbW;
        double at(Offset p) => ((p.dx - thumbW / 2) / track).clamp(0.0, 1.0);
        final x = track * value.clamp(0.0, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (d) => onChanged(at(d.localPosition)) : null,
          onTapUp: enabled ? (d) => onChangeEnd?.call(at(d.localPosition)) : null,
          onHorizontalDragUpdate: enabled ? (d) => onChanged(at(d.localPosition)) : null,
          onHorizontalDragEnd: enabled ? (_) => onChangeEnd?.call(value) : null,
          child: SizedBox(
            height: 30,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Groove.
                const Positioned(
                  left: thumbW / 2,
                  right: thumbW / 2,
                  top: 8,
                  child: SizedBox(
                    height: 4,
                    child: Win98Bevel(style: BevelStyle.sunken, color: W98.light, child: SizedBox.expand()),
                  ),
                ),
                // Ticks.
                for (var i = 0; i <= ticks; i++)
                  Positioned(
                    left: thumbW / 2 + track * i / ticks,
                    top: 24,
                    child: Container(width: 1, height: 4, color: W98.dark),
                  ),
                // Pointer thumb.
                Positioned(
                  left: x,
                  top: 0,
                  child: Opacity(
                    opacity: enabled ? 1 : 0.5,
                    child: const CustomPaint(size: Size(thumbW, thumbH), painter: _TrackThumbPainter()),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The pointed trackbar thumb with its 3D edges.
class _TrackThumbPainter extends CustomPainter {
  const _TrackThumbPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, tip = h - w / 2;
    final body = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, tip)
      ..lineTo(w / 2, h)
      ..lineTo(0, tip)
      ..close();
    canvas.drawPath(body, Paint()..color = W98.face);
    final hi = Paint()
      ..color = W98.white
      ..strokeWidth = 1;
    final lo = Paint()
      ..color = W98.dark
      ..strokeWidth = 1;
    final mid = Paint()
      ..color = W98.shadow
      ..strokeWidth = 1;
    canvas.drawLine(const Offset(0.5, 0.5), Offset(w - 0.5, 0.5), hi);
    canvas.drawLine(const Offset(0.5, 0.5), Offset(0.5, tip), hi);
    canvas.drawLine(Offset(0.5, tip), Offset(w / 2, h - 0.5), hi);
    canvas.drawLine(Offset(w - 0.5, 0.5), Offset(w - 0.5, tip), lo);
    canvas.drawLine(Offset(w - 0.5, tip), Offset(w / 2, h - 0.5), lo);
    canvas.drawLine(Offset(w - 1.5, 1.5), Offset(w - 1.5, tip - 0.5), mid);
  }

  @override
  bool shouldRepaint(_TrackThumbPainter old) => false;
}

/// The little bitmap symbols 9x drew on caption buttons, menus, check boxes
/// and sort headers (the UI font has no such glyphs, and neither did the
/// real one: they were bitmaps).
enum Win98Glyph {
  minimize(['', '', '', '', '', 'XXXXXX', 'XXXXXX']),
  maximize([
    'XXXXXXXXX',
    'XXXXXXXXX',
    'X.......X',
    'X.......X',
    'X.......X',
    'X.......X',
    'X.......X',
    'XXXXXXXXX',
  ]),
  close(['XX....XX', '.XX..XX.', '..XXXX..', '...XX...', '..XXXX..', '.XX..XX.', 'XX....XX']),
  check(['......X', '.....XX', 'X...XXX', 'XX.XXX.', 'XXXXX..', '.XXX...', '..X....']),
  left(['...X', '..XX', '.XXX', 'XXXX', '.XXX', '..XX', '...X']),
  right(['X...', 'XX..', 'XXX.', 'XXXX', 'XXX.', 'XX..', 'X...']),
  up(['...X...', '..XXX..', '.XXXXX.', 'XXXXXXX']),
  down(['XXXXXXX', '.XXXXX.', '..XXX..', '...X...']);

  const Win98Glyph(this.rows);
  final List<String> rows;
}

/// Draws a [Win98Glyph] as crisp pixels, [dot] logical px per bitmap pixel.
class Win98GlyphView extends StatelessWidget {
  const Win98GlyphView(this.glyph, {super.key, this.dot = 1.4, this.color = W98.dark});

  final Win98Glyph glyph;
  final double dot;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final w = glyph.rows.fold<int>(0, (m, r) => math.max(m, r.length));
    return CustomPaint(
      size: Size(w * dot, glyph.rows.length * dot),
      painter: _GlyphPainter(glyph, dot, color),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.dot, this.color);

  final Win98Glyph glyph;
  final double dot;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (var y = 0; y < glyph.rows.length; y++) {
      final row = glyph.rows[y];
      for (var x = 0; x < row.length; x++) {
        if (row[x] == 'X') canvas.drawRect(Rect.fromLTWH(x * dot, y * dot, dot + 0.05, dot + 0.05), p);
      }
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.glyph != glyph || old.dot != dot || old.color != color;
}
