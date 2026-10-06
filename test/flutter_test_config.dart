import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Screenshot runs (SHOTS=dir) render with real fonts instead of the test
/// font's boxes: Roboto from the Flutter SDK is registered under the
/// family names the tests fall back to. Ordinary test runs are unchanged.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final sdk = Platform.environment['FLUTTER_ROOT'];
  if (Platform.environment['SHOTS'] != null && sdk != null) {
    final dir = Directory('$sdk/bin/cache/artifacts/material_fonts');
    for (final family in ['Roboto', 'FlutterTest', 'Ahem']) {
      final loader = FontLoader(family);
      for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']) {
        final file = File('${dir.path}/$f');
        if (file.existsSync()) loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      }
      await loader.load();
    }
    final icons = File('${dir.path}/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())))).load();
    }
  }
  await testMain();
}
