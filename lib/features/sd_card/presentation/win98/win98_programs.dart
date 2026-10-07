import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'pixel_icons.dart';
import 'win98_widgets.dart';

/// The little programs Start > Run can open (hinted at in Tip of the Day).

/// RABBIT.EXE: the rabbit hops back and forth across a little field.
Future<void> showRabbitExe(BuildContext context) => showWin98Window<void>(
  context,
  title: 'RABBIT.EXE',
  width: 300,
  icon: const PixelIconView(PixelIcon.rabbit),
  builder: (context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Win98Bevel(
          style: BevelStyle.sunken,
          color: Color(0xFF9ED36A),
          child: SizedBox(height: 110, child: _Hopper()),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(child: Text('Hop.')),
            Win98Button(minWidth: 76, onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
          ],
        ),
      ],
    ),
  ),
);

class _Hopper extends StatefulWidget {
  const _Hopper();

  @override
  State<_Hopper> createState() => _HopperState();
}

class _HopperState extends State<_Hopper> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          // There and back again: x runs a triangle wave, hops on top.
          final t = _c.value;
          final there = t < 0.5;
          final u = there ? t * 2 : 2 - t * 2;
          const size = 32.0;
          final x = u * (box.maxWidth - size);
          final hop = (math.sin(t * math.pi * 16)).abs() * 34;
          return Stack(
            children: [
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 18,
                child: ColoredBox(color: Color(0xFF6FA84A)),
              ),
              Positioned(
                left: x,
                bottom: 14 + hop,
                child: Transform.flip(
                  flipX: !there,
                  child: const PixelIconView(PixelIcon.rabbit, size: size),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// An MS-DOS Prompt window that types out [lines], one every so often.
Future<void> showDosPrompt(BuildContext context, {required String command, required List<String> lines}) =>
    showWin98Window<void>(
      context,
      title: 'MS-DOS Prompt',
      width: 330,
      icon: const PixelIconView(PixelIcon.computer),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Console(lines: ['C:\\DARKROOM>$command', ...lines]),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Win98Button(
                minWidth: 76,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );

class _Console extends StatefulWidget {
  const _Console({required this.lines});

  final List<String> lines;

  @override
  State<_Console> createState() => _ConsoleState();
}

class _ConsoleState extends State<_Console> {
  int _shown = 1;
  Timer? _t;
  bool _cursor = true;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 420), (_) {
      if (!mounted) return;
      setState(() {
        _cursor = !_cursor;
        if (_shown < widget.lines.length) _shown++;
      });
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = _shown >= widget.lines.length;
    final text = [...widget.lines.take(_shown), if (done) 'C:\\DARKROOM>${_cursor ? '_' : ''}'].join('\n');
    return Container(
      height: 190,
      color: Colors.black,
      padding: const EdgeInsets.all(6),
      alignment: Alignment.topLeft,
      child: Text(text, style: W98.text.copyWith(color: const Color(0xFFC0C0C0), fontSize: 11, height: 1.3)),
    );
  }
}

/// Notepad with a read-only text file.
Future<void> showNotepad(BuildContext context, {required String file, required String text}) =>
    showWin98Window<void>(
      context,
      title: '$file - Notepad',
      width: 330,
      icon: const PixelIconView(PixelIcon.info),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: Win98Bevel(
                style: BevelStyle.sunken,
                color: Colors.white,
                padding: const EdgeInsets.all(6),
                child: SingleChildScrollView(child: Text(text, style: W98.text.copyWith(fontSize: 12))),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Win98Button(
                minWidth: 76,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ),
          ],
        ),
      ),
    );

const readmeText = '''DARKROOM 98 - README.TXT

Thanks for using Darkroom 98!

Things you can run from Start > Run...

  SOL.EXE       Solitaire
  BRICKS.EXE    knock down the wall
  PINBALL.EXE   Space Rabbit Pinball
  RABBIT.EXE    say hello to the mascot
  DEVELOP.BAT   how your film is made
  PING          how long until your prints?
  DEFRAG        tidy up the SD card
  WINVER        version information
  A:  C:  E:    jump to a drive

Known issues:
  - There is no Minesweeper.
  - Film cannot be rushed.
''';

const developLines = [
  'Loading developer...............OK',
  'Rolling film onto the reel......OK',
  'Developer, 20C, agitate 10s/min',
  '  [##########] done',
  'Stop bath.......................OK',
  'Fixer...........................OK',
  'Wash............................OK',
  'Hanging to dry..................OK',
  '',
  'Film cannot be rushed.',
  'Your prints will be on the corkboard.',
];

const pingLines = [
  'Pinging corkboard [darkroom] with 32 bytes of film:',
  '',
  'Reply from darkroom: bytes=32 time=5min TTL=98',
  'Reply from darkroom: bytes=32 time=5min TTL=98',
  'Reply from darkroom: bytes=32 time=5min TTL=98',
  'Reply from darkroom: bytes=32 time=20s TTL=600 (instant)',
  '',
  'Ping statistics: 4 sent, 4 developed, 0 lost.',
];
