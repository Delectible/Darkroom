import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/device/upright.dart';
import '../../core/review/review_prompt.dart';
import '../../core/support/support.dart';
import '../../core/theme/note_box.dart';
import '../../core/theme/retro_theme.dart';

/// Settings > CONTACT: email, Instagram, a rating, the privacy policy.
Future<void> showContactSheet(BuildContext context) {
  final palette = RetroPalette.of(context);
  return showUprightSheet<void>(
    context,
    backgroundColor: palette.body,
    builder: (_, {required landscape}) => Theme(data: palette.toTheme(), child: const ContactSheet()),
  );
}

class ContactSheet extends StatelessWidget {
  const ContactSheet({super.key});

  static Future<void> email() async {
    if (!await Support.sendFeedback()) {
      Notes.show('No mail app found. The address (${Support.email}) is copied.');
    }
  }

  static Future<void> instagram() async {
    if (!await Support.openInstagram()) {
      Notes.show("Couldn't open Instagram. Find us at ${Support.instagram}.");
    }
  }

  static Future<void> rate() async {
    if (!await ReviewPrompt.show()) Notes.show("The store couldn't open its rating box right now.");
  }

  @override
  Widget build(BuildContext context) {
    final p = RetroPalette.of(context);
    Widget row(IconData icon, String title, String sub, Future<void> Function() go) => ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon, color: p.accent),
      title: Text(
        title,
        style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(sub, style: TextStyle(color: p.textMuted, fontSize: 13)),
      onTap: () {
        Navigator.of(context).pop();
        unawaited(go());
      },
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/artwork/rabbit_mark.png', height: 64, filterQuality: FilterQuality.medium),
            const SizedBox(height: 12),
            Text(
              'Contact us',
              style: TextStyle(color: p.text, fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Questions, bugs, ideas: we read everything.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 12),
            row(Icons.help_outline, 'Help & support', 'Common questions on our website', () async {
              await Support.openSupport();
            }),
            row(Icons.mail_outline, 'Email us', Support.email, email),
            row(Icons.camera_alt_outlined, 'Instagram', Support.instagram, instagram),
            row(Icons.star_outline, 'Rate Darkroom', 'Tell others what you think', rate),
            row(Icons.lock_outline, 'Privacy policy', 'What we do (and don\'t) collect', () async {
              await Support.openPrivacy();
            }),
          ],
        ),
      ),
    );
  }
}
