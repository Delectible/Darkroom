/// Version and revision history (shown in Help > About).
class AppInfo {
  const AppInfo._();

  static const name = 'Darkroom';
  static const version = '1.4.3';
  static const build = '1998.10.05';

  /// What changed in this build, in plain words: Google Play's "What's new"
  /// (tool/play/whats_new.py). Replace it every build.
  static const latest =
      'Films get their own names: Vivid 100, Portrait 400, Classic 400 and Instant 600. Same looks, '
      'same grain. The mines game is now Minefield (Start > Run..., MINES).';

  /// Help > About: the main ideas of each version, a few words each.
  static const revisions = <(String, List<String>)>[
    (
      '1.4',
      [
        'Welcome tour, with your name on your prints',
        'Darkroom 98 slides in on a beige monitor',
        'Swipe right for the corkboard, left for Darkroom 98',
        'Photoreal 3D shutter buttons',
        'Watch prints develop up close',
        'Sound volume slider, haptics switch, crash reports',
        'Real phone battery on the digital cameras',
        'Tape-style sound for Super 8 and camcorder',
      ],
    ),
    (
      '1.3',
      [
        'Corkboard in a wooden frame, on real cork',
        'Instant film with notes on the border',
        'Super 8 projector with tape-deck keys',
        'Films retuned against real scans',
        'Toss the camera to swap film and digital',
        'Darkroom 98 games, sounds and a Shut Down',
        'Volume buttons take the picture',
        'On Google Play',
      ],
    ),
    (
      '1.2',
      [
        'Film looks with real grain and halation',
        'Super 8 movie camera and 1999 Floppy Cam',
        'Renamed from RetroCam to Darkroom',
      ],
    ),
    ('1.1', ['Fixed ruined prints and stuck videos', 'Faster viewfinder, new picker and icon']),
    ('1.0', ['First roll: film darkroom and corkboard, digital SD card']),
  ];
}
