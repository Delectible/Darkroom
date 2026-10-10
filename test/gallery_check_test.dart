import 'package:darkroom/core/db/media_repository.dart';
import 'package:darkroom/core/device/gallery_check.dart';
import 'package:darkroom/features/viewer/presentation/media_actions.dart';
import 'package:flutter_test/flutter_test.dart';

/// Saved copies deleted from the phone's photos are noticed by name: the
/// library may have numbered a clashing name, case doesn't matter, and an
/// instant print goes in as its file name (border baked in), the rest as
/// the stored file.
void main() {
  test('a saved name is found, numbered or not, any case', () {
    final names = {'roll001_07.jpg', 'dsc000051.jpg', 'reel003.mp4'};
    expect(GalleryCheck.contains(names, 'ROLL001_07.JPG'), isTrue);
    expect(GalleryCheck.contains(names, 'DSC00005.JPG'), isTrue, reason: 'numbered by the library');
    expect(GalleryCheck.contains(names, 'REEL003.MP4'), isTrue);
    expect(GalleryCheck.contains(names, 'ROLL001_08.JPG'), isFalse);
    expect(GalleryCheck.contains(names, 'DSC00006.JPG'), isFalse);
  });

  test('the name each item is saved under', () {
    MediaItem item(String camera, String file, String out, {MediaKind kind = MediaKind.photo}) => MediaItem(
      id: file,
      cameraId: camera,
      kind: kind,
      status: MediaStatus.ready,
      fileName: file,
      capturedAt: DateTime(2026),
      readyAt: DateTime(2026),
      outputPath: out,
    );
    expect(galleryNameFor(item('polaroid600', 'PACK0001.JPG', '/data/x/abc.jpg')), 'PACK0001.JPG');
    expect(galleryNameFor(item('portra400', 'ROLL001_07.JPG', '/data/x/ROLL001_07.jpg')), 'ROLL001_07.jpg');
    expect(
      galleryNameFor(item('super8', 'REEL003.MP4', '/data/x/REEL003.mp4', kind: MediaKind.video)),
      'REEL003.mp4',
    );
  });
}
