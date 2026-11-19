import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/audio/sfx.dart';
import '../../core/device/upright.dart';
import '../../core/db/media_repository.dart';
import '../../core/device/haptics.dart';
import '../../core/diagnostics/perf_recorder.dart';
import '../../core/providers.dart';
import 'studio_book_screen.dart';
import 'studio_makers.dart';
import 'studio_snapshot.dart';
import 'studio_store.dart';
import 'studio_ui.dart';

/// Studio colours: a dark wooden work table under a warm lamp.
class StudioInk {
  StudioInk._();

  static const table = Color(0xFF3A2418);
  static const tableDark = Color(0xFF24160E);
  static const brass = Color(0xFFD9A35B);
  static const label = Color(0xFFF0C88A);
  static const paper = Color(0xFFF3ECE0);
  static const ink = Color(0xFFF3E9D8);
  static const muted = Color(0xFFC9A57A);
  static const card = Color(0xFF4A3324);
}

/// An image's frameBuilder: eased in as it loads, not popped in over a
/// blank.
Widget studioFadeIn(BuildContext context, Widget child, int? frame, bool sync) => sync
    ? child
    : AnimatedOpacity(
        opacity: frame == null ? 0 : 1,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        child: child,
      );

/// The Studio's sign: a little house with a door.
class StudioHouseIcon extends StatelessWidget {
  const StudioHouseIcon({super.key, this.size = 18, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _HousePainter(color ?? IconTheme.of(context).color ?? StudioInk.ink),
  );
}

class _HousePainter extends CustomPainter {
  const _HousePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // (drawn on a 24-unit grid, like an icon)
    final k = size.width / 24;
    canvas.scale(k);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(4, 21)
        ..lineTo(4, 9)
        ..lineTo(12, 3)
        ..lineTo(20, 9)
        ..lineTo(20, 21)
        ..close(),
      pen,
    );
    canvas.drawPath(
      Path()
        ..moveTo(9.5, 21)
        ..lineTo(9.5, 15)
        ..lineTo(14.5, 15)
        ..lineTo(14.5, 21),
      pen,
    );
  }

  @override
  bool shouldRepaint(_HousePainter old) => old.color != color;
}

/// The table: walnut boards under a desk lamp, its hard-edged pool of
/// warm light up near the tray, the room falling dark beyond it.
class StudioTable extends StatelessWidget {
  const StudioTable({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(color: StudioInk.table),
    child: CustomPaint(painter: Baked('studio table', const _Walnut().paint), child: child),
  );
}

class _Walnut extends CustomPainter {
  const _Walnut();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rnd = math.Random(7);
    // the boards, each its own shade, joined edge to edge
    final board = math.max(70.0, w / 4.6);
    var x = -rnd.nextDouble() * board * 0.5;
    var k = 0;
    while (x < w) {
      final bw = board * (0.85 + rnd.nextDouble() * 0.3);
      final r = Rect.fromLTWH(x, 0, bw, h);
      final tone = rnd.nextDouble();
      canvas.drawRect(
        r,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Color.lerp(const Color(0xFF4A2E19), const Color(0xFF5C3A20), tone)!,
              Color.lerp(const Color(0xFF3E2614), const Color(0xFF52331C), tone)!,
              Color.lerp(const Color(0xFF4A2E19), const Color(0xFF5A381F), tone)!,
            ],
            stops: const [0, 0.55, 1],
          ).createShader(r),
      );
      // the grain: long wavering lines, closer and darker in places
      canvas.save();
      canvas.clipRect(r);
      final seed = math.Random(k * 31 + 5);
      final lines = (bw / 3.2).round();
      for (var i = 0; i < lines; i++) {
        final gx = x + seed.nextDouble() * bw;
        final amp = 1.5 + seed.nextDouble() * 4;
        final len = 120 + seed.nextDouble() * 260;
        final phase = seed.nextDouble() * math.pi * 2;
        final path = Path()..moveTo(gx, -10);
        for (var y = 0.0; y <= h + 10; y += 12) {
          path.lineTo(gx + math.sin(y / len * math.pi * 2 + phase) * amp, y);
        }
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.6 + seed.nextDouble() * 1.2
            ..color = seed.nextDouble() < 0.7
                ? Color.fromRGBO(20, 10, 4, 0.10 + seed.nextDouble() * 0.16)
                : Color.fromRGBO(255, 214, 160, 0.04 + seed.nextDouble() * 0.05),
        );
      }
      // now and then a knot, the grain swirling round it
      if (seed.nextDouble() < 0.5) {
        final c = Offset(x + bw * (0.3 + seed.nextDouble() * 0.4), h * seed.nextDouble());
        for (var ring = 0; ring < 6; ring++) {
          canvas.drawOval(
            Rect.fromCenter(center: c, width: 6.0 + ring * 5, height: 16.0 + ring * 13),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.9
              ..color = Color.fromRGBO(20, 10, 4, 0.22 - ring * 0.03),
          );
        }
      }
      canvas.restore();
      // the joint: a dark seam, a lit edge beside it
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, h),
        Paint()
          ..color = const Color(0xAA140A04)
          ..strokeWidth = 1.6,
      );
      canvas.drawLine(
        Offset(x + 1.6, 0),
        Offset(x + 1.6, h),
        Paint()
          ..color = const Color(0x22FFD9A0)
          ..strokeWidth = 1,
      );
      x += bw;
      k++;
    }
    // the lamp: a pool with a hard rim, warm, over the tray...
    final lamp = Offset(w * 0.5, h * 0.2);
    final reach = math.max(w * 0.78, 260.0);
    canvas.drawCircle(
      lamp,
      reach,
      Paint()
        ..shader = ui.Gradient.radial(
          lamp,
          reach,
          const [Color(0x58FFD08A), Color(0x44FFC878), Color(0x0AFFB060), Color(0x00FFB060)],
          const [0, 0.64, 0.7, 1],
        ),
    );
    // ...and the room beyond it falling into the dark
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          lamp,
          math.max(w, h) * 0.95,
          const [Color(0x00000000), Color(0x00000000), Color(0x8C000000)],
          const [0, 0.42, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_Walnut old) => false;
}

/// The Studio: the prints sent from the corkboard lie on the table, and
/// four things can be made from them (each says how many prints it takes).
/// What's made goes in the book.
class StudioScreen extends ConsumerStatefulWidget {
  const StudioScreen({super.key});

  // (turns with the phone, like the corkboard)
  static Route<void> route() => MaterialPageRoute<void>(
    settings: UprightApp.landscape,
    builder: (_) => const UprightPage(child: StudioScreen()),
  );

  @override
  ConsumerState<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends ConsumerState<StudioScreen> with SingleTickerProviderStateMixin {
  static const _kinds = [StudioKind.strip, StudioKind.collage, StudioKind.scrapbook, StudioKind.flipbook];

  // The prints slide into the tray from the right each time the Studio is
  // opened, one after another, once their pictures are ready (so none is
  // seen loading).
  late final AnimationController _arrive = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  );
  bool _arriving = false;

  // (its own lines in Debug > Performance Report)
  late final String _wasScreen = PerfRecorder.screen;

  @override
  void initState() {
    super.initState();
    _wasScreen;
    PerfRecorder.screen = 'studio';
    unawaited(Sfx.studioSnap.preload());
  }

  @override
  void dispose() {
    PerfRecorder.screen = _wasScreen;
    _arrive.dispose();
    super.dispose();
  }

  void _bringIn(List<MediaItem> prints) {
    if (_arriving || prints.isEmpty) return;
    _arriving = true;
    final ready = Future.wait([
      for (final m in prints.take(8))
        if (m.thumbPath ?? m.outputPath case final path?)
          precacheImage(
            ResizeImage.resizeIfNeeded(300, null, FileImage(File(path))),
            context,
            onError: (_, _) {},
          ),
    ]);
    // (not held up for long by a slow picture)
    unawaited(
      ready.timeout(const Duration(milliseconds: 1200), onTimeout: () => const []).whenComplete(() {
        if (!mounted) return;
        PerfRecorder.mark('studio prints slide in', hold: const Duration(milliseconds: 1000));
        unawaited(_arrive.forward());
      }),
    );
  }

  /// [child], the tray's [i]th print, where it is on its way in.
  Widget _onItsWayIn(int i, Widget child) => AnimatedBuilder(
    animation: _arrive,
    child: child,
    builder: (context, child) {
      if (_arrive.isCompleted) return child!;
      final t = ((_arrive.value - math.min(i, 7) * 0.08) / 0.44).clamp(0.0, 1.0);
      final e = Curves.easeOutCubic.transform(t);
      return Transform.translate(offset: Offset((1 - e) * MediaQuery.sizeOf(context).width, 0), child: child);
    },
  );

  List<MediaItem> _prints() {
    final ids = ref.watch(studioProvider);
    final all = {for (final m in ref.watch(filmItemsProvider).value ?? const <MediaItem>[]) m.id: m};
    // (a print thrown away from the board leaves the Studio too)
    if (all.isNotEmpty && ids.any((id) => !all.containsKey(id))) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(ref.read(studioProvider.notifier).keepOnly(all.keys.toSet())),
      );
    }
    return [
      for (final id in ids)
        if (all[id] case final m? when m.outputPath != null) m,
    ];
  }

  Future<void> _returnAll(List<MediaItem> prints) async {
    if (prints.isEmpty) return;
    final ok = await studioAsk(
      context,
      title: 'Return all to the board?',
      message: 'The ${prints.length} prints go back to their spots on the corkboard.',
      yes: 'Return all',
      no: 'Cancel',
    );
    if (ok == true) await ref.read(studioProvider.notifier).clear();
  }

  /// A little bubble just under the print, pointing up at it: Send Back.
  Future<void> _printMenu(MediaItem m, BuildContext anchor) async {
    final box = anchor.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    unawaited(Haptics.selectionClick());
    final back = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (context, _, _) => _SendBack(below: rect),
      transitionBuilder: (context, a, _, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          alignment: Alignment(((rect.center.dx / MediaQuery.sizeOf(context).width) * 2 - 1), -1),
          scale: Tween(begin: 0.9, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
          child: child,
        ),
      ),
    );
    if (back == true) await ref.read(studioProvider.notifier).remove([m.id]);
  }

  Future<void> _make(StudioKind kind, List<MediaItem> prints) async {
    final needs = StudioNeeds.of(kind);
    if (prints.length < needs.min) return;
    var chosen = prints;
    if (!needs.fits(prints.length)) {
      final picked = await Navigator.of(context).push<List<MediaItem>>(
        MaterialPageRoute(
          settings: UprightApp.landscape,
          builder: (_) => UprightPage(
            child: PickPrints(prints: prints, kind: kind),
          ),
        ),
      );
      if (picked == null || !mounted) return;
      chosen = picked;
    }
    // (each maker its own lines in Debug > Performance Report, and the
    // drop its own: not counted as the Studio sitting idle)
    PerfRecorder.screen = 'maker: ${kind.name}';
    final made = await Navigator.of(context)
        .push<StudioWork>(makerRoute(StudioMaker(kind: kind, prints: chosen)));
    PerfRecorder.screen = 'studio';
    if (made == null || !mounted) return;
    // out of the maker's white flash: the piece lands on the table
    PerfRecorder.mark('studio drop', hold: const Duration(milliseconds: 2800));
    await showSnapshotDrop(context, made);
    // (the prints stay on the table for something else; Return all sends them back)
  }

  @override
  Widget build(BuildContext context) {
    final prints = _prints();
    _bringIn(prints);
    final works = ref.watch(studioBookProvider).value?.length ?? 0;
    final size = MediaQuery.sizeOf(context);
    final sideways = size.width > size.height * 1.2;
    return Scaffold(
      // (text boxes move up out of the keyboard's way; the screen stays put)

      resizeToAvoidBottomInset: false,
      backgroundColor: StudioInk.table,
      body: StudioTable(
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 14, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back to the board',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back, color: StudioInk.ink),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'THE STUDIO',
                              style: TextStyle(
                                color: StudioInk.label,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 4,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              prints.isEmpty
                                  ? 'Nothing on the table yet'
                                  : '${prints.length} print${prints.length == 1 ? '' : 's'} on the table',
                              style: const TextStyle(color: StudioInk.muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      _BookButton(
                        works: works,
                        onTap: () => Navigator.of(context).push(StudioBookScreen.route()),
                      ),
                    ],
                  ),
                ),
              ),
              // the felt tray the prints lie in (hold one to move it along)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 14, 10, 4),
                  child: _FeltTray(
                    child: SizedBox(
                      height: sideways ? 150 : 176,
                      child: prints.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 30),
                                child: Text(
                                  'Open a print on the corkboard and tap Studio to bring it here.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Color(0xFFB9D0C0), height: 1.4),
                                ),
                              ),
                            )
                          : ReorderableListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
                              buildDefaultDragHandles: false,
                              itemCount: prints.length,
                              onReorderItem: (from, to) {
                                unawaited(Haptics.selectionClick());
                                unawaited(ref.read(studioProvider.notifier).move(from, to));
                              },
                              proxyDecorator: (child, _, a) => AnimatedBuilder(
                                animation: a,
                                builder: (_, child) =>
                                    Transform.scale(scale: 1 + 0.08 * a.value, child: child),
                                child: Material(type: MaterialType.transparency, child: child),
                              ),
                              itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
                                key: ValueKey(prints[i].id),
                                index: i,
                                child: _onItsWayIn(
                                  i,
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 7),
                                    child: Builder(
                                      builder: (anchor) => TrayPrint(
                                        item: prints[i],
                                        turn: ((prints[i].id.hashCode % 9) - 4) / 90,
                                        onTap: () => _printMenu(prints[i], anchor),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              // (reordering by holding isn't obvious)
              if (prints.length > 1)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Hold a print to move it along',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: StudioInk.muted, fontSize: 11),
                    ),
                  ),
                ),
              if (prints.isNotEmpty)
                SliverToBoxAdapter(
                  child: Center(
                    child: TextButton.icon(
                      onPressed: () => _returnAll(prints),
                      style: TextButton.styleFrom(
                        foregroundColor: StudioInk.label,
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          fontSize: 12,
                        ),
                      ),
                      icon: const Icon(Icons.push_pin_outlined, size: 15),
                      label: const Text('RETURN ALL TO THE BOARD'),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 18, 14, 24),
                // (sideways: the four cards in one row, under the tray)
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: sideways ? 4 : 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.15,
                    // (sideways: a set height, so the words always fit)
                    mainAxisExtent: sideways ? 116 : null,
                  ),
                  delegate: SliverChildListDelegate([
                    for (final k in _kinds)
                      _MakeCard(kind: k, have: prints.length, onTap: () => _make(k, prints)),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A print lying in the tray.
class TrayPrint extends StatelessWidget {
  const TrayPrint({super.key, required this.item, this.turn = 0, this.onTap, this.selected = false});

  final MediaItem item;
  final double turn;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final path = item.thumbPath ?? item.outputPath;
    return GestureDetector(
      onTap: onTap,
      child: Transform.rotate(
        angle: turn,
        child: Container(
          width: 118,
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 16),
          decoration: BoxDecoration(
            color: StudioInk.paper,
            border: selected ? Border.all(color: StudioInk.brass, width: 3) : null,
            boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 8, offset: Offset(0, 4))],
          ),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: path == null
                ? const ColoredBox(color: Color(0xFFE2DACB))
                : Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    cacheWidth: 300,
                    gaplessPlayback: true,
                    frameBuilder: studioFadeIn,
                  ),
          ),
        ),
      ),
    );
  }
}

/// What a card is called, its line icon and how many prints it takes.
(String, IconData) studioKindLook(StudioKind k) => switch (k) {
  StudioKind.strip => ('Photo Strip', Icons.view_agenda_outlined),
  StudioKind.collage => ('Collage', Icons.grid_view),
  StudioKind.scrapbook => ('Scrapbook', Icons.auto_stories_outlined),
  StudioKind.flipbook => ('Flip Book', Icons.slideshow_outlined),
};

class _MakeCard extends StatelessWidget {
  const _MakeCard({required this.kind, required this.have, required this.onTap});

  final StudioKind kind;
  final int have;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final needs = StudioNeeds.of(kind);
    final ready = have >= needs.min;
    final (name, icon) = studioKindLook(kind);
    final more = needs.min - have;
    final note = ready
        ? (needs.fits(have) ? 'ready' : 'pick ${have > needs.max ? 'up to ${needs.max}' : 'which'}')
        : '$more more needed';
    final fg = ready ? const Color(0xFF2A1A10) : StudioInk.muted;
    return Semantics(
      button: true,
      enabled: ready,
      label: '$name, ${needs.label}, $note',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: ready
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFF7EEDC), Color(0xFFE6D8BD)],
                  )
                : null,
            color: ready ? null : StudioInk.card,
            border: Border.all(color: ready ? const Color(0xFFC9A87A) : const Color(0x22FFE0B0)),
            boxShadow: ready
                ? const [BoxShadow(color: Color(0x73000000), blurRadius: 12, offset: Offset(0, 6))]
                : null,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: ready ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: fg, size: 28),
                  const Spacer(),
                  Text(
                    name,
                    style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${needs.label} · $note',
                    style: TextStyle(color: ready ? const Color(0xFF6A5340) : StudioInk.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Picking which prints go in (more on the table than a piece takes, or a
/// collage's count not matching).
class PickPrints extends StatefulWidget {
  const PickPrints({super.key, required this.prints, required this.kind});

  final List<MediaItem> prints;
  final StudioKind kind;

  @override
  State<PickPrints> createState() => _PickPrintsState();
}

class _PickPrintsState extends State<PickPrints> {
  final _picked = <String>[];

  @override
  Widget build(BuildContext context) {
    final needs = StudioNeeds.of(widget.kind);
    final ok = needs.fits(_picked.length);
    final (name, _) = studioKindLook(widget.kind);
    return Scaffold(
      // (text boxes move up out of the keyboard's way; the screen stays put)

      resizeToAvoidBottomInset: false,
      backgroundColor: StudioInk.table,
      appBar: StudioTitleBar(title: 'Pick prints', subtitle: 'For the $name · ${needs.label}'),
      body: StudioTable(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                '${_picked.length} picked',
                style: const TextStyle(
                  color: StudioInk.label,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            Expanded(
              child: GridView.count(
                crossAxisCount: 3,
                padding: const EdgeInsets.all(18),
                mainAxisSpacing: 18,
                crossAxisSpacing: 14,
                children: [
                  for (final m in widget.prints)
                    Center(
                      child: TrayPrint(
                        item: m,
                        selected: _picked.contains(m.id),
                        onTap: () => setState(() {
                          if (!_picked.remove(m.id) && _picked.length < needs.max) _picked.add(m.id);
                        }),
                      ),
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: StudioInk.brass,
                      foregroundColor: const Color(0xFF22150B),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        fontSize: 15,
                      ),
                    ),
                    onPressed: ok
                        ? () => Navigator.pop(context, [
                            for (final id in _picked) widget.prints.firstWhere((m) => m.id == id),
                          ])
                        : null,
                    child: const Text('Use these'),
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

/// The tray the prints lie in: a wooden photo box, brass at its corners,
/// lined with green felt that catches the lamp.
class _FeltTray extends StatelessWidget {
  const _FeltTray({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(color: Color(0xAA000000), blurRadius: 22, offset: Offset(0, 14)),
            BoxShadow(color: Color(0x55000000), blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x33FFE0B0)),
        ),
        child: CustomPaint(
          painter: Baked('studio box rim', const _BoxRim().paint),
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              boxShadow: [BoxShadow(color: Color(0x66FFE0B0), offset: Offset(0, 1))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: CustomPaint(
                painter: Baked('studio felt', const _Felt().paint),
                foregroundPainter: const _FeltShade(),
                child: child,
              ),
            ),
          ),
        ),
      ),
      for (final a in const [
        Alignment.topLeft,
        Alignment.topRight,
        Alignment.bottomLeft,
        Alignment.bottomRight,
      ])
        Positioned.fill(
          child: Align(
            alignment: a,
            child: Transform.translate(offset: Offset(a.x * 3, a.y * 3), child: const _BrassCorner()),
          ),
        ),
    ],
  );
}

/// The box's rim: walnut, its grain running round, lit from the lamp above.
class _BoxRim extends CustomPainter {
  const _BoxRim();

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8));
    canvas.drawRRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF8E5E36), Color(0xFF6A4224), Color(0xFF4E2F17)],
        ).createShader(Offset.zero & size),
    );
    final rnd = math.Random(3);
    canvas.save();
    canvas.clipRRect(r);
    for (var i = 0; i < 70; i++) {
      final y = rnd.nextDouble() * size.height;
      final path = Path()..moveTo(-5, y);
      for (var x = 0.0; x <= size.width + 10; x += 14) {
        path.lineTo(x, y + math.sin(x / 90 + i) * 1.4);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6 + rnd.nextDouble()
          ..color = Color.fromRGBO(30, 14, 5, 0.12 + rnd.nextDouble() * 0.14),
      );
    }
    canvas.restore();
    // a lit top edge
    canvas.drawRRect(
      r.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x66FFDDAA), Color(0x00FFDDAA)],
          stops: [0, 0.35],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_BoxRim old) => false;
}

/// A little brass corner cap, a nail in it.
class _BrassCorner extends StatelessWidget {
  const _BrassCorner();

  @override
  Widget build(BuildContext context) => Container(
    width: 20,
    height: 20,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(3),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF6DD9C), Color(0xFFC9A04F), Color(0xFF8C6A28)],
      ),
      boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 3, offset: Offset(1, 2))],
    ),
    child: Center(
      child: Container(
        width: 5,
        height: 5,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: Alignment(-0.4, -0.4),
            colors: [Color(0xFFFFF0C8), Color(0xFF7A5A20)],
          ),
        ),
      ),
    ),
  );
}

/// The felt: green baize, its nap in short fibres, a little mottled.
class _Felt extends CustomPainter {
  const _Felt();

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = const Color(0xFF2B5640));
    final rnd = math.Random(11);
    // soft mottling: the nap lying different ways
    for (var i = 0; i < 26; i++) {
      final c = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      final rad = 20 + rnd.nextDouble() * 60;
      canvas.drawCircle(
        c,
        rad,
        Paint()
          ..color = rnd.nextBool() ? const Color(0x0C000000) : const Color(0x0AB8F0C8)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, rad * 0.6),
      );
    }
    // the fibres: short strokes every way
    final f = Paint()..strokeCap = StrokeCap.round;
    final n = (size.width * size.height / 7).round().clamp(800, 40000);
    for (var i = 0; i < n; i++) {
      final p = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      final a = rnd.nextDouble() * math.pi;
      final len = 0.8 + rnd.nextDouble() * 1.8;
      f
        ..strokeWidth = 0.5 + rnd.nextDouble() * 0.5
        ..color = rnd.nextDouble() < 0.55 ? const Color(0x1A001408) : const Color(0x14D8FFE4);
      canvas.drawLine(p, p + Offset(math.cos(a) * len, math.sin(a) * len), f);
    }
  }

  @override
  bool shouldRepaint(_Felt old) => false;
}

/// Over the felt and the prints on it: sunk below the rim (shadow round
/// its edges), the lamp's light falling across it.
class _FeltShade extends CustomPainter {
  const _FeltShade();

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.radial(Offset(size.width * 0.5, -size.height * 0.2), size.width * 0.85, const [
          Color(0x22FFE6B0),
          Color(0x00FFE6B0),
        ]),
    );
    canvas.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x8C000000), Color(0x00000000), Color(0x00000000), Color(0x33000000)],
          stops: [0, 0.14, 0.86, 1],
        ).createShader(r),
    );
    canvas.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x55000000), Color(0x00000000), Color(0x00000000), Color(0x55000000)],
          stops: [0, 0.05, 0.95, 1],
        ).createShader(r),
    );
  }

  @override
  bool shouldRepaint(_FeltShade old) => false;
}

/// The book's button: a little open album and how many pieces are in it.
class _BookButton extends StatelessWidget {
  const _BookButton({required this.works, required this.onTap});

  final int works;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Your book, $works pieces',
    child: Material(
      color: const Color(0xFF5A3A24),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CustomPaint(size: Size(42, 34), painter: _OpenAlbum()),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'BOOK',
                    style: TextStyle(
                      color: StudioInk.label,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    works == 1 ? '1 piece' : '$works pieces',
                    style: const TextStyle(color: StudioInk.muted, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// An open album: leather cover, two cream pages, a photo on each.
class _OpenAlbum extends CustomPainter {
  const _OpenAlbum();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final cover = Path()
      ..moveTo(w * 0.02, h * 0.2)
      ..quadraticBezierTo(w * 0.25, h * 0.1, w * 0.5, h * 0.2)
      ..quadraticBezierTo(w * 0.75, h * 0.1, w * 0.98, h * 0.2)
      ..lineTo(w * 0.98, h * 0.96)
      ..quadraticBezierTo(w * 0.75, h * 0.86, w * 0.5, h * 0.98)
      ..quadraticBezierTo(w * 0.25, h * 0.86, w * 0.02, h * 0.96)
      ..close();
    canvas.drawShadow(cover, const Color(0xFF000000), 2, false);
    canvas.drawPath(cover, Paint()..color = const Color(0xFF7A4A2A));
    Path page(double l, double r) {
      final m = (l + r) / 2;
      return Path()
        ..moveTo(w * l, h * 0.14)
        ..quadraticBezierTo(w * m, h * 0.04, w * r, h * 0.14)
        ..lineTo(w * r, h * 0.86)
        ..quadraticBezierTo(w * m, h * 0.76, w * l, h * 0.86)
        ..close();
    }

    canvas.drawPath(page(0.07, 0.5), Paint()..color = const Color(0xFFF2EADB));
    canvas.drawPath(page(0.5, 0.93), Paint()..color = const Color(0xFFEDE3D0));
    // the gutter
    canvas.drawLine(
      Offset(w * 0.5, h * 0.14),
      Offset(w * 0.5, h * 0.9),
      Paint()
        ..color = const Color(0x55402510)
        ..strokeWidth = 1.2,
    );
    // a photo on each page, slightly turned
    void photo(Offset c, double turn, Color a, Color b) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(turn);
      final r = Rect.fromCenter(center: Offset.zero, width: w * 0.26, height: h * 0.36);
      canvas.drawRect(r.inflate(1.4), Paint()..color = const Color(0xFFFFFFFF));
      canvas.drawRect(r, Paint()..shader = LinearGradient(colors: [a, b]).createShader(r));
      canvas.restore();
    }

    photo(Offset(w * 0.28, h * 0.46), -0.08, const Color(0xFF7AA0C4), const Color(0xFFE0B48A));
    photo(Offset(w * 0.72, h * 0.5), 0.07, const Color(0xFFC2786A), const Color(0xFFF2C78E));
  }

  @override
  bool shouldRepaint(_OpenAlbum old) => false;
}

/// "Send Back" in a small bubble under a print, its point aimed up at it.
class _SendBack extends StatelessWidget {
  const _SendBack({required this.below});

  final Rect below;

  @override
  Widget build(BuildContext context) {
    const width = 150.0, arrow = 9.0;
    final screen = MediaQuery.sizeOf(context);
    final left = (below.center.dx - width / 2).clamp(10.0, screen.width - width - 10);
    return Stack(
      children: [
        Positioned(
          left: left,
          top: below.bottom + 2,
          width: width,
          child: CustomPaint(
            painter: _Bubble(tip: below.center.dx - left, arrow: arrow),
            child: Padding(
              padding: const EdgeInsets.only(top: arrow),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(context).pop(true),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.push_pin_outlined, size: 17, color: Color(0xFF2A1A10)),
                        SizedBox(width: 6),
                        Text(
                          'Send Back',
                          style: TextStyle(
                            color: Color(0xFF2A1A10),
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends CustomPainter {
  const _Bubble({required this.tip, required this.arrow});

  final double tip, arrow;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, arrow, size.width, size.height - arrow),
      const Radius.circular(12),
    );
    final t = tip.clamp(18.0, size.width - 18);
    final path = Path()
      ..addRRect(body)
      ..moveTo(t - arrow, arrow + 0.5)
      ..lineTo(t, 0)
      ..lineTo(t + arrow, arrow + 0.5)
      ..close();
    canvas.drawShadow(path, const Color(0xFF000000), 6, false);
    canvas.drawPath(path, Paint()..color = StudioInk.paper);
  }

  @override
  bool shouldRepaint(_Bubble old) => old.tip != tip;
}
