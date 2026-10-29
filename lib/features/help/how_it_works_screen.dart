import 'package:flutter/material.dart';

import 'gesture_demo.dart';

/// A refresher for anyone who skipped the tour: the moves, drawn, and the
/// three things worth knowing. From Settings, Darkroom 98 Help and the
/// "New here?" hint.
class HowItWorksScreen extends StatelessWidget {
  const HowItWorksScreen({super.key});

  static const _bg = Color(0xFF0E0E12);
  static const _ink = Color(0xFFF3EEE6);
  static const _muted = Color(0xFF9C978F);
  static const _accent = Color(0xFFFF5A4F);

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const HowItWorksScreen());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('How it works', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: const [
            GestureGrid(ink: _ink, muted: _muted),
            SizedBox(height: 18),
            _Fact(
              icon: Icons.hourglass_bottom,
              title: 'Prints take about 5 minutes',
              body: 'They develop in the darkroom, then get pinned to the corkboard. Go make a coffee.',
            ),
            _Fact(
              icon: Icons.photo_library_outlined,
              title: 'Nothing reaches your gallery until you Save',
              body:
                  'Tap Save on a print, or Save all on the board. Digital shots go when you move them to C:.',
            ),
            _Fact(
              icon: Icons.wb_twilight_outlined,
              title: 'One roll a day',
              body:
                  'Plus one battery charge for the digital cameras, fresh every morning. Darkroom Pro lifts the limit.',
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title, body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF1C1B20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: HowItWorksScreen._accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: HowItWorksScreen._ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(color: HowItWorksScreen._muted, fontSize: 13, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
