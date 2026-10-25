import 'package:darkroom/core/processing/film/film_profile.dart';
import 'package:darkroom/features/camera/application/lab_note.dart';
import 'package:darkroom/features/cameras/domain/camera_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

/// A slow film runs out of light in the dark long before a fast one.
void main() {
  double under(String id, double ev) => FilmProfile.forStock(id)!.process.underFor(ev);

  test('daylight: every 35 mm film is fine', () {
    for (final id in ['velvia50', 'ektar100', 'portra400', 'cinestill800t']) {
      expect(under(id, 14), 0, reason: id);
    }
  });

  test('a dim street: the slow films fall behind, the fast one copes', () {
    expect(under('ektar100', 4), closeTo(3.9, 0.05));
    expect(under('portra400', 4), closeTo(1.9, 0.05));
    expect(under('cinestill800t', 4), closeTo(0.9, 0.05));
    expect(under('velvia50', 1), 4); // capped: past that it's just black
  });

  test('the lab leaves a note when it was too dark for the film', () {
    final vivid = CameraCatalog.film.firstWhere((s) => s.film?.id == 'ektar100');
    final note = LabNote.forShot(vivid, 4, flash: false)!;
    expect(note, startsWith('Note from the Lab: too dark for ${vivid.name}'));
    expect(LabNote.forShot(vivid, 4, flash: true), isNull);
    expect(LabNote.forShot(vivid, 13, flash: false), isNull);
    expect(LabNote.forShot(vivid, null, flash: false), isNull);
  });
}
