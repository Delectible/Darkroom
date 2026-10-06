import 'package:flutter_test/flutter_test.dart';
import 'package:darkroom/core/notifications/notification_service.dart';
import 'package:darkroom/core/utils/pixel_font.dart';
import 'package:darkroom/features/sd_card/presentation/win98/pixel_icons.dart';

void main() {
  test('consolidated darkroom message', () {
    expect(
      NotificationService.developedMessage(photos: 1, videos: 0),
      'A photo has finished developing in the Darkroom.',
    );
    expect(
      NotificationService.developedMessage(photos: 3, videos: 0),
      '3 photos have finished developing in the Darkroom.',
    );
    expect(
      NotificationService.developedMessage(photos: 2, videos: 1),
      '2 photos and a reel have finished developing in the Darkroom.',
    );
    expect(
      NotificationService.developedMessage(photos: 0, videos: 1),
      'A reel has finished developing in the Darkroom.',
    );
  });

  test('timestamp formats', () {
    final t = DateTime(2026, 10, 5, 14, 32, 7);
    expect(TimestampFormat.ledDate(t), "'26 10 05");
    expect(TimestampFormat.phone(t), '2026/10/05 14:32');
    expect(TimestampFormat.camcorder(t), ['PM  2:32:07', 'OCT 05 2026']);
  });

  test('pixel sprites are 16x16', () {
    expect(spritesAreValid(), isTrue);
  });
}
