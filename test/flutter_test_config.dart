import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Tests measure and draw text with the real fonts: Roboto (Android's UI
/// font, which the Win98 screens and Material theme use) and the Material
/// icons, loaded from the Flutter SDK running the tests. Layout checks then
/// catch overflows the phone would show, not ones only the wide test font
/// produces. Without the SDK fonts, tests fall back to the test font.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final fonts = _sdkFonts();
  if (fonts != null) {
    final roboto = FontLoader('Roboto');
    for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']) {
      final file = File('${fonts.path}/$f');
      if (file.existsSync()) roboto.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await roboto.load();
    final icons = File('${fonts.path}/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())))).load();
    }
  }
  // The app's own bundled fonts (pubspec `fonts:`), by family.
  for (final (family, file) in [('Caveat', 'Caveat-SemiBold.ttf'), ('W98', 'DotGothic16-Regular.ttf')]) {
    final f = File('assets/fonts/$file');
    if (f.existsSync()) {
      await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())))).load();
    }
  }
  await testMain();
}

/// `sdk/bin/cache/artifacts/material_fonts`, from FLUTTER_ROOT or the path
/// of the flutter_tester binary running us.
Directory? _sdkFonts() {
  final roots = [
    Platform.environment['FLUTTER_ROOT'],
    // .../bin/cache/artifacts/engine/<platform>/flutter_tester
    File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path,
  ];
  for (final r in roots) {
    if (r == null) continue;
    final d = Directory('$r/bin/cache/artifacts/material_fonts');
    if (d.existsSync()) return d;
  }
  return null;
}
