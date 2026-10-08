import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/db/media_repository.dart';
import 'package:darkroom/core/providers.dart';
import 'package:darkroom/core/settings/settings_repository.dart';
import 'package:darkroom/features/sd_card/application/sd_card_controller.dart';
import 'package:darkroom/features/sd_card/presentation/win98/explorer_dialogs.dart';
import 'package:darkroom/features/sd_card/presentation/win98/explorer_screen.dart';
import 'package:darkroom/features/camera/application/camera_ui_state.dart'
    show UserNameNotifier, userNameProvider;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Prefs extends ExplorerPrefsNotifier {
  @override
  ExplorerPrefs build() => const ExplorerPrefs();
}

/// Every explorer tab, menu and dialog at a Pixel 9 Pro's size, through the
/// 1.3x Win98 scale: any overflow fails. `SHOTS=dir` saves each frame.
void main() {
  final shots = Platform.environment['SHOTS'];
  final boundary = GlobalKey();

  MediaItem file(
    String id,
    String camera,
    String name, {
    MediaKind kind = MediaKind.photo,
    bool onC = false,
  }) => MediaItem(
    id: id,
    cameraId: camera,
    kind: kind,
    status: MediaStatus.ready,
    fileName: name,
    capturedAt: DateTime(2026, 10, 6, 9),
    readyAt: DateTime(2026, 10, 6, 9),
    bytes: kind == MediaKind.video ? 5400000 : 380000,
    durationMs: kind == MediaKind.video ? 42000 : null,
    width: 640,
    height: 480,
    location: onC ? MediaLocation.c : MediaLocation.sd,
  );

  final items = [
    file('1', 'ccd2003', 'DSC00001.JPG'),
    file('2', 'flipphone', 'IMG_0002.JPG'),
    file('3', 'floppy99', 'FLP00003.JPG'),
    file('4', 'camcorder90', 'CLIP0004.MP4', kind: MediaKind.video),
    file('5', 'ccd2003', 'DSC00005.JPG', onC: true),
  ];

  var shotTag = '';
  Future<void> shoot(WidgetTester tester, String name) async {
    if (shots == null) return;
    await tester.runAsync(() async {
      final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await ro.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$shots/explorer_$name$shotTag.png').writeAsBytes(png!.buffer.asUint8List());
    });
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  // Portrait, and held sideways (the app turns Win98 to landscape).
  for (final land in [false, true]) {
    testWidgets('explorer ${land ? 'landscape' : 'portrait'}: tabs, menus and dialogs fit', (tester) async {
      shotTag = land ? '_land' : '';
      tester.view.physicalSize = land ? const Size(2856, 1280) : const Size(1280, 2856);
      tester.view.devicePixelRatio = 3.1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sdCardItemsProvider.overrideWith((ref) => Stream.value(items)),
            explorerPrefsProvider.overrideWith(_Prefs.new),
            userNameProvider.overrideWith(_Name.new),
            initialGlobalSettingsProvider.overrideWithValue(const GlobalSettings()),
            initialCameraSettingsProvider.overrideWithValue(const {}),
          ],
          child: RepaintBoundary(
            key: boundary,
            // On its monitor, as it appears in the app.
            child: const MaterialApp(
              debugShowCheckedModeBanner: false,
              home: ExplorerMonitor(child: ExplorerScreen()),
            ),
          ),
        ),
      );
      await settle(tester);

      for (final tab in ['SD Card (E:)', 'A:', 'C:', 'My Computer']) {
        await tester.tap(find.text(tab).first);
        await settle(tester);
        await shoot(tester, 'tab_${tab.replaceAll(RegExp(r'[^A-Za-z]'), '')}');
      }
      for (final menu in ['File', 'Edit', 'View', 'Tools', 'Help']) {
        await tester.tap(find.text(menu).first);
        await settle(tester);
        await shoot(tester, 'menu_$menu');
        await tester.tapAt(Offset(5, land ? 380 : 900)); // dismiss
        await settle(tester);
      }
      await tester.tap(find.text('Start'));
      await settle(tester);
      await shoot(tester, 'start');
      await tester.tapAt(Offset(land ? 800 : 400, 100));
      await settle(tester);

      final ctx = tester.element(find.byType(ExplorerScreen));
      for (final (name, open) in <(String, Future<void> Function())>[
        (
          'properties',
          () => showDriveProperties(ctx, label: 'SD Card (E:)', used: 3000000, capacity: sdCardCapacityBytes),
        ),
        ('options', () => showExplorerOptions(ctx)),
        ('about', () => showAboutDarkroom(ctx)),
        ('tip', () => showTipOfTheDay(ctx)),
        ('run', () => showRunDialog(ctx)),
        (
          'box',
          () => win98Box(
            ctx,
            'Confirm File Delete',
            "Are you sure you want to delete 'DSC00001.JPG'?",
            buttons: const ['Yes', 'No'],
          ),
        ),
      ]) {
        final future = open();
        await settle(tester);
        await shoot(tester, 'dialog_$name');
        Navigator.of(tester.element(find.byType(ExplorerScreen)), rootNavigator: true).pop();
        await settle(tester);
        await future;
      }
    });
  }
}

class _Name extends UserNameNotifier {
  @override
  String? build() => 'Gabe';
}
