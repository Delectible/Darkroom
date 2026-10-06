/// Version and revision history (shown in Help > About).
class AppInfo {
  const AppInfo._();

  static const name = 'Darkroom';
  static const version = '1.2.0';
  static const build = '1998.10.05';

  static const revisions = <(String, String)>[
    (
      '1.2',
      'Film looks rebuilt from colour LUTs with real grain and halation. Super 8 movie camera. '
          '1999 Floppy Cam. Move to C:, Save / Save all, landscape shots, quiet notifications. '
          'Renamed from RetroCam to Darkroom.',
    ),
    ('1.1', 'Fixed ruined prints and stuck videos. Faster film viewfinder. New stock picker and app icon.'),
    ('1.0', 'First roll: Film Mode with the darkroom and corkboard, Digital Mode with the SD card.'),
  ];
}
