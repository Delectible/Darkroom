import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/sfx.dart';
import '../../../core/device/upright.dart';
import '../../../core/processing/crop_math.dart';
import '../../../core/processing/film/film_profile.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/retro_theme.dart';
import '../../camera/application/camera_ui_state.dart';
import '../../cameras/domain/camera_catalog.dart';
import '../../cameras/domain/camera_spec.dart';
import '../application/settings_controllers.dart';

Future<void> showSettingsSheet(BuildContext context) {
  final palette = RetroPalette.of(context);
  return showUprightSheet<void>(
    context,
    backgroundColor: palette.body,
    builder: (_, {required landscape}) => Theme(
      data: palette.toTheme(),
      child: _SettingsSheet(landscape: landscape),
    ),
  );
}

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet({required this.landscape});

  /// Held sideways: a fixed panel instead of a draggable sheet.
  final bool landscape;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RetroPalette.of(context);
    final global = ref.watch(globalSettingsProvider);
    final g = ref.read(globalSettingsProvider.notifier);
    final mode = ref.watch(appModeProvider);
    final cams = ref.watch(cameraSettingsProvider);

    Widget list(ScrollController? scroll) => ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: p.textMuted, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        const SizedBox(height: 16),
        _Heading('GLOBAL', p),
        _Toggle(
          title: 'Darkroom development',
          subtitle: global.darkroomEnabled
              ? 'Film shots take ${CameraSpec.defaultDevelopTime.inMinutes} minutes to develop '
                    '(instant prints: under a minute).'
              : 'Film shots develop instantly.',
          value: global.darkroomEnabled,
          onChanged: (v) => unawaited(g.setDarkroomEnabled(v)),
        ),
        _Toggle(
          title: 'Notifications',
          subtitle: 'Tell me when prints finish developing.',
          value: global.notificationsEnabled,
          onChanged: (v) async {
            final ok = await g.setNotificationsEnabled(v);
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Notifications are blocked in system settings.')));
            }
          },
        ),
        _Toggle(
          title: 'Save original unfiltered copy',
          subtitle: "Also save the cropped, un-graded photo to 'Darkroom Originals'.",
          value: global.saveOriginalCopy,
          onChanged: (v) => unawaited(g.setSaveOriginalCopy(v)),
        ),
        _VolumeSlider(
          value: global.sfxVolume,
          onChanged: (v) => unawaited(g.setSfxVolume(v, save: false)),
          onChangeEnd: (v) {
            unawaited(g.setSfxVolume(v));
            Sfx.shutterFilm.play(); // a sample at the new level
          },
        ),
        _Toggle(
          title: 'Haptics',
          subtitle: 'Little vibrations on the shutter, swaps and buttons.',
          value: global.haptics,
          onChanged: (v) => unawaited(g.setHaptics(v)),
        ),
        _Toggle(
          title: '3D controls',
          subtitle:
              'Buttons turn with the camera when you swap. Off: flat buttons, a little lighter on older phones.',
          value: global.controls3d,
          onChanged: (v) => unawaited(g.setControls3d(v)),
        ),
        _Toggle(
          title: 'Volume buttons zoom',
          subtitle:
              'The volume buttons take the picture. Turn this on to zoom with them on digital cameras instead.',
          value: global.volumeZoom,
          onChanged: (v) => unawaited(g.setVolumeZoom(v)),
        ),
        const SizedBox(height: 18),
        _Heading(mode == AppMode.film ? 'FILM STOCKS' : 'CAMERAS', p),
        for (final spec in CameraCatalog.forMode(mode))
          _CameraSettingsTile(spec: spec, settings: cams[spec.id] ?? CameraLocalSettings.defaultsFor(spec)),
      ],
    );
    if (landscape) {
      return LayoutBuilder(
        builder: (context, box) => SizedBox(height: box.maxHeight * 0.92, child: list(null)),
      );
    }
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (context, scroll) => list(scroll),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, this.p);

  final String text;
  final RetroPalette p;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(color: p.accent, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 12),
    ),
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.title, required this.subtitle, required this.value, required this.onChanged});

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = RetroPalette.of(context);
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      title: Text(
        title,
        style: TextStyle(color: p.text, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(subtitle, style: TextStyle(color: p.textMuted, fontSize: 12)),
    );
  }
}

/// Sound effects level: off at the far left, half way by default.
class _VolumeSlider extends StatelessWidget {
  const _VolumeSlider({required this.value, required this.onChanged, required this.onChangeEnd});

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final p = RetroPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sound effects',
                  style: TextStyle(color: p.text, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                value <= 0 ? 'Off' : '${(value * 100).round()}%',
                style: TextStyle(color: p.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          Text(
            'Shutter clicks, swooshes and the rest. Videos keep their sound.',
            style: TextStyle(color: p.textMuted, fontSize: 12),
          ),
          Row(
            children: [
              Icon(Icons.volume_off, size: 18, color: p.textMuted),
              Expanded(
                child: Slider.adaptive(value: value, onChanged: onChanged, onChangeEnd: onChangeEnd),
              ),
              Icon(Icons.volume_up, size: 18, color: p.textMuted),
            ],
          ),
        ],
      ),
    );
  }
}

class _CameraSettingsTile extends ConsumerWidget {
  const _CameraSettingsTile({required this.spec, required this.settings});

  final CameraSpec spec;
  final CameraLocalSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RetroPalette.of(context);
    final n = ref.read(cameraSettingsProvider.notifier);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.bodyHighlight.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.bodyShadow.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            spec.name,
            style: TextStyle(color: p.text, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          _ChoiceRow<AspectRatioOption>(
            label: 'Default ratio',
            locked: spec.aspectLocked,
            values: spec.aspects,
            selected: spec.aspectLocked ? spec.defaultAspect : settings.aspect,
            name: (a) => a.label,
            onSelected: (a) => unawaited(n.setAspect(spec.id, a)),
          ),
          if (spec.film != null) ...[
            const SizedBox(height: 6),
            _ChoiceRow<GrainStrength>(
              label: 'Grain',
              values: GrainStrength.values,
              selected: settings.grain,
              name: (g) => switch (g) {
                GrainStrength.weak => 'Weak',
                GrainStrength.normal => 'Normal',
                GrainStrength.strong => 'Strong',
              },
              onSelected: (g) => unawaited(n.setGrain(spec.id, g)),
            ),
          ],
          if (spec.supportsTimestamp)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('Timestamp overlay', style: TextStyle(color: p.text)),
              subtitle: Text(
                _tsDescription(spec.timestampStyle),
                style: TextStyle(color: p.textMuted, fontSize: 11),
              ),
              value: settings.timestamp,
              onChanged: (v) => unawaited(n.setTimestamp(spec.id, v)),
            ),
        ],
      ),
    );
  }

  static String _tsDescription(TimestampStyle s) => switch (s) {
    TimestampStyle.ledDate => "Orange LED date imprint ('26 10 05)",
    TimestampStyle.phone => 'Date & time in the corner',
    TimestampStyle.camcorderOsd => 'Tape OSD burned in: clock, REC, battery and zoom bar',
    TimestampStyle.none => '',
  };
}

/// Label + chips that wrap onto the next line on narrow phones.
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.values,
    required this.selected,
    required this.name,
    required this.onSelected,
    this.locked = false,
  });

  final String label;
  final List<T> values;
  final T selected;
  final String Function(T) name;
  final ValueChanged<T> onSelected;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final p = RetroPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(label, style: TextStyle(color: p.textMuted, fontSize: 12)),
          ),
        ),
        Expanded(
          child: locked
              ? Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Icon(Icons.lock, size: 14, color: p.textMuted),
                      const SizedBox(width: 4),
                      Text(name(selected), style: TextStyle(color: p.text)),
                    ],
                  ),
                )
              : Wrap(
                  spacing: 4,
                  runSpacing: 0,
                  children: [
                    for (final v in values)
                      ChoiceChip(
                        label: Text(name(v)),
                        selected: selected == v,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => onSelected(v),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
