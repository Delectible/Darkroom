import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';

import '../../core/device/haptics.dart';
import '../../core/providers.dart';
import '../../core/theme/darkroom_mark.dart';
import '../camera/application/camera_session_controller.dart';
import '../camera/application/camera_ui_state.dart';
import '../settings/application/settings_controllers.dart';

/// First-run tour: what the app is, how to drive it (gestures), a name for
/// the lab to write on your prints, then every permission asked for at once
/// with a reason for each. Shown once; replay from Win98 Help > Welcome Tour.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});

  /// Called when the tour is finished or skipped.
  final VoidCallback onDone;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _Ask { camera, microphone, photos, notifications }

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _bg = Color(0xFF0E0E12);
  static const _ink = Color(0xFFF3EEE6);
  static const _muted = Color(0xFF9C978F);
  static const _accent = Color(0xFFFF5A4F);

  final _pages = PageController();
  late final _name = TextEditingController(text: ref.read(userNameProvider) ?? '');
  int _page = 0;
  bool _asking = false;
  final Map<_Ask, bool> _granted = {};

  static const _count = 7;

  @override
  void dispose() {
    _pages.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(userNameProvider.notifier).set(_name.text);
    await ref.read(sharedPrefsProvider).setBool(PrefKeys.onboarded, true);
    widget.onDone();
  }

  void _next() {
    FocusScope.of(context).unfocus();
    if (_page >= _count - 1) {
      unawaited(_finish());
      return;
    }
    unawaited(_pages.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic));
  }

  /// One tap, every prompt, in a sensible order.
  Future<void> _askAll() async {
    if (_asking) return;
    setState(() => _asking = true);
    unawaited(Haptics.lightImpact());
    // Camera + microphone: opening the camera once is what makes Android /
    // iOS ask (the camera plugin has no separate request).
    var camera = false, mic = false;
    try {
      final cams = await availableCameras();
      if (cams.isNotEmpty) {
        Future<bool> open({required bool audio}) async {
          final c = CameraController(cams.first, ResolutionPreset.low, enableAudio: audio);
          try {
            await c.initialize();
            return true;
          } on CameraException catch (e) {
            if (audio && CameraSessionController.isAudioPermissionError(e.code)) return false;
            if (CameraSessionController.isCameraPermissionError(e.code)) camera = false;
            rethrow;
          } finally {
            await c.dispose();
          }
        }

        try {
          camera = mic = await open(audio: true);
          if (!mic) camera = await open(audio: false);
        } on CameraException {
          // Left false.
        }
      }
    } catch (_) {}
    var notify = false, photos = false;
    try {
      notify = await ref.read(notificationServiceProvider).requestPermission();
    } catch (_) {}
    try {
      photos = await Gal.hasAccess(toAlbum: true) || await Gal.requestAccess(toAlbum: true);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _asking = false;
      _granted
        ..[_Ask.camera] = camera
        ..[_Ask.microphone] = mic
        ..[_Ask.notifications] = notify
        ..[_Ask.photos] = photos;
    });
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _count - 1;
    final asked = _granted.isNotEmpty;
    return Scaffold(
      backgroundColor: _bg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedOpacity(
                opacity: last ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: TextButton(
                  onPressed: last ? null : () => _pages.jumpToPage(_count - 1),
                  child: const Text('Skip', style: TextStyle(color: _muted)),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  const _Page(
                    hero: _SplitRabbit(size: 120),
                    title: 'Hi. This is Darkroom.',
                    body:
                        'A camera that makes you wait for your photos. On purpose. '
                        "It's good for you, like vegetables, but with more grain.",
                  ),
                  const _Page(
                    icon: Icons.camera_roll_outlined,
                    title: 'Film: shoot now, see later.',
                    body:
                        'Pick a film (colour, black & white, an instant pack, even Super 8). Every shot goes into the '
                        'darkroom for about five minutes, then gets pinned to your corkboard.\n\n'
                        'Nothing lands in your phone\'s gallery until you tap Save. Very old-fashioned. Very you.',
                  ),
                  const _Page(
                    icon: Icons.save_outlined,
                    title: 'Digital: the year 2000 called.',
                    body:
                        'A floppy-disk camera, a CCD compact, a flip phone and a camcorder. Shots go onto a '
                        'pretend SD card, browsed on an extremely serious 1998 desktop.\n\n'
                        'Move them to C: to set them free. There may be games. We will deny everything.',
                  ),
                  const _Page(icon: Icons.swipe_outlined, title: 'Getting around', child: _Gestures()),
                  _Page(
                    icon: Icons.waving_hand_outlined,
                    title: 'What should we call you?',
                    body: "So the lab knows whose prints these are. (Optional. We won't make it weird.)",
                    child: Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: TextField(
                        controller: _name,
                        textAlign: TextAlign.center,
                        textCapitalization: TextCapitalization.words,
                        maxLength: 24,
                        style: const TextStyle(color: _ink, fontSize: 22, fontWeight: FontWeight.w700),
                        cursorColor: _accent,
                        decoration: const InputDecoration(
                          hintText: 'Your name',
                          hintStyle: TextStyle(color: Color(0xFF5A5650)),
                          counterText: '',
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF3A3632)),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: _accent, width: 2),
                          ),
                        ),
                        onSubmitted: (_) => _next(),
                      ),
                    ),
                  ),
                  _Page(
                    icon: Icons.view_in_ar_outlined,
                    title: 'How fancy?',
                    body:
                        'The camera buttons can be little 3D objects that turn when you swap cameras. '
                        'Flat ones are a touch lighter on older phones. Change it any time in Settings.',
                    child: Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: Row(
                        children: [
                          for (final on in [true, false]) ...[
                            if (!on) const SizedBox(width: 12),
                            Expanded(
                              child: _ChoiceCard(
                                icon: on ? Icons.view_in_ar : Icons.crop_square,
                                title: on ? '3D' : 'Flat',
                                note: on ? 'Recommended' : 'Lighter',
                                selected: ref.watch(globalSettingsProvider.select((s) => s.controls3d)) == on,
                                onTap: () {
                                  unawaited(Haptics.selectionClick());
                                  unawaited(ref.read(globalSettingsProvider.notifier).setControls3d(on));
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  _Page(
                    icon: Icons.verified_user_outlined,
                    title: 'A few quick yeses',
                    body: 'Darkroom keeps everything on your phone. Here is what it asks for, and why:',
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        _PermissionRow(
                          icon: Icons.photo_camera_outlined,
                          name: 'Camera',
                          why: 'To take pictures. Kind of the whole point.',
                          granted: _granted[_Ask.camera],
                        ),
                        _PermissionRow(
                          icon: Icons.mic_none,
                          name: 'Microphone',
                          why: "Sound for Super 8 and camcorder clips. We're not listening otherwise.",
                          granted: _granted[_Ask.microphone],
                        ),
                        _PermissionRow(
                          icon: Icons.photo_library_outlined,
                          name: 'Photos',
                          why: 'Only used when you tap Save or move files to C:.',
                          granted: _granted[_Ask.photos],
                        ),
                        _PermissionRow(
                          icon: Icons.notifications_none,
                          name: 'Notifications',
                          why: 'A quiet nudge when prints are ready. No buzzing, no spam.',
                          granted: _granted[_Ask.notifications],
                        ),
                        if (asked && _granted.values.any((g) => !g))
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'No worries: anything you skipped can be turned on later in your phone\'s settings.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: _muted, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _count; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == _page ? 22 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: i == _page ? _accent : const Color(0xFF3A3632),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _asking
                          ? null
                          : last && !asked
                          ? _askAll
                          : _next,
                      child: Text(
                        _asking
                            ? 'Asking nicely…'
                            : last
                            ? (asked ? "Let's shoot" : 'Allow all')
                            : _page == 0
                            ? 'Show me around'
                            : 'Next',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  if (last && !asked)
                    TextButton(
                      onPressed: () => unawaited(_finish()),
                      child: const Text('Maybe later', style: TextStyle(color: _muted)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.title, this.body, this.icon, this.hero, this.child});

  final String title;
  final String? body;
  final IconData? icon;
  final Widget? hero;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          // Centred on the page, but free to scroll when the keyboard is up.
          constraints: BoxConstraints(minHeight: box.maxHeight * 0.85),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              hero ?? Icon(icon, size: 56, color: _OnboardingScreenState._accent),
              const SizedBox(height: 26),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _OnboardingScreenState._ink,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              if (body != null) ...[
                const SizedBox(height: 14),
                Text(
                  body!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _OnboardingScreenState._muted, fontSize: 15, height: 1.45),
                ),
              ],
              ?child,
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _Gestures extends StatelessWidget {
  const _Gestures();

  @override
  Widget build(BuildContext context) {
    const rows = [
      (Icons.swap_horiz, 'Swipe the camera sideways', 'Toss it aside for the other one: film or digital.'),
      (Icons.swipe_up_outlined, 'Swipe up', 'Pick a film or a camera.'),
      (Icons.east, 'Swipe right on film', 'Your corkboard slides in.'),
      (Icons.west, 'Swipe left on digital', 'The 1998 computer boots up. Brace yourself.'),
      (Icons.volume_up_outlined, 'Volume buttons', 'Take the picture, like a real shutter.'),
      (Icons.touch_app_outlined, 'Tap a print in the darkroom', 'Watch it come up in the tray.'),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        children: [
          for (final (icon, what, does) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1B20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: _OnboardingScreenState._ink, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          what,
                          style: const TextStyle(
                            color: _OnboardingScreenState._ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          does,
                          style: const TextStyle(color: _OnboardingScreenState._muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.note,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String note;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const accent = _OnboardingScreenState._accent;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.14) : const Color(0xFF1A1A20),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? accent : const Color(0xFF3A3632), width: 2),
        ),
        child: Column(
          children: [
            Icon(icon, size: 36, color: selected ? accent : _OnboardingScreenState._muted),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                color: _OnboardingScreenState._ink,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(note, style: const TextStyle(color: _OnboardingScreenState._muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.icon, required this.name, required this.why, this.granted});

  final IconData icon;
  final String name;
  final String why;

  /// null = not asked yet.
  final bool? granted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, color: _OnboardingScreenState._ink, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(color: _OnboardingScreenState._ink, fontWeight: FontWeight.w700),
                ),
                Text(why, style: const TextStyle(color: _OnboardingScreenState._muted, fontSize: 13)),
              ],
            ),
          ),
          if (granted != null)
            Icon(
              granted! ? Icons.check_circle : Icons.remove_circle_outline,
              color: granted! ? const Color(0xFF6BCB77) : _OnboardingScreenState._muted,
            ),
        ],
      ),
    );
  }
}

/// The app icon's rabbit: red, green and blue copies slightly apart, adding
/// up to white where they overlap.
class _SplitRabbit extends StatelessWidget {
  const _SplitRabbit({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final shift = size * 0.03;
    return CustomPaint(
      size: Size(size * DarkroomMark.aspect + shift * 2, size),
      painter: _SplitRabbitPainter(shift),
    );
  }
}

class _SplitRabbitPainter extends CustomPainter {
  const _SplitRabbitPainter(this.shift);

  final double shift;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds.inflate(4), Paint());
    for (final (c, dx) in [
      (const Color(0xFFFF0000), 0.0),
      (const Color(0xFF00FF00), shift),
      (const Color(0xFF0000FF), shift * 2),
    ]) {
      canvas.saveLayer(bounds.inflate(4), Paint()..blendMode = BlendMode.plus);
      canvas.translate(dx, 0);
      DarkroomMarkPainter(color: c).paint(canvas, Size(size.height * DarkroomMark.aspect, size.height));
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SplitRabbitPainter old) => old.shift != shift;
}
