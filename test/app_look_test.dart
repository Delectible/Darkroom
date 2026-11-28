import 'dart:io';
import 'dart:ui' as ui;

import 'package:darkroom/core/brand/app_look.dart';
import 'package:darkroom/core/theme/darkroom_mark.dart';
import 'package:darkroom/features/cameras/domain/camera_catalog.dart';
import 'package:darkroom/features/sd_card/presentation/win98/pixel_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// The promise behind the app icon picker (app_look.dart): once someone
/// picks anything but the original, the rabbit with X'd-out eyes never
/// shows again, anywhere. These checks keep a later change from quietly
/// bringing it back.
void main() {
  tearDown(Look.reset);

  Iterable<File> dartFiles(String dir) =>
      Directory(dir).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  test('no rabbit picture skips the icon picked', () {
    for (final f in dartFiles('lib')) {
      if (f.path.endsWith('core/brand/app_look.dart')) continue;
      final src = f.readAsStringSync();
      expect(
        src.contains('rabbit_mark.png'),
        isFalse,
        reason: '${f.path}: use RabbitMark / Look.rabbitAsset',
      );
      expect(src.contains('rabbit_mark_eyeless'), isFalse, reason: f.path);
      // the drawn rabbit: its eyes are whatever Look allows, never forced on
      expect(RegExp(r'eyes:\s*true').hasMatch(src), isFalse, reason: f.path);
      expect(src.contains('ic_stat_darkroom'), isFalse, reason: '${f.path}: use Look.notificationIcon');
    }
  });

  test('every stock picture shown without eyes has its copy', () {
    Look.reset(AppLook.eyeless);
    for (final name in Look.eyelessArtwork) {
      expect(File('assets/artwork/eyeless/$name.webp').existsSync(), isTrue, reason: name);
    }
    for (final f in Directory('assets/artwork/eyeless').listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last.replaceAll('.webp', '');
      expect(Look.eyelessArtwork, contains(name), reason: 'copy not used: $name');
    }
    for (final spec in CameraCatalog.all) {
      final path = spec.artwork;
      expect(File(path).existsSync(), isTrue, reason: path);
      final name = path.split('/').last.replaceAll('.webp', '');
      if (Look.eyelessArtwork.contains(name)) expect(path, contains('/eyeless/'));
    }
    Look.reset();
    for (final spec in CameraCatalog.all) {
      expect(spec.artwork, isNot(contains('/eyeless/')));
    }
  });

  test('rabbit picture, picker pictures and notification glyph follow the pick', () {
    expect(Look.rabbitAsset, 'assets/artwork/rabbit_mark.png');
    expect(AppLook.classic.preview, 'assets/artwork/looks/classic.png');
    for (final look in AppLook.values.skip(1)) {
      Look.reset(look);
      expect(Look.eyes, isFalse);
      expect(Look.rabbitAsset, 'assets/artwork/rabbit_mark_eyeless.png');
      // someone who left the original never sees it, even in the picker
      expect(AppLook.classic.preview, 'assets/artwork/looks/eyeless.png');
      expect(Look.notificationIcon, isNot('@drawable/ic_stat_darkroom'));
    }
    for (final f in ['assets/artwork/rabbit_mark.png', 'assets/artwork/rabbit_mark_eyeless.png']) {
      expect(File(f).existsSync(), isTrue, reason: f);
    }
    for (final look in AppLook.values) {
      expect(File('assets/artwork/looks/${look.name}.png').existsSync(), isTrue, reason: look.name);
    }
  });

  test('every icon is built for Android and iPhone', () {
    const res = 'android/app/src/main/res';
    const dens = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final looksKt = File('android/app/src/main/kotlin/com/dingo/darkroom/Looks.kt').readAsStringSync();
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final workflow = File('.github/workflows/build-apk.yml').readAsStringSync();
    for (final look in AppLook.values) {
      Look.reset(look);
      final glyph = Look.notificationIcon.replaceFirst('@drawable/', '');
      for (final d in dens) {
        expect(File('$res/drawable-$d/$glyph.png').existsSync(), isTrue, reason: '$d $glyph');
      }
      expect(looksKt, contains('"${look.name}"'), reason: 'Looks.kt ${look.name}');
      expect(delegate, contains('"${look.name}"'), reason: 'AppDelegate ${look.name}');
      if (look == AppLook.classic) continue;
      final cap = '${look.name[0].toUpperCase()}${look.name.substring(1)}';
      expect(manifest, contains('android:name=".Look$cap"'), reason: 'manifest Look$cap');
      expect(manifest, contains('@mipmap/ic_launcher_${look.name}"'), reason: 'manifest icon ${look.name}');
      expect(File('$res/mipmap-anydpi-v26/ic_launcher_${look.name}.xml').existsSync(), isTrue);
      for (final d in dens) {
        for (final part in ['', '_foreground', '_monochrome']) {
          final f = '$res/mipmap-$d/ic_launcher_${look.name}$part.png';
          expect(File(f).existsSync(), isTrue, reason: f);
        }
      }
      final set = 'ios/Runner/Assets.xcassets/AppIcon$cap.appiconset';
      expect(File('$set/Contents.json').existsSync(), isTrue, reason: set);
      expect(delegate, contains('"AppIcon$cap"'));
      expect(workflow, contains('AppIcon$cap'), reason: 'build-apk.yml lists AppIcon$cap');
    }
    // each icon's own splash: the faceless rabbit, or the camera icon itself
    for (final (theme, splash) in [('Eyeless', 'rabbit_eyeless'), ('Instant', 'instant'), ('Lens', 'lens')]) {
      for (final d in dens) {
        expect(File('$res/drawable-$d/splash_$splash.png').existsSync(), isTrue, reason: '$d $splash');
      }
      for (final dir in ['values', 'values-night', 'values-v31', 'values-night-v31']) {
        expect(File('$res/$dir/styles.xml').readAsStringSync(), contains('LaunchTheme.$theme"'), reason: dir);
      }
      expect(manifest, contains('@style/LaunchTheme.$theme"'), reason: theme);
    }
    Look.reset(AppLook.instant);
    expect(Look.splashIcon, 'assets/artwork/looks/instant.png');
    Look.reset(AppLook.eyeless);
    expect(Look.splashIcon, isNull);
    // the iPhone's launch screen can't follow the pick: it has no rabbit
    final launch = File('ios/Runner/Base.lproj/LaunchScreen.storyboard').readAsStringSync();
    expect(launch.contains('<imageView'), isFalse);
  });

  Future<ui.Image> render(void Function(Canvas) paint, int w, int h) {
    final rec = ui.PictureRecorder();
    paint(Canvas(rec));
    return rec.endRecording().toImage(w, h);
  }

  Future<int> alphaAt(ui.Image image, int x, int y) async {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return bytes.getUint8((y * image.width + x) * 4 + 3);
  }

  test('the pixel rabbit loses its eyes', () async {
    Future<ui.Color> pixel(int x, int y) async {
      final image = await render(
        (c) => paintPixelIcon(c, PixelIcon.rabbit, const Rect.fromLTWH(0, 0, 16, 16)),
        16,
        16,
      );
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final i = (y * 16 + x) * 4;
      return ui.Color.fromARGB(
        bytes.getUint8(i + 3),
        bytes.getUint8(i),
        bytes.getUint8(i + 1),
        bytes.getUint8(i + 2),
      );
    }

    // (3, 10): a stroke of the left X
    expect(await pixel(3, 10), const ui.Color(0xFF000000));
    Look.reset(AppLook.lens);
    expect(await pixel(3, 10), const ui.Color(0xFFFFFFFF));
  });

  test('the drawn rabbit loses its eyes', () async {
    // 129 px tall: the design grid 1:1, so the left eye's centre is (28, 89)
    Future<int> eyeAlpha() async {
      final image = await render(
        (c) => DarkroomMarkPainter(color: Colors.white).paint(c, const Size(105, 129)),
        110,
        130,
      );
      return alphaAt(image, 28, 89);
    }

    expect(await eyeAlpha(), lessThan(40));
    Look.reset(AppLook.eyeless);
    expect(await eyeAlpha(), greaterThan(215));
  });
}
