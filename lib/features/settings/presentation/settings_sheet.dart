import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_info.dart';
import '../../../core/audio/sfx.dart';
import '../../../core/device/camera_control.dart';
import '../../../core/device/device_memory.dart';
import '../../../core/device/haptics.dart';
import '../../../core/device/upright.dart';
import '../../../core/monetization/allowance.dart';
import '../../../core/monetization/pro.dart';
import '../../../core/processing/film/film_profile.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/support/support.dart';
import '../../../core/theme/note_box.dart';
import '../../camera/application/camera_ui_state.dart';
import '../../cameras/domain/camera_catalog.dart';
import '../../cameras/domain/camera_spec.dart';
import '../../help/how_it_works_screen.dart';
import '../../monetization/pro_sheet.dart';
import '../../skins/presentation/camera_shop_screen.dart';
import '../application/settings_controllers.dart';

/// Settings, dressed as the camera in hand would have them: film, the
/// owner's manual from the box (printed paper, numbered sections, boxes to
/// tick); digital, the camera's own menu screen (dot-matrix tabs and rows).
/// The same settings either way.
Future<void> showSettingsSheet(BuildContext context) {
  final film = ProviderScope.containerOf(context).read(appModeProvider) == AppMode.film;
  return showUprightSheet<void>(
    context,
    backgroundColor: film ? _Manual.paper : _Menu.body,
    builder: (_, {required landscape}) => film ? _Manual(landscape: landscape) : _Menu(landscape: landscape),
  );
}

/// Portrait: a draggable sheet; held sideways: a fixed panel.
Widget _sheet({
  required bool landscape,
  required Widget Function(ScrollController? scroll) child,
  double initial = 0.78,
}) {
  if (landscape) {
    return LayoutBuilder(
      builder: (context, box) => SizedBox(height: box.maxHeight * 0.92, child: child(null)),
    );
  }
  return DraggableScrollableSheet(
    expand: false,
    initialChildSize: initial,
    maxChildSize: 0.92,
    builder: (context, scroll) => child(scroll),
  );
}

/// The camera whose own settings are shown: the one in hand to begin with,
/// stepped through the others with the arrows.
mixin _CameraPick<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  String? _picked;

  CameraSpec pickedSpec(AppMode mode) {
    final all = CameraCatalog.forMode(mode);
    final id = _picked ?? ref.read(activeSpecProvider).id;
    return all.firstWhere((s) => s.id == id, orElse: () => all.first);
  }

  void stepCamera(AppMode mode, int by) {
    final all = CameraCatalog.forMode(mode);
    final i = all.indexWhere((s) => s.id == pickedSpec(mode).id);
    unawaited(Haptics.selectionClick());
    setState(() => _picked = all[(i + by) % all.length].id);
  }
}

Future<void> _feedback(BuildContext context) async {
  if (!await Support.sendFeedback() && context.mounted) {
    Notes.show('No mail app found. The address (${Support.email}) is copied.');
  }
}

Future<void> _notifications(BuildContext context, WidgetRef ref, bool v) async {
  final ok = await ref.read(globalSettingsProvider.notifier).setNotificationsEnabled(v);
  if (!ok && context.mounted) Notes.show('Notifications are blocked in system settings.');
}

String _grainName(GrainStrength g) => switch (g) {
  GrainStrength.weak => 'Weak',
  GrainStrength.normal => 'Normal',
  GrainStrength.strong => 'Strong',
};

String _stampName(TimestampStyle s) => switch (s) {
  TimestampStyle.ledDate => 'Date stamp in the corner',
  TimestampStyle.phone => 'Date and time in the corner',
  TimestampStyle.camcorderOsd => 'Tape readout (clock, REC, battery)',
  TimestampStyle.none => '',
};

// ===========================================================================
// Film: the owner's manual
// ===========================================================================

class _Manual extends ConsumerStatefulWidget {
  const _Manual({required this.landscape});

  final bool landscape;

  static const paper = Color(0xFFEEE8DC);
  static const ink = Color(0xFF1E1B17);
  static const faint = Color(0xFF5E564B);
  static const rule = Color(0xFF9C9283);
  static const red = Color(0xFF8A3A1E);

  static const head = TextStyle(
    fontFamily: 'Dial',
    fontWeight: FontWeight.w600,
    color: ink,
    letterSpacing: 1.2,
    height: 1.1,
  );
  // (the dial lettering's family, a little wider and calmer for reading)
  static const body = TextStyle(
    fontFamily: 'Manual',
    color: ink,
    fontSize: 15,
    height: 1.3,
    letterSpacing: 0.1,
  );
  static const small = TextStyle(fontFamily: 'Manual', color: faint, fontSize: 12.5, height: 1.35);

  @override
  ConsumerState<_Manual> createState() => _ManualState();
}

class _ManualState extends ConsumerState<_Manual> with _CameraPick<_Manual> {
  @override
  Widget build(BuildContext context) {
    final global = ref.watch(globalSettingsProvider);
    final g = ref.read(globalSettingsProvider.notifier);
    final cams = ref.watch(cameraSettingsProvider);
    final n = ref.read(cameraSettingsProvider.notifier);
    final pro = ref.watch(proProvider);
    final spec = pickedSpec(AppMode.film);
    final local = cams[spec.id] ?? CameraLocalSettings.defaultsFor(spec);
    final ratio = spec.aspectLocked ? spec.defaultAspect : local.aspect;

    return _sheet(
      landscape: widget.landscape,
      child: (scroll) => DefaultTextStyle(
        style: _Manual.body,
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 30),
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFB9B0A1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.only(bottom: 6),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _Manual.ink, width: 2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text("OWNER'S MANUAL", style: _Manual.head.copyWith(fontSize: 30)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'DARKROOM ${AppInfo.version}',
                    style: _Manual.small.copyWith(
                      fontSize: 11,
                      letterSpacing: 1,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // Pro: a boxed note, as a leaflet has for the optional extras
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              decoration: BoxDecoration(border: Border.all(color: _Manual.ink, width: 1.5)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('DARKROOM PRO', style: _Manual.head.copyWith(fontSize: 17)),
                        const SizedBox(height: 2),
                        Text(
                          pro
                              ? 'Unlocked: unlimited film and battery, every film and camera. Thank you!'
                              : 'One roll and one battery charge a day. Pro lifts the limits and adds 9 films and cameras.',
                          style: _Manual.small,
                        ),
                      ],
                    ),
                  ),
                  if (!pro) ...[
                    const SizedBox(width: 10),
                    _ManualButton(label: 'UNLOCK', onTap: () => showProSheet(context)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            _ManualSection(
              number: 1,
              title: 'This film',
              trailing: _ManualStepper(
                label: spec.name,
                onPrev: () => stepCamera(AppMode.film, -1),
                onNext: () => stepCamera(AppMode.film, 1),
              ),
              children: [
                _ManualRow(
                  label: 'Frame',
                  child: spec.aspectLocked
                      ? Text('${ratio.label} (fixed)', style: _Manual.small)
                      : _ManualBoxes(
                          values: [for (final a in spec.aspects) a.label],
                          selected: spec.aspects.indexOf(ratio),
                          onSelected: (i) => unawaited(n.setAspect(spec.id, spec.aspects[i])),
                        ),
                ),
                _ManualRow(
                  label: 'Grain',
                  child: _ManualBoxes(
                    values: [for (final v in GrainStrength.values) _grainName(v)],
                    selected: GrainStrength.values.indexOf(local.grain),
                    // weak grain a cool dark blue, strong a warm dark orange
                    inks: const [Color(0xFF243B5E), _Manual.ink, Color(0xFF9A4A14)],
                    onSelected: (i) => unawaited(n.setGrain(spec.id, GrainStrength.values[i])),
                  ),
                ),
                if (spec.supportsTimestamp)
                  _ManualTick(
                    label: _stampName(spec.timestampStyle),
                    value: local.timestamp,
                    onChanged: (v) => unawaited(n.setTimestamp(spec.id, v)),
                    last: true,
                  ),
              ],
            ),
            _ManualSection(
              number: 2,
              title: 'Sound and feel',
              children: [
                _ManualScale(
                  value: global.sfxVolume,
                  onChanged: (v) => unawaited(g.setSfxVolume(v, save: false)),
                  onChangeEnd: (v) {
                    unawaited(g.setSfxVolume(v));
                    Sfx.shutterFilm.play(); // a sample at the new level
                  },
                ),
                _ManualTick(
                  label: 'Haptics',
                  value: global.haptics,
                  onChanged: (v) => unawaited(g.setHaptics(v)),
                ),
                _ManualTick(
                  label: 'Fancy graphics (3D cameras)',
                  note: DeviceMemory.low
                      ? 'Some effects are reduced on this phone, to keep it smooth.'
                      : null,
                  value: global.controls3d,
                  onChanged: (v) => unawaited(g.setControls3d(v)),
                  last: true,
                ),
              ],
            ),
            _ManualSection(
              number: 3,
              title: 'The darkroom',
              children: [
                _ManualTick(
                  label: 'Tell me when prints are ready',
                  value: global.notificationsEnabled,
                  onChanged: (v) => unawaited(_notifications(context, ref, v)),
                ),
                _ManualTick(
                  label: 'Keep an unfiltered copy too',
                  note: "Saved to 'Darkroom Originals'.",
                  value: global.saveOriginalCopy,
                  onChanged: (v) => unawaited(g.setSaveOriginalCopy(v)),
                  last: true,
                ),
              ],
            ),
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.only(top: 6),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _Manual.ink, width: 2)),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                children: [
                  _ManualLink('HOW IT WORKS', () => Navigator.of(context).push(HowItWorksScreen.route())),
                  _ManualLink('CAMERA SHOP', () => showCameraShop(context, mode: AppMode.film)),
                  _ManualLink('FEEDBACK', () => unawaited(_feedback(context))),
                  _ManualLink('PRIVACY', () => unawaited(Support.openPrivacy())),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualSection extends StatelessWidget {
  const _ManualSection({required this.number, required this.title, required this.children, this.trailing});

  final int number;
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '$number   ${title.toUpperCase()}',
              style: _Manual.head.copyWith(fontSize: 15, color: _Manual.red, letterSpacing: 2),
            ),
            const Spacer(),
            ?trailing,
          ],
        ),
        const SizedBox(height: 4),
        ...children,
      ],
    ),
  );
}

/// ◀ name ▶: which film's settings these are.
class _ManualStepper extends StatelessWidget {
  const _ManualStepper({required this.label, required this.onPrev, required this.onNext});

  final String label;
  final VoidCallback onPrev, onNext;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _arrow(Icons.chevron_left, 'Previous film', onPrev),
      Text(label.toUpperCase(), style: _Manual.head.copyWith(fontSize: 14)),
      _arrow(Icons.chevron_right, 'Next film', onNext),
    ],
  );

  static Widget _arrow(IconData icon, String label, VoidCallback onTap) => Semantics(
    button: true,
    label: label,
    child: InkResponse(
      onTap: onTap,
      radius: 20,
      child: SizedBox(width: 32, height: 40, child: Icon(icon, size: 20, color: _Manual.ink)),
    ),
  );
}

class _ManualRow extends StatelessWidget {
  const _ManualRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 44),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: _Manual.rule, width: 1)),
    ),
    child: Row(
      children: [
        Text(label),
        const SizedBox(width: 12),
        Expanded(
          child: Align(alignment: Alignment.centerRight, child: child),
        ),
      ],
    ),
  );
}

/// Printed option boxes, the chosen one inked in.
class _ManualBoxes extends StatelessWidget {
  const _ManualBoxes({required this.values, required this.selected, required this.onSelected, this.inks});

  final List<String> values;
  final int selected;
  final ValueChanged<int> onSelected;

  /// Each option's ink when chosen (default: the manual's black).
  final List<Color>? inks;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.end,
    spacing: 4,
    runSpacing: 4,
    children: [
      for (var i = 0; i < values.length; i++)
        Semantics(
          button: true,
          selected: i == selected,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              unawaited(Haptics.selectionClick());
              onSelected(i);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: i == selected ? (inks?[i] ?? _Manual.ink) : null,
                  border: Border.all(
                    color: i == selected ? (inks?[i] ?? _Manual.ink) : _Manual.ink,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  values[i],
                  style: TextStyle(
                    fontFamily: 'Manual',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: i == selected ? _Manual.paper : _Manual.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

/// A line with a printed tick box: the whole line takes the tap.
class _ManualTick extends StatelessWidget {
  const _ManualTick({
    required this.label,
    required this.value,
    required this.onChanged,
    this.note,
    this.last = false,
  });

  final String label;
  final String? note;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool last;

  @override
  Widget build(BuildContext context) => Semantics(
    toggled: value,
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        unawaited(Haptics.selectionClick());
        onChanged(!value);
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          border: last ? null : const Border(bottom: BorderSide(color: _Manual.rule, width: 1)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label),
                  if (note != null) Text(note!, style: _Manual.small),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: value ? _Manual.ink : null,
                border: Border.all(color: _Manual.ink, width: 1.5),
              ),
              child: value ? const Icon(Icons.check, size: 15, color: _Manual.paper) : null,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Sound: a printed scale with a red marker.
class _ManualScale extends StatelessWidget {
  const _ManualScale({required this.value, required this.onChanged, required this.onChangeEnd});

  final double value;
  final ValueChanged<double> onChanged, onChangeEnd;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.only(top: 8),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: _Manual.rule, width: 1)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Text('Sound effects')),
            Text(
              value <= 0 ? 'Off' : '${(value * 100).round()}%',
              style: _Manual.small.copyWith(
                color: _Manual.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        SizedBox(
          height: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Positioned.fill(child: CustomPaint(painter: _ScalePainter())),
              SliderTheme(
                data: const SliderThemeData(
                  trackHeight: 0,
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  thumbColor: _Manual.red,
                  overlayColor: Color(0x228A3A1E),
                  thumbShape: _BarThumb(),
                  trackShape: RectangularSliderTrackShape(),
                ),
                // (in tens: 0, 10 ... 100%)
                child: Slider(value: value, divisions: 10, onChanged: onChanged, onChangeEnd: onChangeEnd),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// The scale under the sound marker: a rule with long and short ticks.
class _ScalePainter extends CustomPainter {
  const _ScalePainter();

  @override
  void paint(Canvas canvas, Size size) {
    // (the slider's own inset: its thumb travels between these)
    const inset = 24.0;
    final p = Paint()
      ..color = _Manual.ink
      ..strokeWidth = 1.5;
    final y = size.height / 2;
    canvas.drawLine(Offset(inset, y), Offset(size.width - inset, y), p);
    p.strokeWidth = 1;
    for (var i = 0; i <= 10; i++) {
      final x = inset + (size.width - 2 * inset) * i / 10;
      final long = i.isEven;
      canvas.drawLine(Offset(x, y - (long ? 7 : 4)), Offset(x, y), p);
    }
  }

  @override
  bool shouldRepaint(_ScalePainter old) => false;
}

/// A slim upright bar for a thumb (a printed pointer, not a dot).
class _BarThumb extends SliderComponentShape {
  const _BarThumb();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(10, 20);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    context.canvas.drawRect(
      Rect.fromCenter(center: center, width: 9, height: 20),
      Paint()..color = sliderTheme.thumbColor ?? _Manual.red,
    );
  }
}

class _ManualButton extends StatelessWidget {
  const _ManualButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        color: _Manual.ink,
        child: Text(label, style: _Manual.head.copyWith(fontSize: 15, color: _Manual.paper)),
      ),
    ),
  );
}

class _ManualLink extends StatelessWidget {
  const _ManualLink(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
        child: Text(label, style: _Manual.head.copyWith(fontSize: 14, decoration: TextDecoration.underline)),
      ),
    ),
  );
}

// ===========================================================================
// Digital: the camera's menu screen
// ===========================================================================

enum _Tab { camera, sound, setup, pro }

class _Menu extends ConsumerStatefulWidget {
  const _Menu({required this.landscape});

  final bool landscape;

  static const body = Color(0xFF2B2A28);
  static const lcd = Color(0xFF10140F);
  static const ink = Color(0xFFC9E7B8);
  static const dim = Color(0xFF7E9A71);
  static const line = Color(0xFF263021);
  static const edge = Color(0xFF4E6346);

  static const text = TextStyle(fontFamily: 'W98', color: ink, fontSize: 16, height: 1.2, letterSpacing: 0.5);

  @override
  ConsumerState<_Menu> createState() => _MenuState();
}

class _MenuState extends ConsumerState<_Menu> with _CameraPick<_Menu> {
  _Tab _tab = _Tab.camera;

  /// The menu screen's height: one size for every tab (the longest fits).
  static const _panel = 456.0;

  /// The row last touched, highlighted as the camera's cursor would be.
  String? _cursor;

  void _touch(String row) {
    unawaited(Haptics.selectionClick());
    setState(() => _cursor = row);
  }

  @override
  Widget build(BuildContext context) {
    return _sheet(
      landscape: widget.landscape,
      // (the menu screen's own height, and no more)
      initial: ((_panel + 70) / MediaQuery.sizeOf(context).height).clamp(0.3, 0.92),
      child: (scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF5A5753),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: _panel,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              color: _Menu.lcd,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1B1A18), width: 3),
            ),
            child: DefaultTextStyle(
              style: _Menu.text,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      for (final t in _Tab.values) ...[
                        if (t != _Tab.camera) const SizedBox(width: 6),
                        Expanded(child: _tabKey(t)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: switch (_tab) {
                          _Tab.camera => _camera(),
                          _Tab.sound => _sound(),
                          _Tab.setup => _setup(),
                          _Tab.pro => _pro(),
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '< > CHANGE   TAP OK',
                          style: _Menu.text.copyWith(fontSize: 12, color: _Menu.dim),
                        ),
                      ),
                      Text('v${AppInfo.version}', style: _Menu.text.copyWith(fontSize: 12, color: _Menu.dim)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabKey(_Tab t) {
    final on = t == _tab;
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          unawaited(Haptics.selectionClick());
          setState(() {
            _tab = t;
            _cursor = null;
          });
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? _Menu.ink : null,
            border: Border.all(color: on ? _Menu.ink : _Menu.edge),
          ),
          child: FittedBox(
            child: Text(
              t.name.toUpperCase(),
              style: _Menu.text.copyWith(fontSize: 13, color: on ? _Menu.lcd : _Menu.ink),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _camera() {
    final cams = ref.watch(cameraSettingsProvider);
    final n = ref.read(cameraSettingsProvider.notifier);
    final spec = pickedSpec(AppMode.digital);
    final local = cams[spec.id] ?? CameraLocalSettings.defaultsFor(spec);
    final ratio = spec.aspectLocked ? spec.defaultAspect : local.aspect;
    void ratioBy(int by) {
      final i = spec.aspects.indexOf(ratio);
      unawaited(n.setAspect(spec.id, spec.aspects[(i + by) % spec.aspects.length]));
    }

    return [
      _MenuRow(
        label: spec.name.toUpperCase(),
        value: '',
        dim: true,
        selected: false,
        onTap: () {},
        onPrev: () => stepCamera(AppMode.digital, -1),
        onNext: () => stepCamera(AppMode.digital, 1),
      ),
      _MenuRow(
        label: 'RATIO',
        value: spec.aspectLocked ? '${ratio.label} FIXED' : ratio.label,
        selected: _cursor == 'ratio',
        onTap: () {
          _touch('ratio');
          if (!spec.aspectLocked) ratioBy(1);
        },
        onPrev: spec.aspectLocked ? null : () => ratioBy(-1),
        onNext: spec.aspectLocked ? null : () => ratioBy(1),
      ),
      if (spec.supportsTimestamp)
        _MenuRow(
          label: spec.timestampStyle == TimestampStyle.camcorderOsd ? 'TAPE READOUT' : 'DATE STAMP',
          value: local.timestamp ? 'ON' : 'OFF',
          off: !local.timestamp,
          selected: _cursor == 'stamp',
          onTap: () {
            _touch('stamp');
            unawaited(n.setTimestamp(spec.id, !local.timestamp));
          },
        ),
    ];
  }

  List<Widget> _sound() {
    final global = ref.watch(globalSettingsProvider);
    final g = ref.read(globalSettingsProvider.notifier);
    void volumeBy(double by) {
      final v = ((global.sfxVolume + by) * 10).round().clamp(0, 10) / 10;
      unawaited(g.setSfxVolume(v));
      Sfx.shutterFilm.play();
    }

    return [
      _MenuRow(
        label: 'SOUND',
        value: global.sfxVolume <= 0 ? 'OFF' : '${(global.sfxVolume * 100).round()}%',
        selected: _cursor == 'sound',
        onTap: () => _touch('sound'),
        onPrev: () {
          _touch('sound');
          volumeBy(-0.1);
        },
        onNext: () {
          _touch('sound');
          volumeBy(0.1);
        },
      ),
      _toggle('haptics', 'HAPTICS', global.haptics, (v) => unawaited(g.setHaptics(v))),
      if (!CameraControl.present)
        _toggle('zoom', 'VOLUME KEYS ZOOM', global.volumeZoom, (v) => unawaited(g.setVolumeZoom(v))),
    ];
  }

  List<Widget> _setup() {
    final global = ref.watch(globalSettingsProvider);
    final g = ref.read(globalSettingsProvider.notifier);
    return [
      _toggle('3d', '3D CAMERAS', global.controls3d, (v) => unawaited(g.setControls3d(v))),
      _toggle(
        'notify',
        'NOTIFY WHEN READY',
        global.notificationsEnabled,
        (v) => unawaited(_notifications(context, ref, v)),
      ),
      _toggle(
        'original',
        'KEEP ORIGINAL',
        global.saveOriginalCopy,
        (v) => unawaited(g.setSaveOriginalCopy(v)),
      ),
      _go('HOW IT WORKS', () => Navigator.of(context).push(HowItWorksScreen.route())),
      _go('CAMERA SHOP', () => showCameraShop(context, mode: AppMode.digital)),
      _go('FEEDBACK', () => unawaited(_feedback(context))),
      _go('PRIVACY', () => unawaited(Support.openPrivacy())),
    ];
  }

  List<Widget> _pro() {
    final pro = ref.watch(proProvider);
    final spec = ref.watch(activeSpecProvider);
    final today = ref.watch(allowanceProvider).at(AllowanceNotifier.now());
    final size = Allowance.sizeOf(spec);
    final left = pro ? size : today.left(spec).clamp(0, size);
    const cells = 10;
    final lit = size <= 0 ? 0 : (left / size * cells).ceil();
    return [
      Text('DARKROOM PRO', style: _Menu.text.copyWith(fontSize: 18)),
      const SizedBox(height: 6),
      Text(
        pro
            ? 'UNLOCKED: UNLIMITED FILM AND BATTERY, EVERY CAMERA. THANK YOU!'
            : 'ONE ROLL AND ONE BATTERY CHARGE A DAY. PRO LIFTS THE LIMITS AND ADDS 9 FILMS AND CAMERAS.',
        style: _Menu.text.copyWith(fontSize: 13, color: _Menu.dim, height: 1.35),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(border: Border.all(color: _Menu.edge)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('BATTERY TODAY', style: _Menu.text.copyWith(fontSize: 13))),
                Text(pro ? 'FULL' : '$left LEFT', style: _Menu.text.copyWith(fontSize: 13)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var i = 0; i < cells; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(child: Container(height: 10, color: i < lit ? _Menu.ink : _Menu.line)),
                ],
              ],
            ),
          ],
        ),
      ),
      if (!pro) ...[
        const SizedBox(height: 10),
        _MenuRow(label: 'UNLOCK PRO', value: '>', selected: true, onTap: () => showProSheet(context)),
      ],
    ];
  }

  Widget _toggle(String id, String label, bool value, ValueChanged<bool> onChanged) => _MenuRow(
    label: label,
    value: value ? 'ON' : 'OFF',
    off: !value,
    selected: _cursor == id,
    onTap: () {
      _touch(id);
      onChanged(!value);
    },
  );

  Widget _go(String label, VoidCallback onTap) => _MenuRow(
    label: label,
    value: '>',
    selected: false,
    onTap: () {
      unawaited(Haptics.selectionClick());
      onTap();
    },
  );
}

/// One menu line: its name, its value on the right (◀ ▶ either side when it
/// steps), inverted when the cursor is on it.
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
    this.onPrev,
    this.onNext,
    this.off = false,
    this.dim = false,
  });

  final String label, value;
  final bool selected, off, dim;
  final VoidCallback onTap;
  final VoidCallback? onPrev, onNext;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? _Menu.lcd : (dim ? _Menu.dim : _Menu.ink);
    Widget arrow(String glyph, VoidCallback? f, String what) => f == null
        ? const SizedBox.shrink()
        : Semantics(
            button: true,
            label: what,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: f,
              child: SizedBox(
                width: 34,
                height: 44,
                child: Center(
                  child: Text(glyph, style: _Menu.text.copyWith(color: fg)),
                ),
              ),
            ),
          );
    return Semantics(
      button: true,
      selected: selected,
      label: '$label $value',
      excludeSemantics: onPrev == null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: EdgeInsets.only(left: 10, right: onNext == null ? 10 : 0),
          decoration: BoxDecoration(
            color: selected ? _Menu.ink : null,
            border: selected ? null : const Border(bottom: BorderSide(color: _Menu.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: _Menu.text.copyWith(color: fg)),
              ),
              arrow('<', onPrev, 'Previous'),
              Text(value, style: _Menu.text.copyWith(color: selected ? _Menu.lcd : (off ? _Menu.dim : fg))),
              arrow('>', onNext, 'Next'),
            ],
          ),
        ),
      ),
    );
  }
}
