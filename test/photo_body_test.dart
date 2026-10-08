import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:darkroom/core/device/physical_orientation.dart';
import 'package:darkroom/core/processing/photo_pipeline.dart';
import 'package:darkroom/core/providers.dart';
import 'package:darkroom/core/settings/settings_repository.dart';
import 'package:darkroom/core/theme/retro_theme.dart';
import 'package:darkroom/features/camera/application/camera_ui_state.dart';
import 'package:darkroom/features/camera/presentation/body_swap.dart';
import 'package:darkroom/features/camera/presentation/photo_body.dart';
import 'package:darkroom/features/camera/presentation/widgets/camera_controls.dart';
import 'package:darkroom/features/cameras/domain/camera_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Mode extends AppModeNotifier {
  _Mode(this.mode);

  final AppMode mode;

  @override
  AppMode build() => mode;
}

class _Selected extends SelectedCameraNotifier {
  @override
  Map<AppMode, String> build() => {AppMode.film: 'portra400', AppMode.digital: 'ccd2003'};
}

class _Flash extends FlashNotifier {
  @override
  Map<AppMode, FlashSetting> build() => {AppMode.film: FlashSetting.auto, AppMode.digital: FlashSetting.auto};
}

class _Held extends PhysicalOrientationNotifier {
  @override
  DeviceOrientation build() => DeviceOrientation.portraitUp;
}

class _Lens extends LensNotifier {
  @override
  CameraLensDirection build() => CameraLensDirection.back;
}

/// The photoreal bodies (assets/body): every frame the app can ask for is
/// bundled, turns cross-fade without a jump, and each body lays out at a
/// Pixel 9 Pro's size, face-on and turned mid-swap. `SHOTS=dir` saves them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final shots = Platform.environment['SHOTS'];
  final boundary = GlobalKey();

  test('turns bracket smoothly', () async {
    final art = await BodyArt.load();
    if (art == null) return markTestSkipped('no body art bundled');
    for (final mode in AppMode.values) {
      if (!art.has(mode)) continue;
      final p = art.part(mode, 'panel')!;
      // Weight of the far frame climbs 0 -> 1 between rendered turns and
      // hands over cleanly at each one.
      var last = -1.0;
      for (var d = 0.0; d <= p.yaws.last; d += 0.25) {
        final (lo, hi, f) = p.bracket(d);
        expect(lo <= d && d <= hi, isTrue);
        final pos = lo + (hi - lo) * f;
        expect(pos, greaterThanOrEqualTo(last));
        last = pos;
      }
    }
  });

  test('3D off (or no art) draws the classic bodies', () async {
    final art = await BodyArt.load();
    if (art == null) return markTestSkipped('no body art bundled');
    for (final on in [true, false]) {
      final c = ProviderContainer(
        overrides: [
          initialGlobalSettingsProvider.overrideWithValue(GlobalSettings(controls3d: on)),
          bodyArtProvider.overrideWith((ref) async => art),
        ],
      );
      addTearDown(c.dispose);
      await c.read(bodyArtProvider.future);
      for (final mode in AppMode.values) {
        if (!art.has(mode)) continue;
        expect(c.read(photoBodyProvider(mode)), on ? same(art) : isNull);
      }
    }
  });

  test('every frame the app draws is bundled', () async {
    final art = await BodyArt.load();
    if (art == null) return markTestSkipped('no body art bundled');
    final names = {
      AppMode.film: [
        'panel',
        'plate-top',
        'plate-bot',
        'frame',
        'flash',
        'flashtab',
        'aspect',
        'lens',
        'lensdot',
        'menu',
        'memo',
        'print',
        'tray',
        'shutter',
        'lever',
        'release',
        'run',
      ],
      AppMode.digital: [
        'panel',
        'frame',
        'pill',
        'pillwide',
        'pillsmall',
        'lens',
        'lensdot',
        'lcd',
        'review',
        'rocker',
        'tray',
        'shutter',
        'rec',
      ],
    };
    for (final mode in AppMode.values) {
      if (!art.has(mode)) continue;
      for (final name in names[mode]!) {
        final p = art.part(mode, name);
        expect(p, isNotNull, reason: '$mode $name');
        for (final y in p!.yaws) {
          for (final st in p.states.isEmpty ? <String?>[null] : p.states) {
            if (y != 0 && st != null && p.yaw0States.contains(st)) continue;
            await rootBundle.load(p.asset(st, y));
          }
        }
      }
    }
  });

  for (final mode in AppMode.values) {
    {
      testWidgets('${mode.name} body through a swap', (tester) async {
        final art = await tester.runAsync(BodyArt.load);
        if (art == null || !art.has(mode)) return markTestSkipped('no ${mode.name} body bundled');
        tester.view.physicalSize = const Size(1280, 2856);
        tester.view.devicePixelRatio = 3.1;
        addTearDown(tester.view.reset);
        BodyArt.faceOnly = false;

        final film = mode == AppMode.film;
        final yaw = ValueNotifier<double>(0);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              initialGlobalSettingsProvider.overrideWithValue(const GlobalSettings()),
              initialCameraSettingsProvider.overrideWithValue(const {}),
              physicalOrientationProvider.overrideWith(_Held.new),
              bodyArtProvider.overrideWith((ref) async => art),
              appModeProvider.overrideWith(() => _Mode(mode)),
              selectedCameraProvider.overrideWith(_Selected.new),
              flashProvider.overrideWith(_Flash.new),
              lensProvider.overrideWith(_Lens.new),
            ],
            child: RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: RetroPalette.forMode(mode).toTheme(),
                home: ValueListenableBuilder(
                  valueListenable: yaw,
                  builder: (context, deg, child) => BodyYaw(yaw: deg * math.pi / 180, child: child!),
                  child: Scaffold(
                    body: Stack(
                      children: [
                        Positioned.fill(
                          child: BodyBackdrop(art: art, mode: mode, top: 106, bottom: 36),
                        ),
                        Positioned(
                          left: 23,
                          top: 109,
                          right: 23,
                          height: 582,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Positioned.fill(child: ColoredBox(color: Color(0xFF0C0B0A))),
                              Positioned.fill(child: BodySlice(art.part(mode, 'frame')!)),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 12,
                          right: 12,
                          top: 52,
                          child: Row(
                            children: [
                              const FlashButton(),
                              const SizedBox(width: 8),
                              AspectButton(onCycle: () {}),
                              const Spacer(),
                              const LensFlipButton(enabled: true),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 60,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              SizedBox.square(
                                dimension: 84,
                                child: Center(child: BodySprite(art.part(mode, film ? 'print' : 'review')!)),
                              ),
                              SizedBox.square(
                                dimension: 120,
                                child: Center(child: BodySprite(art.part(mode, 'shutter')!, state: 'up')),
                              ),
                              StockButton(onOpen: () {}),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        // Decode everything on screen, then let it paint.
        await tester.runAsync(() async {
          await art.precache(tester.element(find.byType(Scaffold)));
        });
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);

        // Turn through a swap and back a frame at a time: every frame it
        // needs is already decoded (nothing pops in or stalls mid-swap).
        final cache = PaintingBinding.instance.imageCache;
        for (var d = 0.0; d <= 48; d += 1.5) {
          yaw.value = d;
          await tester.pump(const Duration(milliseconds: 16));
          final waiting = <String>[];
          for (final e in find.byType(Image).evaluate()) {
            final img = (e.widget as Image).image;
            if (img is! ResizeImage || img.imageProvider is! AssetImage) continue;
            final name = (img.imageProvider as AssetImage).assetName;
            if (!name.startsWith(BodyArt.root)) continue;
            final key = await img.obtainKey(createLocalImageConfiguration(e));
            final st = cache.statusForKey(key);
            if (st.pending || !st.keepAlive) waiting.add(name);
          }
          expect(waiting, isEmpty, reason: '${mode.name} at $d degrees');
          if (shots != null && const [0.0, 9.0, 27.0, 45.0].contains(d)) {
            await tester.runAsync(() async {
              final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
              final image = await ro.toImage(pixelRatio: 1);
              final png = await image.toByteData(format: ui.ImageByteFormat.png);
              await File('$shots/body_${mode.name}_${d.round()}.png').writeAsBytes(png!.buffer.asUint8List());
            });
          }
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
