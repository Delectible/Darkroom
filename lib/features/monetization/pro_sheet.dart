import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device/upright.dart';
import '../../core/monetization/allowance.dart';
import '../../core/monetization/pro.dart';
import '../../core/theme/retro_theme.dart';
import '../camera/application/camera_ui_state.dart';
import '../cameras/domain/camera_catalog.dart';
import '../cameras/domain/camera_spec.dart';

/// The free version ran out (or another roll is loaded): says why, when it
/// comes back, and mentions Pro once, quietly.
Future<void> showLimitSheet(BuildContext context, Blocked why, CameraSpec spec) {
  final palette = RetroPalette.of(context);
  return showUprightSheet<void>(
    context,
    backgroundColor: palette.body,
    builder: (_, {required landscape}) => Theme(
      data: palette.toTheme(),
      child: _LimitSheet(why: why, spec: spec),
    ),
  );
}

/// What the user chose when asked to load today's roll.
enum LoadChoice { load, pickOther }

/// Free version, first shot of the day on film: today's roll is [spec] once
/// it's loaded, until it's finished. Shows the box and what the roll holds.
Future<LoadChoice?> showLoadRollSheet(BuildContext context, CameraSpec spec) {
  final palette = RetroPalette.of(context);
  return showUprightSheet<LoadChoice>(
    context,
    backgroundColor: palette.body,
    builder: (_, {required landscape}) => Theme(
      data: palette.toTheme(),
      child: _LoadRollSheet(spec: spec),
    ),
  );
}

class _LoadRollSheet extends StatelessWidget {
  const _LoadRollSheet({required this.spec});

  final CameraSpec spec;

  @override
  Widget build(BuildContext context) {
    final p = RetroPalette.of(context);
    final size = Allowance.sizeOf(spec);
    final amount = spec.recordsVideo
        ? (size % 60 == 0 ? '${size ~/ 60} minute${size == 60 ? '' : 's'} of film' : '$size seconds of film')
        : '$size shots';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 150,
              child: Image.asset(
                spec.artwork,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Load ${spec.name}?',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.text, fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              amount,
              style: TextStyle(color: p.accent, fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              "This is today's roll. Once it's in, it stays in the camera until it's finished. "
              'A fresh roll of anything arrives tomorrow morning.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textMuted, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: p.text,
                      side: BorderSide(color: p.textMuted),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.of(context).pop(LoadChoice.pickOther),
                    child: const Text('Pick another film'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: p.accent,
                      foregroundColor: const Color(0xFF1A1714),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.of(context).pop(LoadChoice.load),
                    child: const Text('Load it'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Darkroom Pro: what it adds, the price, buy / restore.
Future<void> showProSheet(BuildContext context) {
  final palette = RetroPalette.of(context);
  return showUprightSheet<void>(
    context,
    backgroundColor: palette.body,
    builder: (_, {required landscape}) => Theme(data: palette.toTheme(), child: const _ProSheet()),
  );
}

class _LimitSheet extends ConsumerWidget {
  const _LimitSheet({required this.why, required this.spec});

  final Blocked why;
  final CameraSpec spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RetroPalette.of(context);
    final today = ref.watch(allowanceProvider).at(AllowanceNotifier.now());
    final loaded = today.stock == null ? null : CameraCatalog.byId(today.stock!);
    final (title, body) = switch (why) {
      Blocked.outOfFilm => (
        'Out of film',
        "That's today's roll finished. A fresh one arrives tomorrow morning.",
      ),
      Blocked.otherRoll => (
        '${loaded?.name ?? 'Another film'} is loaded',
        "Today's roll is ${loaded?.name ?? 'another film'}, with ${loaded == null ? 'some' : today.left(loaded)} "
            'shots left. A roll stays in the camera until it is finished.',
      ),
      Blocked.flatBattery => (
        'Battery flat',
        'The digital cameras have used today\'s charge. It will be full again tomorrow morning.',
      ),
      Blocked.unloaded => ('', ''), // asked by showLoadRollSheet instead
    };
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(body, style: TextStyle(color: p.text, fontSize: 15, height: 1.35)),
            const SizedBox(height: 14),
            Text(
              'Darkroom Pro removes the daily limits, for a one-time ${ProStore.fallbackPrice}.',
              style: TextStyle(color: p.textMuted, fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    unawaited(showProSheet(context));
                  },
                  child: Text('About Pro', style: TextStyle(color: p.textMuted)),
                ),
                const Spacer(),
                if (why == Blocked.otherRoll && loaded != null)
                  TextButton(
                    onPressed: () {
                      unawaited(ref.read(selectedCameraProvider.notifier).select(AppMode.film, loaded.id));
                      Navigator.of(context).pop();
                    },
                    child: Text('Back to ${loaded.name}', style: TextStyle(color: p.accent)),
                  )
                else
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'OK',
                      style: TextStyle(color: p.accent, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProSheet extends ConsumerStatefulWidget {
  const _ProSheet();

  @override
  ConsumerState<_ProSheet> createState() => _ProSheetState();
}

class _ProSheetState extends ConsumerState<_ProSheet> {
  String _price = ProStore.fallbackPrice;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(
      ref.read(proStoreProvider).price().then((v) {
        if (mounted) setState(() => _price = v);
      }),
    );
  }

  Future<void> _run(Future<StoreResult> Function() action) async {
    setState(() => _busy = true);
    final r = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    final msg = switch (r) {
      StoreResult.bought => 'Thank you! Darkroom Pro is unlocked.',
      StoreResult.restored => 'Welcome back. Darkroom Pro is unlocked.',
      StoreResult.nothingToRestore => 'No earlier purchase was found on this account.',
      StoreResult.cancelled => null,
      StoreResult.pending => 'The purchase is pending. Pro unlocks as soon as it goes through.',
      StoreResult.unavailable => "The store isn't available right now. Try again later.",
      StoreResult.failed => 'Something went wrong with the store. Nothing was charged.',
    };
    if (msg != null) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));
    if (r == StoreResult.bought || r == StoreResult.restored) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = RetroPalette.of(context);
    final pro = ref.watch(proProvider);
    final store = ref.read(proStoreProvider);
    Widget line(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '·  ',
            style: TextStyle(color: p.accent, fontSize: 15, fontWeight: FontWeight.w900),
          ),
          Expanded(
            child: Text(text, style: TextStyle(color: p.text, fontSize: 15, height: 1.3)),
          ),
        ],
      ),
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Darkroom Pro',
              style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'The free version gives you one roll of film and one battery charge for the digital cameras '
              'each day. Pro takes the limits away:',
              style: TextStyle(color: p.textMuted, fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 12),
            line('Unlimited film: a new roll whenever you want one'),
            line('Unlimited battery for the digital cameras'),
            line('Change film in the middle of a roll'),
            line('Full-length Super 8 cartridges'),
            const SizedBox(height: 10),
            Text('One payment. No subscription, no ads.', style: TextStyle(color: p.textMuted, fontSize: 13)),
            const SizedBox(height: 14),
            if (pro)
              Text(
                'Pro is unlocked. Thank you!',
                style: TextStyle(color: p.accent, fontSize: 15, fontWeight: FontWeight.w700),
              )
            else
              Row(
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => _run(store.restore),
                    child: Text('Restore purchase', style: TextStyle(color: p.textMuted)),
                  ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: p.accent),
                    onPressed: _busy ? null : () => _run(store.buy),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text('Get Pro · $_price'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
