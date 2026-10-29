import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/camera/application/camera_ui_state.dart' show PrefKeys;
import '../../features/settings/application/settings_controllers.dart';
import '../device/upright.dart';
import '../navigation.dart';
import '../providers.dart';
import '../theme/retro_theme.dart';

/// Keeps an eye out for a phone that can't keep up with Fancy graphics, and
/// offers once to turn it off, in case the user doesn't know the setting
/// exists and thinks the lag is just how the app is.
///
/// Cheap: the engine already reports each frame's timings in batches; this
/// adds them up and looks every 10 s. Only frames that were drawn count
/// (a still screen draws none, so it can't look slow). A 10 s window with
/// at least [_busy] frames whose average cost (the slower of build and
/// raster) is over 50 ms is slow (under 20 fps while things move); 3 slow
/// windows out of the last 6 ask. Not in the first 20 s (start-up and the
/// shaders warming), only with Fancy graphics on, only on the camera screen,
/// and never again once asked.
class LagWatch {
  LagWatch(this._ref);

  final WidgetRef _ref;
  Timer? _start, _tick;
  bool _listening = false;
  int _frames = 0, _cost = 0;
  final _recent = <bool>[];

  static const _busy = 30;
  static const _slowMs = 50;

  void start() {
    if (_asked) return;
    _start = Timer(const Duration(seconds: 20), () {
      SchedulerBinding.instance.addTimingsCallback(_timings);
      _listening = true;
      _tick = Timer.periodic(const Duration(seconds: 10), (_) => _look());
    });
  }

  void stop() {
    _start?.cancel();
    _tick?.cancel();
    if (_listening) SchedulerBinding.instance.removeTimingsCallback(_timings);
    _listening = false;
  }

  bool get _asked {
    try {
      return _ref.read(sharedPrefsProvider).getBool(PrefKeys.lagAsked) ?? false;
    } catch (_) {
      return true; // no prefs (tests): stay quiet
    }
  }

  void _timings(List<ui.FrameTiming> timings) {
    for (final t in timings) {
      _frames++;
      _cost += math.max(t.buildDuration.inMicroseconds, t.rasterDuration.inMicroseconds);
    }
  }

  void _look() {
    final frames = _frames, cost = _cost;
    _frames = 0;
    _cost = 0;
    if (!_ref.read(globalSettingsProvider).controls3d) {
      _recent.clear();
      return;
    }
    if (frames < _busy) return; // not much moving: nothing to judge
    _recent.add(cost / frames / 1000 > _slowMs);
    if (_recent.length > 6) _recent.removeAt(0);
    if (_recent.where((s) => s).length < 3) return;
    // Only over the camera itself (not mid-shot in another screen).
    final nav = appNavigatorKey.currentState;
    if (nav == null || nav.canPop()) return;
    stop();
    unawaited(_ask(nav.context));
  }

  Future<void> _ask(BuildContext context) async {
    try {
      await _ref.read(sharedPrefsProvider).setBool(PrefKeys.lagAsked, true);
    } catch (_) {}
    if (!context.mounted) return;
    if (await showLagSheet(context)) {
      await _ref.read(globalSettingsProvider.notifier).setControls3d(false);
    }
  }
}

/// "Things feeling slow?": true = switch Fancy graphics off.
Future<bool> showLagSheet(BuildContext context) async {
  final palette = RetroPalette.of(context);
  final yes = await showUprightSheet<bool>(
    context,
    backgroundColor: palette.body,
    builder: (_, {required landscape}) => Theme(data: palette.toTheme(), child: const LagSheet()),
  );
  return yes ?? false;
}

class LagSheet extends StatelessWidget {
  const LagSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final p = RetroPalette.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/artwork/rabbit_mark.png', height: 64, filterQuality: FilterQuality.medium),
            const SizedBox(height: 14),
            Text(
              'Things feeling slow?',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.text, fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              'Your phone seems to be working hard to draw the 3D cameras. Turning off Fancy graphics '
              'keeps every film, camera and photo exactly the same, just with flat-drawn cameras and '
              'fewer effects, so everything moves smoothly. You can turn it back on any time in Settings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textMuted, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: p.text,
                      side: BorderSide(color: p.textMuted),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Keep it fancy'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: p.accent,
                      foregroundColor: const Color(0xFF1A1714),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Smooth it out'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
