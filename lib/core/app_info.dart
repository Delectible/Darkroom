/// Version and revision history (shown in Help > About).
class AppInfo {
  const AppInfo._();

  static const name = 'Darkroom';
  static const version = '1.4.0';
  static const build = '1998.10.05';

  /// What changed in this build, in plain words: Google Play's "What's new"
  /// (tool/play/whats_new.py). Replace it every build.
  static const latest =
      'A welcome tour, Windows 98 on a beige monitor (swipe left on a digital camera), '
      'your name under Start > User Profile, the phone\'s real battery on the digital cameras, '
      'faster Polaroid sharing and a tidier revision history.';

  /// Help > About: the main ideas of each version, a few words each.
  static const revisions = <(String, List<String>)>[
    (
      '1.4',
      [
        'Welcome tour, with your name on your prints',
        'Windows 98 slides in on a beige monitor',
        'Swipe right for the corkboard, left for Windows 98',
        'Photoreal shutter buttons',
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
        'Polaroid 600 with notes on the border',
        'Super 8 projector with tape-deck keys',
        'Films retuned against real scans',
        'Toss the camera to swap film and digital',
        'Windows 98 games, sounds and a Shut Down',
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
