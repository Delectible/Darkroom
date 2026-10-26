import 'package:darkroom/core/db/media_repository.dart';
import 'package:darkroom/core/device/gallery_check.dart';
import 'package:darkroom/features/viewer/presentation/media_actions.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('darkroom/gallery');
  var album = <Map<String, String>>[];

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'entries' ? album : null,
    );
  });

  MediaItem saved(String id, String name) => MediaItem(
    id: id,
    cameraId: 'ccd2003',
    kind: MediaKind.photo,
    status: MediaStatus.ready,
    fileName: name,
    outputPath: '/data/sd/$name',
    capturedAt: DateTime(2026),
    readyAt: DateTime(2026),
    location: MediaLocation.c,
    savedAt: DateTime(2026),
  );

  test('a copy renamed in another app is still there, by its id', () async {
    final links = GalleryLinks.memory();
    final a = saved('a', 'DSC0001.JPG'), b = saved('b', 'DSC0002.JPG');
    album = [
      {'id': 'i:1', 'name': 'DSC0001.JPG'},
      {'id': 'i:2', 'name': 'DSC0002.JPG'},
    ];
    // First look: found by name, linked.
    expect(await missingFromGallery([a, b], digitalAlbum, links: links), isEmpty);
    expect(links['a'], 'i:1');
    // Renamed in the phone's files app; the other one deleted.
    album = [
      {'id': 'i:1', 'name': 'Beach day.jpg'},
    ];
    final renamed = <String, String>{};
    final missing = await missingFromGallery(
      [a, b],
      digitalAlbum,
      links: links,
      onRenamed: (m, name) async => renamed[m.id] = name,
    );
    expect(missing!.map((m) => m.id), ['b']);
    expect(renamed, {'a': 'Beach day.jpg'});
  });

  test('without links, a name match (or a numbered copy) counts', () async {
    album = [
      {'id': 'i:9', 'name': 'DSC00011.JPG'},
    ];
    expect(await missingFromGallery([saved('a', 'DSC0001.JPG')], digitalAlbum), isEmpty);
  });
}
