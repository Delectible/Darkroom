/// Version and revision history (shown in Help > About).
class AppInfo {
  const AppInfo._();

  static const name = 'Darkroom';
  static const version = '1.3.2';
  static const build = '1998.10.05';

  static const revisions = <(String, String)>[
    (
      '1.3',
      'Bigger Windows 98 screens with a real Media Player, zoom slider and camera info. '
          'Camcorder tapes come off floppies in A: (mind the disk swaps) and record their '
          'on-screen display, zoom bar included. Smooth zoom. Reels show their first frames. '
          'Polaroid 600: square instant prints that develop in 20 seconds, with notes '
          'written on the border. Zoom buttons on every digital camera. '
          'Swipe anywhere in the picker; swipe the film name or box to switch stocks. '
          'Zoomed photos pan instead of flipping. Reels replay after the end. '
          'Smoother corkboard. Flip phone opens the right way.',
    ),
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
