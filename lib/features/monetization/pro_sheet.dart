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
      child: _fits(landscape, _LimitSheet(why: why, spec: spec)),
    ),
  );
}

/// Held sideways the panel is short: it scrolls rather than cut off its
/// buttons.
Widget _fits(bool landscape, Widget sheet) => landscape ? SingleChildScrollView(child: sheet) : sheet;

/// What the user chose when asked to load today's roll.
enum LoadChoice { load, pickOther }

/// What to do with yesterday's unfinished roll.
enum CarryChoice { keep, rewind }

String _amount(CameraSpec spec, int size) => spec.recordsVideo
    ? (size % 60 == 0 ? '${size ~/ 60} minute${size == 60 ? '' : 's'} of film' : '$size seconds of film')
    : '$size shot${size == 1 ? '' : 's'}';

/// Free version, first shot of the day on film: today's roll is [spec] once
/// it's loaded, until it's finished. Shows the box and what the roll holds.
Future<LoadChoice?> showLoadRollSheet(BuildContext context, CameraSpec spec) => _showRollSheet(
  context,
  spec: spec,
  title: 'Load ${spec.name}?',
  amount: _amount(spec, Allowance.sizeOf(spec)),
  body:
      "This is today's roll. Once it's in, it stays in the camera until it's finished, overnight too. "
      'A new roll of anything comes each morning.',
  other: ('Pick another film', LoadChoice.pickOther),
  main: ('Load it', LoadChoice.load),
);

/// Free version, first film shot of a new day with yesterday's roll still
/// in: keep shooting it, or rewind and swap (the rest is lost).
Future<CarryChoice?> showCarriedRollSheet(BuildContext context, CameraSpec loaded, int left) =>
    _showRollSheet(
      context,
      spec: loaded,
      title: "Yesterday's roll is still in",
      amount: '${loaded.name} · ${_amount(loaded, left)} left',
      body:
          'Keep shooting it, or rewind it and load a fresh roll of anything. '
          'Rewinding throws away the rest of this roll. Finishing it brings today\'s fresh roll.',
      other: ('Rewind & swap', CarryChoice.rewind),
      main: ('Keep shooting', CarryChoice.keep),
    );

Future<T?> _showRollSheet<T>(
  BuildContext context, {
  required CameraSpec spec,
  required String title,
  required String amount,
  required String body,
  required (String, T) other,
  required (String, T) main,
}) {
  final palette = RetroPalette.of(context);
  return showUprightSheet<T>(
    context,
    backgroundColor: palette.body,
    builder: (_, {required landscape}) => Theme(
      data: palette.toTheme(),
      child: _fits(
        landscape,
        _RollSheet<T>(spec: spec, title: title, amount: amount, body: body, other: other, main: main),
      ),
    ),
  );
}

/// The film box, a title, what the roll holds, why, and two choices.
class _RollSheet<T> extends StatelessWidget {
  const _RollSheet({
    required this.spec,
    required this.title,
    required this.amount,
    required this.body,
    required this.other,
    required this.main,
  });

  final CameraSpec spec;
  final String title;
  final String amount;
  final String body;
  final (String, T) other;
  final (String, T) main;

  @override
  Widget build(BuildContext context) {
    final p = RetroPalette.of(context);
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
              title,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.text, fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              amount,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.accent, fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              body,
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
                    onPressed: () => Navigator.of(context).pop(other.$2),
                    child: Text(other.$1),
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
                    onPressed: () => Navigator.of(context).pop(main.$2),
                    child: Text(main.$1),
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
    builder: (_, {required landscape}) =>
        Theme(data: palette.toTheme(), child: _fits(landscape, const _ProSheet())),
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
      Blocked.proOnly => (
        '${spec.name} is part of Pro',
        'Darkroom Pro adds ${spec.isFilm ? 'this film' : 'this camera'} and the other Pro '
            '${spec.isFilm ? 'films' : 'cameras'}. Everything you have now stays free.',
      ),
      // Asked by showLoadRollSheet / showCarriedRollSheet instead.
      Blocked.unloaded || Blocked.carriedOver => ('', ''),
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
            FutureBuilder(
              future: ref.read(proStoreProvider).price(),
              builder: (_, price) => Text(
                'Darkroom Pro removes the daily limits and adds 9 more films and cameras, '
                'for a one-time ${price.data ?? ProStore.fallbackPrice}.',
                style: TextStyle(color: p.textMuted, fontSize: 13, height: 1.35),
              ),
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
                if (why == Blocked.otherRoll && today.carried)
                  TextButton(
                    onPressed: () {
                      ref.read(allowanceProvider.notifier).rewind();
                      Navigator.of(context).pop();
                    },
                    child: Text('Rewind & swap', style: TextStyle(color: p.textMuted)),
                  ),
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
              'each day. Pro takes the limits away and opens the whole cabinet:',
              style: TextStyle(color: p.textMuted, fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 12),
            line(
              '5 more films: Golden 200, Night 800T, Chrome 50, a single-use camera and Epic 70 movie film',
            ),
            line('4 more digital cameras: a 2005 webcam, a starter DSLR, a toy pixel cam and MiniDV'),
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
                    child: Text('Restore Purchases', style: TextStyle(color: p.textMuted)),
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
