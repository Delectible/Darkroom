import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';

import '../../core/device/haptics.dart';
import '../../core/providers.dart';
import '../camera/application/camera_session_controller.dart';
import '../camera/application/camera_ui_state.dart';

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
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: !last
                    ? TextButton(
                        key: const ValueKey('skip'),
                        onPressed: () => _pages.jumpToPage(_count - 1),
                        child: const Text('Skip', style: TextStyle(color: _muted)),
                      )
                    : TextButton(
                        key: const ValueKey('later'),
                        // Keeps its height once asked, so nothing below moves.
                        onPressed: asked ? null : () => unawaited(_finish()),
                        child: AnimatedOpacity(
                          opacity: asked ? 0 : 1,
                          duration: const Duration(milliseconds: 200),
                          child: const Text('Maybe later', style: TextStyle(color: _muted)),
                        ),
                      ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _Page(
                    hero: Image.asset(
                      'assets/artwork/rabbit_mark.png',
                      width: 140,
                      height: 140,
                      filterQuality: FilterQuality.medium,
                    ),
                    title: 'Hey, this is your Darkroom.',
                    body:
                        'Experience photography like it used to be. A little more physical, a lot more fun.',
                  ),
                  const _Page(
                    icon: Icons.camera_roll_outlined,
                    title: 'Shoot now, view later.',
                    body:
                        'Pick from a variety of film stocks and cameras. Things take time to develop. '
                        "Don't rush it, go make a coffee.\n\n"
                        "Once it's done, it gets pinned to the corkboard. Nothing goes to your phone's gallery "
                        'until you save it.',
                  ),
                  const _Page(
                    icon: Icons.save_outlined,
                    title: 'Digital: the year 2000 called.',
                    body:
                        'Feed your nostalgia with several retro-inspired digital cameras. Transfer your shots to '
                        'your desktop computer to view them, just like the good old days.\n\n'
                        "Play some games while you're there. Maybe you'll win some cool new looks for your camera.",
                  ),
                  const _Page(
                    icon: Icons.wb_twilight_outlined,
                    title: 'A roll a day.',
                    body:
                        "You get one roll of film of your choice every day. Once it's loaded, you're stuck with it "
                        'till the next day. The battery in your digital camera runs out too.\n\n'
                        'If you ever want more, Darkroom Pro gives you more flexibility: unlimited film and '
                        'battery, change whenever you want, and a few more cameras to choose from.\n\n'
                        'A reasonable price, once, forever. Never any ads, never any pressure.',
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
                          optional: true,
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

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.name,
    required this.why,
    this.granted,
    this.optional = false,
  });

  final IconData icon;
  final bool optional;
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
                Text.rich(
                  TextSpan(
                    text: name,
                    children: [
                      if (optional)
                        const TextSpan(
                          text: '  optional',
                          style: TextStyle(
                            color: _OnboardingScreenState._muted,
                            fontWeight: FontWeight.w400,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
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
