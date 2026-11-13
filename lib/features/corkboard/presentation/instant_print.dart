import 'package:material_ui/material_ui.dart';

import '../../../core/processing/instant_frame.dart';
import '../../../core/processing/paper_wear.dart';

/// An instant print: square picture on textured off-white paper with a deep
/// writing strip.
///
/// [develop] runs 0 -> 1 while the print develops: it starts as an even
/// blue-grey sheet, the picture surfaces through it, and the colour comes in
/// last, like the real chemistry.
class InstantPrint extends StatelessWidget {
  const InstantPrint({
    super.key,
    required this.picture,
    this.note,
    this.develop = 1,
    this.onNoteTap,
    this.shadow = true,
    this.style = InstantStyle.classic,
    this.wear,
  });

  /// The paper as a real sheet (see PaperWear); null: drawn plain (small
  /// previews).
  final PaperWear? wear;

  /// The frame's colour or design (and the note's ink to suit it).
  final InstantStyle style;

  final Widget picture;
  final String? note;
  final double develop;
  final VoidCallback? onNoteTap;
  final bool shadow;

  static const _undeveloped = Color(0xFF34444C);

  static ColorFilter _saturation(double s) {
    const r = 0.2126, g = 0.7152, b = 0.0722;
    final i = 1 - s;
    return ColorFilter.matrix([
      r * i + s, g * i, b * i, 0, 0, //
      r * i, g * i + s, b * i, 0, 0, //
      r * i, g * i, b * i + s, 0, 0, //
      0, 0, 0, 1, 0,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: InstantFrame.aspect,
      child: LayoutBuilder(
        builder: (context, box) {
          final s = box.maxWidth / (1 + 2 * InstantFrame.side);
          final pic = InstantFrame.pictureRect(s);
          final strip = InstantFrame.noteRect(s);
          final p = develop.clamp(0.0, 1.0);
          final text = note?.trim() ?? '';
          PaperTexture.ensureLoaded();
          final wear = this.wear;
          final worn = wear != null && wear.on;
          final print = DecoratedBox(
            decoration: BoxDecoration(
              color: style.paper,
              boxShadow: shadow && !worn
                  ? const [BoxShadow(color: Colors.black45, blurRadius: 7, offset: Offset(3, 5))]
                  : null,
            ),
            child: Stack(
              children: [
                // Embossed off-white surface, like the real frame.
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _PaperPainter(dpr: MediaQuery.devicePixelRatioOf(context), style: style),
                    ),
                  ),
                ),
                Positioned.fromRect(
                  rect: pic,
                  child: ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (p >= 1)
                          picture
                        else
                          ColorFiltered(colorFilter: _saturation(p * p), child: picture),
                        if (p < 1)
                          ColoredBox(
                            color: _undeveloped.withValues(
                              alpha: (1 - Curves.easeOut.transform(p)).clamp(0, 1),
                            ),
                          ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.fromBorderSide(BorderSide(color: Color(0x22000000), width: 0.6)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned.fromRect(
                  rect: strip,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onNoteTap,
                    child: Center(
                      child: Transform.rotate(
                        angle: InstantFrame.noteAngle,
                        child: text.isEmpty
                            ? (onNoteTap == null
                                  ? const SizedBox.shrink()
                                  : Text(
                                      'tap to write…',
                                      style: InstantFrame.noteStyle(
                                        s,
                                      ).copyWith(color: style.ink.withValues(alpha: 0.3)),
                                    ))
                            : SizedBox(
                                // Same line width as the exported file.
                                width: s * 0.94,
                                child: Text(
                                  text,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: InstantFrame.noteStyle(s, color: style.ink),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
          if (!worn) return print;
          return WornSheet(wear: wear, shadow: shadow, paper: style.paper, window: (_) => pic, child: print);
        },
      ),
    );
  }
}

class _PaperPainter extends CustomPainter {
  _PaperPainter({required this.dpr, required this.style}) : super(repaint: PaperTexture.loaded);

  final double dpr;
  final InstantStyle style;

  @override
  void paint(Canvas canvas, Size size) => InstantFrame.paintPaper(
    canvas,
    Offset.zero & size,
    PaperTexture.loaded.value,
    style,
    minTexel: 1 / dpr,
  );

  @override
  bool shouldRepaint(_PaperPainter old) => old.dpr != dpr || old.style != style;
}
