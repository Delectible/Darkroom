import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../core/brand/app_look.dart';
import '../../../core/device/haptics.dart';

/// The welcome tour's "Want a different look?": the app icons to pick from,
/// as a sheet in the tour's own dark style. (Darkroom 98 has its own, in
/// User Profile: win98/look_choice.dart.)
Future<void> showLookPicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF17171C),
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => const _LookSheet(),
  );
}

class _LookSheet extends StatelessWidget {
  const _LookSheet();

  static const _ink = Color(0xFFF3EEE6);
  static const _muted = Color(0xFF9C978F);
  static const _accent = Color(0xFFFF5A4F);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: ValueListenableBuilder<AppLook>(
          valueListenable: Look.notifier,
          builder: (context, current, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Pick your app icon',
                textAlign: TextAlign.center,
                style: TextStyle(color: _ink, fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  for (final look in AppLook.values)
                    Expanded(
                      child: _Tile(
                        look: look,
                        selected: look == current,
                        onTap: () {
                          if (look == current) return;
                          unawaited(Haptics.selectionClick());
                          unawaited(Look.choose(look));
                        },
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                AppLook.note,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 8),
              Text(
                'You can change it later in Darkroom 98, under User Profile.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted.withValues(alpha: 0.75), fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done', style: TextStyle(color: _accent, fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.look, required this.selected, required this.onTap});

  final AppLook look;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${look.title} icon. ${look.blurb}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: selected ? _LookSheet._accent : Colors.transparent, width: 2.5),
                ),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Image.asset(
                    look.preview,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  look.title,
                  style: TextStyle(
                    color: selected ? _LookSheet._ink : _LookSheet._muted,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
