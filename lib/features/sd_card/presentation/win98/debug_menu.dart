import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/app_info.dart';
import '../../../../core/device/battery.dart';
import '../../../../core/diagnostics/crash_log.dart';
import '../../../../core/diagnostics/debug_flags.dart';
import '../../../../core/diagnostics/develop_stats.dart';
import '../../../../core/diagnostics/perf_recorder.dart';
import '../../../../core/monetization/allowance.dart';
import '../../../../core/monetization/pro.dart';
import '../../../../core/processing/capture_processor.dart';
import '../../../../core/providers.dart';
import '../../../../core/skins/camera_skins.dart';
import '../../../../core/review/review_prompt.dart';
import '../../../camera/application/camera_session_controller.dart';
import '../../../camera/application/camera_ui_state.dart' show PrefKeys;
import '../../../cameras/domain/camera_spec.dart';
import '../../../settings/application/settings_controllers.dart';
import '../../../onboarding/onboarding_screen.dart';
import '../../application/sd_card_controller.dart';
import 'explorer_dialogs.dart';
import 'pixel_icons.dart';
import 'win98_widgets.dart';

/// One tool in the Debug window. [on] makes it a switch (shown On / Off).
class _Tool {
  const _Tool(this.icon, this.name, this.about, this.run, {this.on});

  final PixelIcon icon;
  final String name;
  final String about;
  final Future<void> Function(BuildContext context, WidgetRef ref) run;
  final bool Function(WidgetRef ref)? on;
}

final _tools = <_Tool>[
  _Tool(
    PixelIcon.rabbit,
    'Darkroom Pro',
    'On: unlimited film and battery, as if Pro was bought. Off: the free version with its daily roll '
        'and battery. Only changes this phone.',
    (_, ref) => ref.read(proProvider.notifier).set(!ref.read(proProvider)),
    on: (ref) => ref.watch(proProvider),
  ),
  _Tool(
    PixelIcon.camera,
    'Refill Film & Battery',
    "Gives the free version today's roll and a full battery again, as if it were tomorrow morning.",
    (context, ref) async {
      ref.read(allowanceProvider.notifier).refill();
      if (context.mounted) await _done(context, 'A fresh roll and a full battery are waiting.');
    },
  ),
  _Tool(
    PixelIcon.hourglass,
    'Darkroom Development',
    'On: film takes ${CameraSpec.defaultDevelopTime.inMinutes} minutes to develop (instant prints under a minute). '
        'Off: film develops instantly, and anything in the darkroom is finished now.',
    (_, ref) =>
        ref.read(globalSettingsProvider.notifier).setDarkroomEnabled(!ref.read(globalSettingsProvider).darkroomEnabled),
    on: (ref) => ref.watch(globalSettingsProvider).darkroomEnabled,
  ),
  _Tool(
    PixelIcon.hourglass,
    'Performance Recorder',
    'Times every frame while on, labelled with what was happening (panel slides, swaps, menus...). '
        'Turn it on, use the app normally, then open Performance Report.',
    (_, _) async => PerfRecorder.recording ? PerfRecorder.stop() : PerfRecorder.start(),
    on: (_) => PerfRecorder.recording,
  ),
  _Tool(
    PixelIcon.views,
    'Performance Report',
    'Slow frames per activity, and whether the app (UI) or the graphics chip (GPU) was the hold-up. '
        'Copy it and send it to Claude.',
    (context, _) => _perfReport(context),
  ),
  _Tool(
    PixelIcon.hourglass,
    'Development Stats',
    'How long film shots take to process on this phone, and how many missed their darkroom timer. '
        'All time, or since you last reset. Plus the cores at work right now.',
    (context, _) => showWin98Window<void>(
      context,
      title: 'Development Stats',
      width: 320,
      icon: const PixelIconView(PixelIcon.hourglass),
      builder: (context) => const _DevelopStatsView(),
    ),
  ),
  _Tool(
    PixelIcon.camera,
    'Camera Log',
    'Recent camera session events: opens, closes, errors. Screenshot it when the viewfinder misbehaves.',
    (context, _) => showCameraLog(context),
  ),
  _Tool(
    PixelIcon.error,
    'Crash Reports',
    'Crashes kept on this phone, newest first. Copy them into a message.',
    (context, _) => showCrashReports(context),
  ),
  _Tool(
    PixelIcon.rabbit,
    'Welcome Tour',
    'Plays the first-run tour now, exactly as a new user sees it.',
    (context, _) => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (context) => OnboardingScreen(onDone: () => Navigator.of(context).pop()))),
  ),
  _Tool(
    PixelIcon.question,
    'Tour On Next Start',
    'Forgets that the tour was seen, so it opens the next time the app starts from scratch.',
    (context, ref) async {
      await ref.read(sharedPrefsProvider).remove(PrefKeys.onboarded);
      if (context.mounted) await _done(context, 'The tour will show on the next start.');
    },
  ),
  _Tool(
    PixelIcon.hourglass,
    'Develop Everything Now',
    'Every print and reel still in the darkroom is finished at once.',
    (context, ref) async {
      await ref.read(darkroomEngineProvider).developEverythingNow();
      if (context.mounted) await _done(context, 'The darkroom is empty. Everything is on the corkboard.');
    },
  ),
  _Tool(
    PixelIcon.views,
    'Frame Timing Graphs',
    "Flutter's performance overlay: frame times for the UI and the GPU. Spikes over the line are dropped frames.",
    (_, ref) async => ref.read(perfOverlayProvider.notifier).toggle(),
    on: (ref) => ref.watch(perfOverlayProvider),
  ),
  _Tool(
    PixelIcon.hourglass,
    'Slow Motion',
    'Every animation runs 5x slower: swaps, slide-ins, the shutter. Good for checking how they move.',
    (_, _) async => timeDilation = timeDilation == 1 ? 5 : 1,
    on: (_) => timeDilation != 1,
  ),
  _Tool(
    PixelIcon.rabbit,
    'Rating Prompt',
    'Asks the store to show its rating prompt now (normally once, after the 5th launch and the 10th '
        'developed print). Google only shows it to installs from Play; Apple never shows it in TestFlight.',
    (_, _) => ReviewPrompt.show(),
  ),
  _Tool(PixelIcon.camera, 'Unlock All Skins', 'Every camera skin owned (or none again, game progress kept).', (
    _,
    ref,
  ) async {
    final n = ref.read(unlockedSkinsProvider.notifier);
    ref.read(unlockedSkinsProvider).isEmpty ? await n.unlockAll() : await n.lockAll();
  }, on: (ref) => ref.watch(unlockedSkinsProvider).isNotEmpty),
  _Tool(
    PixelIcon.computer,
    'System Info',
    'Version, phone, screen, camera stream, battery and what is stored.',
    (context, ref) => _systemInfo(context, ref),
  ),
  _Tool(PixelIcon.warning, 'Test Crash', 'Throws a harmless error, to check that Crash Reports catches it.', (
    context,
    _,
  ) async {
    scheduleMicrotask(() => throw StateError('Test crash from the Debug window'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (context.mounted) await _done(context, 'Thrown. It should be at the top of Crash Reports.');
  }),
];

Future<void> _perfReport(BuildContext context) => showWin98Window<void>(
  context,
  title: 'Performance Report - Notepad',
  width: 340,
  icon: const PixelIconView(PixelIcon.info),
  builder: (context) => StatefulBuilder(
    builder: (context, setState) {
      final text = PerfRecorder.report();
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: Win98Bevel(
                style: BevelStyle.sunken,
                color: W98.white,
                padding: const EdgeInsets.all(6),
                child: SingleChildScrollView(child: Text(text, style: W98.text.copyWith(fontSize: 10))),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Win98Button(
                  minWidth: 64,
                  onPressed: () {
                    PerfRecorder.clear();
                    setState(() {});
                  },
                  child: const Text('Clear'),
                ),
                const SizedBox(width: 6),
                Win98Button(
                  minWidth: 64,
                  onPressed: () => unawaited(Clipboard.setData(ClipboardData(text: text))),
                  child: const Text('Copy'),
                ),
                const SizedBox(width: 6),
                Win98Button(minWidth: 64, onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
              ],
            ),
          ],
        ),
      );
    },
  ),
);

class _DevelopStatsView extends ConsumerStatefulWidget {
  const _DevelopStatsView();

  @override
  ConsumerState<_DevelopStatsView> createState() => _DevelopStatsViewState();
}

class _DevelopStatsViewState extends ConsumerState<_DevelopStatsView> {
  int _tab = 0;
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    // The queue lines are live.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  static String _secs(int ms) => '${(ms / 1000).toStringAsFixed(1)} s';

  String _text(DevelopTally t) {
    final p = ref.read(captureProcessorProvider);
    final n = t.shots, ok = n - t.late;
    String pct(int v) => n == 0 ? '-' : '${(100 * v / n).toStringAsFixed(0)}%';
    final d = t.since;
    return [
      if (_tab == 1) 'Since ${d.day}/${d.month} ${d.hour}:${d.minute.toString().padLeft(2, '0')}',
      'Film shots developed: $n',
      'On time: $ok (${pct(ok)})',
      'Missed the timer: ${t.late} (${pct(t.late)})',
      if (t.late > 0) 'Average delay when late: ${_secs(t.lateMs ~/ t.late)}',
      'Average processing: ${n == 0 ? '-' : _secs(t.workMs ~/ n)}',
      'Average shot to print: ${n == 0 ? '-' : _secs(t.totalMs ~/ n)}',
      'Longest queue: ${t.maxQueue} waiting',
      '',
      'Cores: ${Platform.numberOfProcessors}, developing on up to ${CaptureProcessor.maxWorkers}',
      'Now: ${p.busy} developing, ${p.waiting} waiting',
      if (t.shots >= DevelopStats.minShots && t.lateShare > DevelopStats.warnShare)
        'Over ${(DevelopStats.warnShare * 100).round()}% late: this phone is the bottleneck.',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.read(developStatsProvider);
    final text = _text(_tab == 0 ? stats.allTime : stats.recent);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Win98TabStrip(
            tabs: const [Win98Tab('All Time'), Win98Tab('Since Reset')],
            selected: _tab,
            onSelect: (i) => setState(() => _tab = i),
          ),
          Win98Bevel(
            style: BevelStyle.window,
            padding: const EdgeInsets.all(8),
            child: Text(text, style: W98.text.copyWith(fontSize: 10)),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_tab == 1) ...[
                Win98Button(
                  minWidth: 64,
                  onPressed: () async {
                    await stats.clearRecent();
                    if (mounted) setState(() {});
                  },
                  child: const Text('Reset'),
                ),
                const SizedBox(width: 6),
              ],
              Win98Button(
                minWidth: 64,
                onPressed: () => unawaited(Clipboard.setData(ClipboardData(text: text))),
                child: const Text('Copy'),
              ),
              const SizedBox(width: 6),
              Win98Button(minWidth: 64, onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _done(BuildContext context, String text) => showWin98MessageBox(context, title: 'Debug', message: text);

Future<void> _systemInfo(BuildContext context, WidgetRef ref) async {
  final battery = await Battery.level();
  if (!context.mounted) return;
  final media = MediaQuery.of(context);
  final view = View.of(context);
  final preview = ref.read(cameraSessionProvider).controller?.value.previewSize;
  final prints = ref.read(filmItemsProvider).value?.length;
  final text = [
    '${AppInfo.name} ${AppInfo.version}',
    '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    'Screen: ${view.physicalSize.width.round()} x ${view.physicalSize.height.round()} px, '
        '${media.devicePixelRatio.toStringAsFixed(2)}x',
    'Camera stream: ${preview == null ? 'closed' : '${preview.width.round()} x ${preview.height.round()}'}',
    'Battery: ${battery == null ? 'unknown' : '$battery%'}',
    'Prints and reels: ${prints ?? '?'}',
    'SD card files: ${ref.read(sdCardFilesProvider).length}',
    'Crash reports: ${CrashLog.reports.length}',
  ].join('\n');
  await showWin98MessageBox(context, title: 'System Info', message: text);
}

/// Help > Debug: a scrolling list of developer tools (room for more), the
/// picked one's description, and Run. Double-tap a tool to run it.
/// The Debug password comes from the build (CI secret `DEBUG_PASSWORD`),
/// never from the source, and only as a salted hash (`--dart-define
/// DEBUG_KEY`), so the app itself doesn't hold it. Without one the window
/// stays shut. Asked for once per app run.
class DebugGate {
  const DebugGate._();

  static String key = const String.fromEnvironment('DEBUG_KEY');
  static bool unlocked = false;

  static String hashOf(String password) => sha256.convert(utf8.encode('darkroom-debug:$password')).toString();

  static bool accepts(String typed) => key.isNotEmpty && hashOf(typed.trim()) == key.toLowerCase();
}

Future<void> showDebugMenu(BuildContext context) async {
  if (!DebugGate.unlocked) {
    final typed = await _askPassword(context);
    if (typed == null || !context.mounted) return;
    if (!DebugGate.accepts(typed)) {
      await showWin98MessageBox(context, title: 'Debug', message: 'Incorrect password.', icon: Win98MessageIcon.error);
      return;
    }
    DebugGate.unlocked = true;
  }
  if (!context.mounted) return;
  await showWin98Window<void>(
    context,
    title: 'Debug',
    width: 320,
    icon: const PixelIconView(PixelIcon.computer),
    builder: (context) => const _DebugMenu(),
  );
}

Future<String?> _askPassword(BuildContext context) {
  final ctrl = TextEditingController();
  return showWin98Window<String>(
    context,
    title: 'Enter Password',
    width: 300,
    icon: const PixelIconView(PixelIcon.computer),
    builder: (context) => Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Type the password for the Debug tools.'),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('Password:  '),
              Expanded(
                child: Win98Bevel(
                  style: BevelStyle.sunken,
                  color: W98.window,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: TextField(
                    controller: ctrl,
                    autofocus: true,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: W98.text,
                    cursorColor: W98.windowInk,
                    decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                    onSubmitted: (v) => Navigator.of(context).pop(v),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Win98Button(minWidth: 76, onPressed: () => Navigator.of(context).pop(ctrl.text), child: const Text('OK')),
              const SizedBox(width: 6),
              Win98Button(minWidth: 76, onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ],
          ),
        ],
      ),
    ),
  );
}

class _DebugMenu extends ConsumerStatefulWidget {
  const _DebugMenu();

  @override
  ConsumerState<_DebugMenu> createState() => _DebugMenuState();
}

/// The Debug window's folders, in order, and the tools in each (by name).
/// A tool left out lands in Other.
const _groups = <(String, List<String>)>[
  ('Darkroom', ['Darkroom Development', 'Develop Everything Now', 'Development Stats']),
  ('Pro & Film', ['Darkroom Pro', 'Refill Film & Battery']),
  ('Performance', ['Performance Recorder', 'Performance Report', 'Frame Timing Graphs', 'Slow Motion']),
  ('Cosmetics', ['Unlock All Skins']),
  ('Diagnostics', ['Camera Log', 'Crash Reports', 'System Info', 'Test Crash']),
  ('First Run & Store', ['Welcome Tour', 'Tour On Next Start', 'Rating Prompt']),
];

/// Folder name -> indexes into [_tools].
final Map<String, List<int>> _folders = () {
  final out = <String, List<int>>{};
  final placed = <int>{};
  for (final (name, tools) in _groups) {
    final ids = [
      for (final t in tools)
        if (_tools.indexWhere((x) => x.name == t) case final i when i >= 0) i,
    ];
    out[name] = ids;
    placed.addAll(ids);
  }
  final rest = [
    for (var i = 0; i < _tools.length; i++)
      if (!placed.contains(i)) i,
  ];
  if (rest.isNotEmpty) out['Other'] = rest;
  return out;
}();

class _DebugMenuState extends ConsumerState<_DebugMenu> {
  final _scroll = ScrollController();

  /// The picked tool (index into [_tools]), or a folder ([_folder]).
  int? _picked;
  String? _folder;
  final _open = <String>{};

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final i = _picked;
    if (i == null) return;
    await _tools[i].run(context, ref);
    if (mounted) setState(() {}); // switches show their new state
  }

  void _toggle(String folder) => setState(() {
    _folder = folder;
    _picked = null;
    if (!_open.remove(folder)) _open.add(folder);
  });

  Widget _row({
    required bool picked,
    required double indent,
    required List<Widget> children,
    VoidCallback? onTap,
    VoidCallback? onDoubleTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: SizedBox(
        height: 26,
        child: Row(
          children: [
            SizedBox(width: indent),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                color: picked ? W98.navy : null,
                child: Row(children: children),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final picked = _picked;
    final tool = picked == null ? null : _tools[picked];
    final on = tool?.on?.call(ref);
    final rows = <Widget>[];
    for (final MapEntry(key: name, value: ids) in _folders.entries) {
      final open = _open.contains(name);
      final sel = _folder == name && picked == null;
      rows.add(
        _row(
          picked: sel,
          indent: 0,
          onTap: () => _toggle(name),
          children: [
            _PlusBox(open: open),
            const SizedBox(width: 4),
            PixelIconView(open ? PixelIcon.folderOpen : PixelIcon.folder),
            const SizedBox(width: 6),
            Expanded(
              child: Text(name, style: W98.text.copyWith(color: sel ? W98.selectInk : W98.windowInk)),
            ),
          ],
        ),
      );
      if (!open) continue;
      for (final i in ids) {
        final t = _tools[i];
        final sel = i == picked;
        final state = t.on?.call(ref);
        rows.add(
          _row(
            picked: sel,
            indent: 24,
            onTap: () => setState(() {
              _picked = i;
              _folder = name;
            }),
            onDoubleTap: () {
              setState(() => _picked = i);
              unawaited(_run());
            },
            children: [
              PixelIconView(t.icon),
              const SizedBox(width: 6),
              Expanded(
                child: Text(t.name, style: W98.text.copyWith(color: sel ? W98.selectInk : W98.windowInk)),
              ),
              if (state != null)
                Text(state ? 'On' : 'Off', style: W98.text.copyWith(color: sel ? W98.white : W98.shadow)),
            ],
          ),
        );
      }
    }
    final folderTools = _folder == null ? const <int>[] : _folders[_folder]!;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Tools:'),
          const SizedBox(height: 4),
          Win98Bevel(
            style: BevelStyle.sunken,
            color: W98.white,
            child: SizedBox(
              height: 220,
              child: Win98Scrollbar(
                controller: _scroll,
                child: ListView(controller: _scroll, padding: const EdgeInsets.all(2), children: rows),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Win98GroupBox(
            label: tool?.name ?? _folder ?? 'Debug',
            child: SizedBox(
              height: 52,
              child: Text(
                tool?.about ??
                    (_folder == null
                        ? 'Open a folder to see its tools.'
                        : [for (final i in folderTools) _tools[i].name].join(', ')),
                style: W98.text.copyWith(fontSize: 11),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Win98Button(
                minWidth: 76,
                onPressed: tool == null ? (_folder == null ? null : () => _toggle(_folder!)) : () => unawaited(_run()),
                child: Text(
                  tool == null
                      ? (_folder != null && _open.contains(_folder) ? 'Collapse' : 'Expand')
                      : on == null
                      ? 'Run'
                      : (on ? 'Turn Off' : 'Turn On'),
                ),
              ),
              const SizedBox(width: 6),
              Win98Button(minWidth: 76, onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
            ],
          ),
        ],
      ),
    );
  }
}

/// The tree's [+] / [-] box.
class _PlusBox extends StatelessWidget {
  const _PlusBox({required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(9, 9), painter: _PlusPainter(open, W98.shadow, W98.windowInk));
}

class _PlusPainter extends CustomPainter {
  _PlusPainter(this.open, this.frame, this.ink);

  final bool open;
  final Color frame, ink;

  @override
  void paint(Canvas canvas, Size size) {
    final f = Paint()
      ..color = frame
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(const Rect.fromLTWH(0.5, 0.5, 8, 8), f);
    final p = Paint()..color = ink;
    canvas.drawRect(const Rect.fromLTWH(2, 4, 5, 1), p);
    if (!open) canvas.drawRect(const Rect.fromLTWH(4, 2, 1, 5), p);
  }

  @override
  bool shouldRepaint(_PlusPainter old) => old.open != open || old.frame != frame || old.ink != ink;
}
