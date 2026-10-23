import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/skins/camera_skins.dart';
import '../win98_widgets.dart';

/// Records a game milestone toward the camera skins ([SkinStats]) and, if
/// it wins one, says so in a Darkroom 98 message box. Quietly does nothing
/// where there's no app around it (the games' own tests).
void awardSkins(BuildContext context, String stat, {int by = 1, int? atLeast}) {
  final ProviderContainer c;
  try {
    c = ProviderScope.containerOf(context, listen: false);
  } catch (_) {
    return;
  }
  unawaited(() async {
    final won = await SkinAwards.record(c, stat, by: by, atLeast: atLeast);
    if (won.isEmpty || !context.mounted) return;
    final names = won.map((s) => '${s.name} (${s.mode.name})').join(', ');
    await showWin98MessageBox(
      context,
      title: 'Camera Exchange',
      message: 'You won a camera skin: $names!\n\nPut it on in Settings > Camera Shop.',
    );
  }());
}
