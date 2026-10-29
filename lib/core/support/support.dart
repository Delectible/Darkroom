import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../diagnostics/crash_log.dart';

/// Getting in touch: feedback and bug reports by email to the developer,
/// and the privacy policy. Nothing is sent by the app itself: it opens the
/// phone's mail app with a message the user can read and edit first.
class Support {
  const Support._();

  static const email = 'lucaraheb1@gmail.com';
  static const privacyUrl = 'https://github.com/Delectible/Darkroom/blob/main/docs/PRIVACY.md';

  static Future<bool> openPrivacy() async {
    try {
      return await launchUrl(Uri.parse(privacyUrl), mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// The message's text: room to write, then the app version, the phone's
  /// system and (if there is one from the last week) the latest crash
  /// report, so a bug can be found without back-and-forth.
  static String feedbackBody({DateTime? now}) {
    final b = StringBuffer('\n\n\n---\nDarkroom ${AppInfo.version}\n');
    try {
      b.writeln('${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    } catch (_) {}
    final crash = CrashLog.reports.where(
      (r) => (now ?? DateTime.now()).difference(r.at) < const Duration(days: 7),
    );
    if (crash.isNotEmpty) {
      final t = crash.first.text;
      b.writeln('\nLatest crash report (delete it if you like):');
      b.writeln(t.length > 1500 ? '${t.substring(0, 1500)}...' : t);
    }
    return b.toString();
  }

  /// Opens a new email to the developer. False if no mail app took it; the
  /// address is then on the clipboard.
  static Future<bool> sendFeedback() async {
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      query: _query({'subject': 'Darkroom ${AppInfo.version} feedback', 'body': feedbackBody()}),
    );
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return true;
    } catch (_) {}
    await Clipboard.setData(const ClipboardData(text: email));
    return false;
  }

  // mailto wants %20 for spaces, not '+'.
  static String _query(Map<String, String> q) =>
      q.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
}
