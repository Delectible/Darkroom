import 'dart:io';

import 'package:darkroom/core/processing/film/film_profile.dart';
import 'package:darkroom/core/processing/look_spec.dart';
import 'package:darkroom/features/cameras/domain/camera_catalog.dart';
import 'package:darkroom/features/cameras/domain/camera_spec.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every stock / body in the catalog must be complete. Adding a camera from
/// docs/NEW_CAMERA_FORM.md should only ever need a catalog entry, a look and
/// an artwork file; this test catches any of the three being missing or
/// inconsistent.
void main() {
  const all = CameraCatalog.all;

  test('ids are unique and listed in exactly one mode', () {
    expect(all.map((c) => c.id).toSet().length, all.length);
    for (final c in all) {
      expect(CameraCatalog.forMode(c.mode), contains(c), reason: c.id);
      expect(CameraCatalog.byId(c.id), same(c), reason: c.id);
    }
  });

  for (final c in all) {
    group(c.id, () {
      test('has artwork on disk', () {
        expect(c.artwork, startsWith('assets/artwork/'));
        expect(File(c.artwork).existsSync(), isTrue, reason: 'missing ${c.artwork}');
      });

      test('aspect options are consistent', () {
        expect(c.aspects, isNotEmpty);
        expect(c.aspects, contains(c.defaultAspect));
      });

      test('names fit the UI', () {
        expect(c.name.trim(), isNotEmpty);
        expect(c.subtitle.length, lessThanOrEqualTo(48), reason: 'subtitle is one line in the picker');
        expect(c.badge.length, lessThanOrEqualTo(10), reason: 'badge sits in the viewfinder HUD');
      });

      if (c.isFilm) {
        test('film: has a film profile and no digital look', () {
          expect(FilmProfile.forStock(c.id), isNotNull, reason: 'add it to film_profile.dart');
          expect(c.look, isNull);
        });
        test('film: never zooms', () => expect(c.zoom, isNull));
        test('film: no explorer drive', () => expect(c.storage, DigitalStorage.sdCard));
        test('film: sensible darkroom time and roll', () {
          expect(c.developTime, greaterThan(Duration.zero));
          expect(c.developTime, lessThanOrEqualTo(const Duration(hours: 1)));
          expect(c.roll.frames, inInclusiveRange(1, 72));
          expect(c.roll.prefix.length, 4, reason: '8.3-style file names');
        });
        if (c.isInstant) {
          test('instant: square frame, stills only', () {
            expect(c.aspects, [c.defaultAspect]);
            expect(c.defaultAspect.long, c.defaultAspect.short);
            expect(c.recordsVideo, isFalse);
          });
        }
      } else {
        test('digital: has a look, no film profile', () {
          expect(c.look, isNotNull);
          expect(c.look!.kind, isNot(ShaderKind.film));
          expect(FilmProfile.forStock(c.id), isNull);
        });
        test('digital: stills only use plain prints', () => expect(c.printStyle, PrintStyle.print));
        test('digital: zoom is set and sane', () {
          expect(c.zoom, isNotNull, reason: 'every digital body has zoom buttons');
          expect(c.zoom!.max, inInclusiveRange(1.0, 20.0));
          expect(c.zoom!.endToEnd, greaterThan(Duration.zero));
        });
        test('digital: 4-character file prefixes', () {
          expect(c.photoPrefix.length, 4);
          if (c.recordsVideo) expect(c.videoPrefix.length, 4);
        });
      }
    });
  }
}
