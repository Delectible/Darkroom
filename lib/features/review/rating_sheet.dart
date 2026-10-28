import 'package:flutter/material.dart';

import '../../core/device/upright.dart';
import '../../core/theme/retro_theme.dart';

/// Our own ask before the store's rating prompt: the store's prompt out of
/// nowhere feels like begging. True = "Yea!" (show the store's prompt).
Future<bool> showRatingSheet(BuildContext context) async {
  final palette = RetroPalette.of(context);
  final yes = await showUprightSheet<bool>(
    context,
    backgroundColor: palette.body,
    builder: (_, {required landscape}) => Theme(data: palette.toTheme(), child: const RatingSheet()),
  );
  return yes ?? false;
}

class RatingSheet extends StatelessWidget {
  const RatingSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final p = RetroPalette.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/artwork/rabbit_mark.png', height: 76, filterQuality: FilterQuality.medium),
            const SizedBox(height: 14),
            Text(
              'Give us a shoutout!',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.text, fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              "If you've been enjoying your Darkroom, please take just a minute to tell us. "
              "If you haven't been enjoying it, we promise we'll listen to your rant.",
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
                    child: const Text('No thanks'),
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
                    child: const Text('Yea!'),
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
