import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The launch screen carried on into the app: the rabbit on near-black (as
/// the system's launch screen left it) with a line of darkroom chatter,
/// held over the app while the camera opens and its look loads, then
/// faded away so the camera is simply there, live, with nothing popping in.
class LaunchCurtain extends StatefulWidget {
  const LaunchCurtain({
    super.key,
    required this.child,
    required this.isReady,
    this.line,
    this.minimum = const Duration(milliseconds: 1100),
    this.maximum = const Duration(seconds: 5),
  });

  final Widget child;

  /// Polled while the curtain is up: true once what's under it is ready.
  final bool Function() isReady;

  /// Which of [lines] to show (a different one each launch); null = random.
  final int? line;

  /// Up at least this long (time to read the line), at most [maximum]
  /// (whatever isn't ready by then finishes in view).
  final Duration minimum, maximum;

  static const background = Color(0xFF0E0E12);

  static const lines = [
    'Loading film',
    'Degaussing monitor',
    'Defragmenting hard drive',
    'Winding on to frame 1',
    'Warming up the safelight',
    'Mixing the developer',
    'Blowing dust off the lens',
    'Rewinding the tapes',
    'Formatting floppy disk',
    'Charging the flash',
    'Feeding the rabbit',
    'Untangling the camera strap',
    'Checking the fixer',
    'Adjusting the tracking',
    'Counting sprocket holes',
    'Inserting disk 2 of 3',
    'Pinning up the prints',
    'Waiting for the kettle',
    'Cleaning the projector gate',
    'Finding the lens cap',
  ];

  @override
  State<LaunchCurtain> createState() => _LaunchCurtainState();
}

class _LaunchCurtainState extends State<LaunchCurtain> with SingleTickerProviderStateMixin {
  late final _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  late final String _line = LaunchCurtain
      .lines[(widget.line ?? math.Random().nextInt(LaunchCurtain.lines.length)) % LaunchCurtain.lines.length];
  // Counted in polls (not a stopwatch) so tests' clocks drive it too.
  var _polls = 0;
  Timer? _poll;
  bool _up = true;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(milliseconds: 100), (_) => _check());
  }

  void _check() {
    final waited = const Duration(milliseconds: 100) * ++_polls;
    if (waited < widget.minimum) return;
    if (waited < widget.maximum && !widget.isReady()) return;
    _poll?.cancel();
    _fade.forward().whenComplete(() {
      if (mounted) setState(() => _up = false);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_up)
          // No touches reach the app until it shows.
          AbsorbPointer(
            child: AnimatedBuilder(
              animation: _fade,
              builder: (context, child) {
                final t = Curves.easeInOut.transform(_fade.value);
                return Opacity(opacity: 1 - t, child: child);
              },
              child: ColoredBox(
                color: LaunchCurtain.background,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Where the launch screen had it (96 dp, centred).
                    Image.asset(
                      'assets/artwork/rabbit_mark.png',
                      width: 96,
                      height: 96,
                      filterQuality: FilterQuality.medium,
                    ),
                    Transform.translate(
                      offset: const Offset(0, 86),
                      child: _Chatter(line: _line),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The line, fading in a moment after the launch screen hands over, its
/// dots ticking like an old progress readout.
class _Chatter extends StatefulWidget {
  const _Chatter({required this.line});

  final String line;

  @override
  State<_Chatter> createState() => _ChatterState();
}

class _ChatterState extends State<_Chatter> with TickerProviderStateMixin {
  late final _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  late final _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
  late final Timer _start;

  @override
  void initState() {
    super.initState();
    _start = Timer(const Duration(milliseconds: 200), _in.forward);
  }

  @override
  void dispose() {
    _start.cancel();
    _in.dispose();
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontFamily: 'W98',
      fontSize: 14,
      letterSpacing: 1,
      color: Color(0xB3F3E3C8),
      decoration: TextDecoration.none,
    );
    return AnimatedBuilder(
      animation: Listenable.merge([_a, _in]),
      builder: (context, _) {
        final appear = _in.value;
        final dots = (_a.value * 4).floor();
        return Opacity(
          opacity: appear,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 30),
              Text(widget.line, style: style, textScaler: TextScaler.noScaling),
              // Fixed width so the line doesn't shuffle as the dots tick.
              SizedBox(
                width: 30,
                child: Text(
                  '...'.substring(0, math.min(3, dots)),
                  style: style,
                  textScaler: TextScaler.noScaling,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
