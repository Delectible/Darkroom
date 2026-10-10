import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/db/media_repository.dart';
import 'package:darkroom/core/providers.dart';
import 'package:darkroom/core/settings/settings_repository.dart';
import 'package:darkroom/features/camera/application/camera_ui_state.dart'
    show UserNameNotifier, Win98ThemeNotifier, userNameProvider, win98ThemeProvider;
import 'package:darkroom/features/sd_card/application/sd_card_controller.dart';
import 'package:darkroom/features/sd_card/presentation/win98/explorer_screen.dart';
import 'package:darkroom/features/sd_card/presentation/win98/win98_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Prefs extends ExplorerPrefsNotifier {
  @override
  ExplorerPrefs build() => const ExplorerPrefs();
}

class _Name extends UserNameNotifier {
  @override
  String? build() => 'Sam';
}

String? _saved;

class _Theme extends Win98ThemeNotifier {
  @override
  String? build() => _saved;

  @override
  Future<void> set(String name) async => state = _saved = name;
}

/// Win98 colour schemes (View > Options > Themes): the explorer opens in
/// the saved one, and picking another recolours the open screens at once.
/// `SHOTS=dir` saves the explorer in every scheme.
void main() {
  final shots = Platform.environment['SHOTS'];
  final boundary = GlobalKey();
  final items = [
    MediaItem(
      id: '1',
      cameraId: 'ccd2003',
      kind: MediaKind.photo,
      status: MediaStatus.ready,
      fileName: 'DSC00001.JPG',
      capturedAt: DateTime(2026, 10, 6, 9),
      readyAt: DateTime(2026, 10, 6, 9),
      bytes: 380000,
      width: 640,
      height: 480,
      location: MediaLocation.sd,
    ),
  ];

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 2856);
    tester.view.devicePixelRatio = 3.1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sdCardItemsProvider.overrideWith((ref) => Stream.value(items)),
          explorerPrefsProvider.overrideWith(_Prefs.new),
          userNameProvider.overrideWith(_Name.new),
          win98ThemeProvider.overrideWith(_Theme.new),
          initialGlobalSettingsProvider.overrideWithValue(const GlobalSettings()),
          initialCameraSettingsProvider.overrideWithValue(const {}),
        ],
        child: RepaintBoundary(
          key: boundary,
          child: const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: ExplorerMonitor(child: ExplorerScreen()),
          ),
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    if (shots == null) return;
    await tester.runAsync(() async {
      final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final png = await (await ro.toImage(pixelRatio: 1)).toByteData(format: ui.ImageByteFormat.png);
      await File('$shots/theme_$name.png').writeAsBytes(png!.buffer.asUint8List());
    });
  }

  Color? titleColor(WidgetTester tester) {
    final title = tester.widget<Text>(find.textContaining('Exploring').first);
    return title.style?.color;
  }

  tearDown(() => _saved = null);

  for (final scheme in Win98Scheme.all) {
    testWidgets('opens in the saved scheme: ${scheme.name}', (tester) async {
      _saved = scheme.name;
      await pump(tester);
      expect(W98.scheme.name, scheme.name);
      expect(titleColor(tester), scheme.titleInk);
      await shoot(tester, scheme.name.replaceAll(' ', '_'));
    });
  }

  testWidgets('picking a theme in View > Options recolours it at once', (tester) async {
    await pump(tester);
    expect(W98.scheme, Win98Scheme.standard);
    await tester.tap(find.text('View').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Options').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Themes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Night'));
    await tester.pumpAndSettle();
    expect(W98.scheme.name, 'Night');
    expect(_saved, 'Night');
    await shoot(tester, 'options_night');
    // The explorer underneath repainted too (its title is a const-free
    // child of a const window, so only the restyle reaches it).
    expect(titleColor(tester), W98.scheme.titleInk);
  });
}
