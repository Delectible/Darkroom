import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_scene/scene.dart' as fs show takeMemoryReport;

import '../../../../core/app_info.dart';
import '../../../../core/device/battery.dart';
import '../../../../core/device/device_memory.dart';
import '../../../../core/diagnostics/crash_log.dart';
import '../../../../core/diagnostics/develop_stats.dart';
import '../../../../core/diagnostics/fps_meter.dart';
import '../../../../core/diagnostics/lag_watch.dart';
import '../../../../core/diagnostics/launch_timer.dart';
import '../../../../core/diagnostics/perf_recorder.dart';
import '../../../../core/diagnostics/speed_test_run.dart';
import '../../../../core/diagnostics/speed_tests.dart';
import '../../../../core/monetization/allowance.dart';
import '../../../../core/monetization/pro.dart';
import '../../../../core/processing/capture_processor.dart';
import '../../../../core/providers.dart';
import '../../../../core/skins/camera_skins.dart';
import '../../../../core/review/review_prompt.dart';
import '../../../camera/application/camera_session_controller.dart';
import '../../../camera/application/camera_ui_state.dart' show PrefKeys;
import '../../../cameras/domain/camera_spec.dart';
import '../../../camera/presentation/body_quality.dart';
import '../../../camera/presentation/whole_body.dart';
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

/// Reads a provider (a widget's ref, or the app's container once the Debug
/// window has closed).
typedef _Read = T Function<T>(ProviderListenable<T> provider);

/// Debug > Speed Tests: (name, switch, what it does).
final _speedTests = <(String, ValueNotifier<bool>, String)>[
  (
    'No Viewfinder Look',
    SpeedTests.noLook,
    'The viewfinder shows the plain camera feed, without the film or digital look.',
  ),
  ('Grain at 12 fps', SpeedTests.slowGrain, 'Film grain moves 12 times a second instead of 24.'),
  (
    'Still Viewfinder in Swipes',
    SpeedTests.stillSwipe,
    'While you swipe, the viewfinder is one still picture instead of being retaken every frame.',
  ),
  (
    'No Strap in Swipes',
    SpeedTests.noStrap,
    'No hanging strap while you swipe (its rope is worked out every frame).',
  ),
  (
    'Cheaper 3D Edges',
    SpeedTests.cheapEdges,
    "The 3D camera's edges smoothed by a cheap filter (FXAA) instead of multisampling.",
  ),
  ('3D at 70%', SpeedTests.small3d, 'The 3D camera drawn at 70% of its size and scaled up.'),
];

final _tools = <_Tool>[
  _Tool(
    PixelIcon.views,
    'Run Speed Test',
    'The one to send: about ${SpeedTestRun.minutes} minutes, hands off. The app swipes between the cameras '
        'and through the corkboard and Darkroom 98 by itself, trying each speed setting in turn, with live '
        'numbers on top. At the end it shows a short result to copy and send. Run it again for '
        'the last result.',
    (context, ref) async {
      final last = SpeedTestRun.lastResults;
      final go = await showWin98MessageBox(
        context,
        title: 'Speed Test',
        message:
            'Takes about ${SpeedTestRun.minutes} minutes. Put the phone down and don\'t touch it: '
            'the app swipes and switches screens by itself. The panel at the top shows how long is left '
            '(tap it to stop).',
        icon: Win98MessageIcon.question,
        buttons: ['Start', if (last != null) 'Last Result', 'Cancel'],
      );
      if (!context.mounted) return;
      if (go == 1 && last != null) return _showResults(context, last);
      if (go != 0) return;
      final container = ProviderScope.containerOf(context, listen: false);
      SpeedTestRun.header = () => _testHeader(container.read);
      final navigator = Navigator.of(context);
      unawaited(
        SpeedTestRun.run(
          navigator,
          done: (text) {
            final c = navigator.context;
            if (c.mounted) unawaited(_showResults(c, text));
          },
        ),
      );
    },
  ),
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
    (_, ref) => ref
        .read(globalSettingsProvider.notifier)
        .setDarkroomEnabled(!ref.read(globalSettingsProvider).darkroomEnabled),
    on: (ref) => ref.watch(globalSettingsProvider).darkroomEnabled,
  ),
  _Tool(
    PixelIcon.views,
    'Performance Report',
    'Everything in one report to copy and send: this phone and its settings, the last launches step by '
        'step, every frame since the app started (by activity, with any Speed Tests on), the 3D camera\'s '
        'quality and memory. Clear starts a fresh recording.',
    (context, ref) => _perfReport(context, ref.read),
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
    (context, _) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => OnboardingScreen(onDone: () => Navigator.of(context).pop()),
      ),
    ),
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
    'FPS Counter',
    'Frames drawn per second, live, with the last 15 seconds as a chart and the slowest recent frame. '
        'Flutter only draws when something changes; the counter itself redraws 4 times a second, so a '
        'still screen reads about 4.',
    (_, ref) async => ref.read(fpsMeterProvider.notifier).toggle(),
    on: (ref) => ref.watch(fpsMeterProvider),
  ),
  _Tool(
    PixelIcon.views,
    'Lag Prompt',
    'Shows the "Things feeling slow?" sheet now (normally once, only if the 3D cameras keep the screen under '
        '20 fps for a while); Smooth it out turns Fancy graphics off.',
    (context, ref) async {
      if (await showLagSheet(context)) await ref.read(globalSettingsProvider.notifier).setControls3d(false);
    },
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
    'Shows the "Give us a shoutout!" sheet now (normally once, after the 5th launch and the 10th developed '
        "print); Yea! asks the store for its prompt. Google only shows that to installs from Play; Apple never "
        'shows it in TestFlight.',
    (context, _) => ReviewPrompt.ask(context),
  ),
  _Tool(
    PixelIcon.camera,
    'Unlock All Skins',
    'Every camera skin owned (or none again, game progress kept).',
    (_, ref) async {
      final n = ref.read(unlockedSkinsProvider.notifier);
      ref.read(unlockedSkinsProvider).isEmpty ? await n.unlockAll() : await n.lockAll();
    },
    on: (ref) => ref.watch(unlockedSkinsProvider).isNotEmpty,
  ),
  _Tool(PixelIcon.warning, 'Test Crash', 'Throws a harmless error, to check that Crash Reports catches it.', (
    context,
    _,
  ) async {
    scheduleMicrotask(() => throw StateError('Test crash from the Debug window'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (context.mounted) await _done(context, 'Thrown. It should be at the top of Crash Reports.');
  }),
  for (final (name, flag, about) in _speedTests)
    _Tool(
      PixelIcon.views,
      name,
      '$about Frames are labelled [${SpeedTests.nameOf(flag)}] in the Performance Report. Resets when the app restarts.',
      (_, _) async => flag.value = !flag.value,
      on: (_) => flag.value,
    ),
];

/// Debug > Performance Report: the phone, the launches, the frames, the 3D
/// camera and memory, in one text to copy.
Future<void> _perfReport(BuildContext context, _Read read) async {
  final battery = await Battery.level();
  if (!context.mounted) return;
  String all() => [
    _phoneReport(read, battery),
    PerfRecorder.report(),
    LaunchTimer.report(),
    '3D QUALITY\n${BodyQuality.report()}',
    'MEMORY\n${_memoryReport(read)}',
  ].join('\n\n');
  await showWin98Window<void>(
    context,
    title: 'Performance Report - Notepad',
    width: 340,
    icon: const PixelIconView(PixelIcon.info),
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final text = all();
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
                  Win98Button(
                    minWidth: 64,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}

String _phoneReport(_Read read, int? battery) {
  final settings = read(globalSettingsProvider);
  final preview = read(cameraSessionProvider).controller?.value.previewSize;
  return [
    'PHONE',
    '${AppInfo.name} ${AppInfo.version}, ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    'RAM ${DeviceMemory.gb?.toStringAsFixed(1) ?? '?'} GB${DeviceMemory.low ? ' (low: lighter settings)' : ''}, '
        '${Platform.numberOfProcessors} cores, battery ${battery == null ? '?' : '$battery%'}',
    'Fancy graphics: ${settings.controls3d ? 'on' : 'off'}',
    'Camera stream: ${preview == null ? 'closed' : '${preview.width.round()} x ${preview.height.round()}'}',
    'Prints and reels: ${read(filmItemsProvider).value?.length ?? '?'}, '
        'SD card files: ${read(sdCardFilesProvider).length}, crash reports: ${CrashLog.reports.length}',
  ].join('\n');
}

String _memoryReport(_Read read) {
  final cache = PaintingBinding.instance.imageCache;
  String mb(int b) => (b / (1 << 20)).toStringAsFixed(1);
  final b = StringBuffer()
    ..writeln('Prints developing at once: up to ${CaptureProcessor.maxWorkers}')
    ..writeln(
      'Picture cache: ${cache.currentSize} pictures, ${mb(cache.currentSizeBytes)} of '
      '${mb(cache.maximumSizeBytes)} MB',
    )
    ..writeln()
    ..writeln('3D cameras:');
  final art = read(wholeArtProvider).value;
  for (final MapEntry(key: mode, value: body) in (art?.bodies ?? const <AppMode, WholeBody>{}).entries) {
    final live = body.live;
    b.writeln(
      live == null
          ? '  ${mode.name}: not loaded'
          : '  ${mode.name}: ${mb(live.textureBytes())} MB of textures (skin ${live.finish}; '
                '${live.textureFormats()})',
    );
  }
  b.writeln(_compressionSupport());
  b.writeln('Engine caches:');
  try {
    b.writeln(fs.takeMemoryReport());
  } catch (e) {
    b.writeln('  not loaded ($e)');
  }
  return b.toString();
}

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
      'Cores: ${Platform.numberOfProcessors}, RAM: ${DeviceMemory.gb?.toStringAsFixed(1) ?? '?'} GB, '
          'developing on up to ${CaptureProcessor.maxWorkers}',
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
              Win98Button(
                minWidth: 64,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _done(BuildContext context, String text) =>
    showWin98MessageBox(context, title: 'Debug', message: text);

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
      await showWin98MessageBox(
        context,
        title: 'Debug',
        message: 'Incorrect password.',
        icon: Win98MessageIcon.error,
      );
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
              Win98Button(
                minWidth: 76,
                onPressed: () => Navigator.of(context).pop(ctrl.text),
                child: const Text('OK'),
              ),
              const SizedBox(width: 6),
              Win98Button(
                minWidth: 76,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
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
final _groups = <(String, List<String>)>[
  ('Performance', ['Run Speed Test', 'Performance Report', 'FPS Counter', 'Slow Motion']),
  ('Darkroom', ['Darkroom Development', 'Develop Everything Now', 'Development Stats']),
  ('Pro & Unlocks', ['Darkroom Pro', 'Refill Film & Battery', 'Unlock All Skins']),
  ('Speed Test Switches', [for (final (name, _, _) in _speedTests) name]),
  ('Diagnostics', ['Camera Log', 'Crash Reports', 'Test Crash']),
  ('First Run & Prompts', ['Welcome Tour', 'Tour On Next Start', 'Rating Prompt', 'Lag Prompt']),
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
  final _aboutScroll = ScrollController();
  (int?, String?) _shown = (null, null);

  /// The picked tool (index into [_tools]), or a folder ([_folder]).
  int? _picked;
  String? _folder;

  /// (Performance open from the start: the speed test is the first thing there)
  final _open = <String>{'Performance'};

  @override
  void dispose() {
    _scroll.dispose();
    _aboutScroll.dispose();
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
    if ((_picked, _folder) != _shown) {
      _shown = (_picked, _folder);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_aboutScroll.hasClients) _aboutScroll.jumpTo(0);
      });
    }
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
            // Long descriptions scroll (back to the top for each pick).
            child: SizedBox(
              height: 60,
              child: Win98Scrollbar(
                controller: _aboutScroll,
                child: SingleChildScrollView(
                  controller: _aboutScroll,
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    tool?.about ??
                        (_folder == null
                            ? 'Open a folder to see its tools.'
                            : [for (final i in folderTools) _tools[i].name].join(', ')),
                    style: W98.text.copyWith(fontSize: 11),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Win98Button(
                minWidth: 76,
                onPressed: tool == null
                    ? (_folder == null ? null : () => _toggle(_folder!))
                    : () => unawaited(_run()),
                child: Text(
                  tool == null
                      ? (_folder != null && _open.contains(_folder) ? 'Collapse' : 'Expand')
                      : on == null
                      ? 'Run'
                      : (on ? 'Turn Off' : 'Turn On'),
                ),
              ),
              const SizedBox(width: 6),
              Win98Button(
                minWidth: 76,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
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

/// Which block-compressed texture families this phone's GPU reports (the 3D
/// textures load as the first of ASTC / BC / ETC2 it has, else rgba8).
String _compressionSupport() {
  try {
    final c = gpu.gpuContext;
    String yes(bool v) => v ? 'yes' : 'no';
    return 'GPU texture compression: '
        'ASTC ${yes(c.supportsTextureCompression(gpu.TextureCompressionFamily.astc))} '
        '(format ${yes(c.supportsTextureFormat(gpu.PixelFormat.astc4x4LDR))}), '
        'BC ${yes(c.supportsTextureCompression(gpu.TextureCompressionFamily.bc))}, '
        'ETC2 ${yes(c.supportsTextureCompression(gpu.TextureCompressionFamily.etc2))}';
  } catch (e) {
    return 'GPU texture compression: unknown ($e)';
  }
}

/// The speed test's own header lines: the app, Fancy graphics, the 3D
/// textures (format and size) and what compression the GPU offers.
String _testHeader(_Read read) {
  final art = read(wholeArtProvider).value;
  final tex = [
    for (final MapEntry(key: mode, value: body) in (art?.bodies ?? const <AppMode, WholeBody>{}).entries)
      if (body.live case final live?)
        '${mode.name} ${(live.textureBytes() / (1 << 20)).round()} MB (${live.textureFormats()})',
  ];
  return [
    '${AppInfo.name} ${AppInfo.version}, RAM ${DeviceMemory.gb?.toStringAsFixed(1) ?? '?'} GB'
        '${DeviceMemory.low ? ' (low)' : ''}, fancy graphics ${read(globalSettingsProvider).controls3d ? 'on' : 'off'}',
    '3D textures: ${tex.isEmpty ? 'not loaded' : tex.join('; ')}',
    _compressionSupport().replaceFirst('GPU texture compression: ', 'GPU compression: '),
  ].join('\n');
}

/// The speed test's result, with a big Copy button.
Future<void> _showResults(BuildContext context, String text) => showWin98Window<void>(
  context,
  title: 'Speed Test Result',
  width: 360,
  icon: const PixelIconView(PixelIcon.info),
  builder: (context) => StatefulBuilder(
    builder: (context, setState) {
      var copied = false;
      return StatefulBuilder(
        builder: (context, setInner) => Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                copied
                    ? 'Copied. Paste it into a message to whoever asked for it.'
                    : 'Done. Copy this and send it (it fits in one message).',
                style: W98.text.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: Win98Bevel(
                  style: BevelStyle.sunken,
                  color: W98.white,
                  padding: const EdgeInsets.all(6),
                  child: SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text(text, style: W98.text.copyWith(fontSize: 9, fontFamily: 'monospace')),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Win98Button(
                      onPressed: () {
                        unawaited(Clipboard.setData(ClipboardData(text: text)));
                        setInner(() => copied = true);
                      },
                      child: Text(copied ? 'Copied!' : 'Copy to Clipboard'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Win98Button(
                    minWidth: 64,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  ),
);
