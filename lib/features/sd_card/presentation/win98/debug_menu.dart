import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/app_info.dart';
import '../../../../core/device/battery.dart';
import '../../../../core/diagnostics/crash_log.dart';
import '../../../../core/diagnostics/debug_flags.dart';
import '../../../../core/diagnostics/perf_recorder.dart';
import '../../../../core/providers.dart';
import '../../../camera/application/camera_session_controller.dart';
import '../../../camera/application/camera_ui_state.dart' show PrefKeys;
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

Future<void> _done(BuildContext context, String text) =>
    showWin98MessageBox(context, title: 'Debug', message: text);

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
Future<void> showDebugMenu(BuildContext context) => showWin98Window<void>(
  context,
  title: 'Debug',
  width: 320,
  icon: const PixelIconView(PixelIcon.computer),
  builder: (context) => const _DebugMenu(),
);

class _DebugMenu extends ConsumerStatefulWidget {
  const _DebugMenu();

  @override
  ConsumerState<_DebugMenu> createState() => _DebugMenuState();
}

class _DebugMenuState extends ConsumerState<_DebugMenu> {
  final _scroll = ScrollController();
  int _picked = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    await _tools[_picked].run(context, ref);
    if (mounted) setState(() {}); // switches show their new state
  }

  @override
  Widget build(BuildContext context) {
    final tool = _tools[_picked];
    final on = tool.on?.call(ref);
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
              height: 168,
              child: Win98Scrollbar(
                controller: _scroll,
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(2),
                  itemCount: _tools.length,
                  itemBuilder: (context, i) {
                    final t = _tools[i];
                    final picked = i == _picked;
                    final state = t.on?.call(ref);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _picked = i),
                      onDoubleTap: () {
                        setState(() => _picked = i);
                        unawaited(_run());
                      },
                      child: Container(
                        height: 26,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        color: picked ? W98.navy : null,
                        child: Row(
                          children: [
                            PixelIconView(t.icon),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                t.name,
                                style: W98.text.copyWith(color: picked ? W98.white : Colors.black),
                              ),
                            ),
                            if (state != null)
                              Text(
                                state ? 'On' : 'Off',
                                style: W98.text.copyWith(color: picked ? W98.white : W98.shadow),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Win98GroupBox(
            label: tool.name,
            child: SizedBox(height: 52, child: Text(tool.about, style: W98.text.copyWith(fontSize: 11))),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Win98Button(
                minWidth: 76,
                onPressed: () => unawaited(_run()),
                child: Text(on == null ? 'Run' : (on ? 'Turn Off' : 'Turn On')),
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
