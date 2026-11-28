import 'package:material_ui/material_ui.dart';

import '../../../../core/brand/app_look.dart';
import 'win98_widgets.dart';

/// User Profile's "App icon" box: the icons as desktop icons, the picked
/// one selected the way Darkroom 98 selects an icon (navy over it and its
/// label). Applied with the window's OK (app_look.dart).
class Win98LookChoice extends StatelessWidget {
  const Win98LookChoice({super.key, required this.selected, required this.onChanged});

  final AppLook selected;
  final ValueChanged<AppLook> onChanged;

  @override
  Widget build(BuildContext context) {
    final changing = selected != Look.current;
    return Win98GroupBox(
      label: 'App icon',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final look in AppLook.values)
                Expanded(
                  child: _Icon(look: look, selected: look == selected, onTap: () => onChanged(look)),
                ),
            ],
          ),
          if (changing) ...[
            const SizedBox(height: 6),
            Text(AppLook.note, style: W98.text.copyWith(fontSize: (W98.text.fontSize ?? 12) * 0.9)),
          ],
        ],
      ),
    );
  }
}

class _Icon extends StatelessWidget {
  const _Icon({required this.look, required this.selected, required this.onTap});

  final AppLook look;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final picture = Image.asset(look.preview, width: 40, height: 40, filterQuality: FilterQuality.medium);
    return Semantics(
      button: true,
      selected: selected,
      label: '${look.title} icon. ${look.blurb}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              selected
                  ? ColorFiltered(
                      colorFilter: ColorFilter.mode(W98.navy.withValues(alpha: 0.45), BlendMode.srcATop),
                      child: picture,
                    )
                  : picture,
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                color: selected ? W98.navy : null,
                child: Text(
                  look.title,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: W98.text.copyWith(color: selected ? W98.selectInk : W98.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
