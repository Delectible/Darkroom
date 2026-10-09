/// Version and revision history (shown in Help > About).
class AppInfo {
  const AppInfo._();

  static const name = 'Darkroom';
  static const version = '1.7.0';
  static const build = '1998.10.05';

  /// What changed in this build, in plain words: Google Play's "What's new"
  /// (tool/play/whats_new.py). Replace it every build.
  static const latest =
      'Real 3D cameras: each body is now a live 3D model that turns smoothly when you swap, with its labels, '
      'LCD and viewfinder staying on it, sharp at every angle. Dials, keys and the lever move on the model.';

  /// Help > About: the main ideas of each version, a few words each.
  static const revisions = <(String, List<String>)>[
    ('1.7', ['Live 3D camera bodies: labels stay on as they turn']),
    ('1.6', ['Whole-camera 3D renders that turn when you swap', 'Film photos at full camera resolution']),
    (
      '1.5',
      [
        'Photoreal 3D camera bodies, rendered in Blender',
        'Corkboard, projector and Darkroom 98 in landscape',
      ],
    ),
    (
      '1.4',
      [
        'Welcome tour, with your name on your prints',
        'Darkroom 98 slides in on a beige monitor',
        'Swipe right for the corkboard, left for Darkroom 98',
        'Photoreal 3D shutter buttons (or flat)',
        'Performance mode for older phones',
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
