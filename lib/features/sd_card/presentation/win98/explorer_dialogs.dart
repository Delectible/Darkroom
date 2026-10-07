import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/audio/sfx.dart';

import '../../../../core/app_info.dart';
import '../../../camera/application/camera_log.dart';
import '../../../cameras/domain/camera_catalog.dart';
import '../../../settings/application/settings_controllers.dart';
import '../../../viewer/presentation/media_actions.dart';
import '../../application/sd_card_controller.dart';
import 'pixel_icons.dart';
import 'win98_widgets.dart';

Widget win98Icon(Win98MessageIcon i) => PixelIconView(switch (i) {
  Win98MessageIcon.info => PixelIcon.info,
  Win98MessageIcon.warning => PixelIcon.warning,
  Win98MessageIcon.error => PixelIcon.error,
  Win98MessageIcon.question => PixelIcon.question,
}, size: 32);

Future<int?> win98Box(
  BuildContext context,
  String title,
  String msg, {
  Win98MessageIcon icon = Win98MessageIcon.info,
  List<String> buttons = const ['OK'],
}) => showWin98MessageBox(
  context,
  title: title,
  message: msg,
  icon: icon,
  buttons: buttons,
  iconBuilder: win98Icon,
);

// -----------------------------------------------------------------------------
// Copying...
// -----------------------------------------------------------------------------

/// "Copying..." with the flying-paper animation.
class CopyingDialog extends ConsumerStatefulWidget {
  const CopyingDialog({super.key, this.fromFloppy = false});

  /// Camcorder clips come off the floppies in A: instead of the card.
  final bool fromFloppy;

  @override
  ConsumerState<CopyingDialog> createState() => _CopyingDialogState();
}

class _CopyingDialogState extends ConsumerState<CopyingDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _fly = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _fly.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(sdTransferProvider);
    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: math.min(330, MediaQuery.sizeOf(context).width - 24),
          child: Win98Bevel(
            style: BevelStyle.window,
            padding: const EdgeInsets.all(3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Win98TitleBar(title: 'Moving...'),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 48,
                        child: AnimatedBuilder(
                          animation: _fly,
                          builder: (context, _) => LayoutBuilder(
                            builder: (context, box) {
                              final x = 36 + (box.maxWidth - 108) * _fly.value;
                              final y = 14 - math.sin(_fly.value * math.pi) * 14;
                              return Stack(
                                children: [
                                  Positioned(
                                    left: 0,
                                    top: 8,
                                    child: PixelIconView(
                                      widget.fromFloppy ? PixelIcon.floppy : PixelIcon.removableDrive,
                                      size: 32,
                                    ),
                                  ),
                                  const Positioned(
                                    right: 0,
                                    top: 8,
                                    child: PixelIconView(PixelIcon.folder, size: 32),
                                  ),
                                  Positioned(
                                    left: x,
                                    top: y,
                                    child: const PixelIconView(PixelIcon.imageFile, size: 24),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(t?.current ?? 'Preparing…', style: W98.text),
                      Text(
                        "From '${widget.fromFloppy ? '3½ Floppy (A:)' : 'SD Card (E:)'}' to 'C:\\My Documents\\Darkroom'",
                        style: W98.text,
                      ),
                      const SizedBox(height: 8),
                      Win98ProgressBar(value: t?.progress ?? 0),
                      const SizedBox(height: 4),
                      Text('${t?.done ?? 0} of ${t?.total ?? 0} file(s)', style: W98.text),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Win98Button(
                          minWidth: 76,
                          onPressed: () => ref.read(sdTransferProvider.notifier).cancel(),
                          child: const Text('Cancel'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Properties (pie chart)
// -----------------------------------------------------------------------------

Future<void> showDriveProperties(
  BuildContext context, {
  required String label,
  required int used,
  required int capacity,
}) {
  return showWin98Window<void>(
    context,
    title: '$label Properties',
    icon: const PixelIconView(PixelIcon.removableDrive),
    builder: (context) => Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const PixelIconView(PixelIcon.removableDrive, size: 32),
              const SizedBox(width: 10),
              Text(label.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9 ]'), ''), style: W98.text),
            ],
          ),
          const Divider(color: W98.shadow, height: 16),
          Text('Type:          ${capacity == 0 ? 'Local Disk' : 'Removable Disk'}'),
          const Text('File system:  FAT'),
          const Divider(color: W98.shadow, height: 16),
          _legend(const Color(0xFF0000FF), 'Used space:', used),
          _legend(const Color(0xFFFF00FF), 'Free space:', math.max(0, capacity - used)),
          const Divider(color: W98.shadow, height: 16),
          Text('Capacity:        ${capacity == 0 ? formatBytes(used) : formatBytes(capacity)}'),
          const SizedBox(height: 10),
          SizedBox(height: 90, child: CustomPaint(painter: _PiePainter(capacity == 0 ? 1 : used / capacity))),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: Win98Button(
              minWidth: 76,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _legend(Color c, String label, int bytes) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 2),
  child: Row(
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: c, border: Border.all()),
      ),
      const SizedBox(width: 6),
      SizedBox(width: 90, child: Text(label)),
      Flexible(child: Text('${_commas(bytes)} bytes', maxLines: 1, overflow: TextOverflow.ellipsis)),
    ],
  ),
);

String _commas(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// The 3D disk-usage pie from the 9x drive properties sheet.
class _PiePainter extends CustomPainter {
  _PiePainter(this.used);

  final double used;

  @override
  void paint(Canvas canvas, Size size) {
    final w = math.min(size.width, 180.0), h = size.height - 16;
    final rect = Rect.fromCenter(center: Offset(size.width / 2, h / 2), width: w, height: h * 0.8);
    const depth = 14.0;
    final usedAng = used.clamp(0.0, 1.0) * math.pi * 2;
    // sides
    for (var d = depth; d > 0; d -= 1) {
      final r = rect.shift(Offset(0, d));
      canvas.drawArc(r, 0, math.pi, true, Paint()..color = const Color(0xFF800080));
      if (usedAng > 0) {
        canvas.drawArc(r, -math.pi / 2, usedAng, true, Paint()..color = const Color(0xFF000080));
      }
    }
    canvas.drawOval(rect, Paint()..color = const Color(0xFFFF00FF));
    if (usedAng > 0) {
      canvas.drawArc(rect, -math.pi / 2, usedAng, true, Paint()..color = const Color(0xFF0000FF));
    }
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.black,
    );
  }

  @override
  bool shouldRepaint(_PiePainter old) => old.used != used;
}

// -----------------------------------------------------------------------------
// View > Options (the same settings as the camera's settings sheet)
// -----------------------------------------------------------------------------

Future<void> showExplorerOptions(BuildContext context) => showWin98Window<void>(
  context,
  title: 'Options',
  width: 340,
  icon: const PixelIconView(PixelIcon.views),
  builder: (context) => const _OptionsBody(),
);

class _OptionsBody extends ConsumerStatefulWidget {
  const _OptionsBody();

  @override
  ConsumerState<_OptionsBody> createState() => _OptionsBodyState();
}

class _OptionsBodyState extends ConsumerState<_OptionsBody> {
  int _tab = 0;
  String _camera = CameraCatalog.digital.first.id;

  @override
  Widget build(BuildContext context) {
    final global = ref.watch(globalSettingsProvider);
    final g = ref.read(globalSettingsProvider.notifier);
    final cams = ref.watch(cameraSettingsProvider);
    final cn = ref.read(cameraSettingsProvider.notifier);
    final spec = CameraCatalog.byId(_camera);
    final local = cams[_camera];

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Win98TabStrip(
            tabs: const [Win98Tab('Cameras'), Win98Tab('General')],
            selected: _tab,
            onSelect: (i) => setState(() => _tab = i),
          ),
          Win98Bevel(
            style: BevelStyle.window,
            padding: const EdgeInsets.all(8),
            child: _tab == 0
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Win98GroupBox(
                        label: 'Camera',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final s in CameraCatalog.digital)
                              Win98Radio(
                                selected: s.id == _camera,
                                label: s.name,
                                onTap: () => setState(() => _camera = s.id),
                              ),
                          ],
                        ),
                      ),
                      Win98GroupBox(
                        label: 'Picture shape',
                        child: Wrap(
                          spacing: 12,
                          children: [
                            for (final a in spec.aspects)
                              Win98Radio(
                                selected: (local?.aspect ?? spec.defaultAspect) == a,
                                label: a.label,
                                onTap: spec.aspectLocked ? null : () => unawaited(cn.setAspect(spec.id, a)),
                              ),
                          ],
                        ),
                      ),
                      if (spec.supportsTimestamp)
                        Win98Checkbox(
                          value: local?.timestamp ?? true,
                          label: 'Print the date on pictures',
                          onChanged: (v) => unawaited(cn.setTimestamp(spec.id, v)),
                        ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Win98Checkbox(
                        value: global.notificationsEnabled,
                        label: 'Notify me when film has developed',
                        onChanged: (v) => unawaited(g.setNotificationsEnabled(v)),
                      ),
                      Win98Checkbox(
                        value: global.darkroomEnabled,
                        label: 'Develop film in the darkroom (5 min)',
                        onChanged: (v) => unawaited(g.setDarkroomEnabled(v)),
                      ),
                      Win98Checkbox(
                        value: global.saveOriginalCopy,
                        label: 'Also save an unfiltered original',
                        onChanged: (v) => unawaited(g.setSaveOriginalCopy(v)),
                      ),
                      Win98Checkbox(
                        value: global.highResFilm,
                        label: 'High-resolution film',
                        onChanged: (v) => unawaited(g.setHighResFilm(v)),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Win98Button(
                minWidth: 76,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Help
// -----------------------------------------------------------------------------

Future<void> showAboutDarkroom(BuildContext context) => showWin98Window<void>(
  context,
  title: 'About ${AppInfo.name}',
  width: 340,
  icon: const PixelIconView(PixelIcon.rabbit),
  builder: (context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const PixelIconView(PixelIcon.rabbit, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${AppInfo.name} 98',
                    style: W98.text.copyWith(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const Text('Version ${AppInfo.version} (Build ${AppInfo.build})'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text('This product is licensed to:\n    You'),
        const Divider(color: W98.shadow, height: 18),
        Text('Revision history', style: W98.text.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 170),
          child: Win98Bevel(
            style: BevelStyle.sunken,
            color: Colors.white,
            padding: const EdgeInsets.all(6),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (v, notes) in AppInfo.revisions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'v$v  ',
                              style: W98.text.copyWith(fontWeight: FontWeight.w700),
                            ),
                            TextSpan(text: notes),
                          ],
                        ),
                        style: W98.text,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Physical memory available to Darkroom:  65,536 KB'),
        const Text('System resources:  98% free'),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: Win98Button(
            minWidth: 76,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ),
      ],
    ),
  ),
);

/// The camera session's recent events, for diagnosing a viewfinder that
/// drops out (screenshot this and send it).
Future<void> showCameraLog(BuildContext context) {
  final lines = CameraLog.lines;
  return showWin98Window<void>(
    context,
    title: 'Camera Log - Notepad',
    width: 340,
    icon: const PixelIconView(PixelIcon.info),
    builder: (context) => Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: Win98Bevel(
              style: BevelStyle.sunken,
              color: Colors.white,
              padding: const EdgeInsets.all(6),
              child: SingleChildScrollView(
                reverse: true,
                child: Text(
                  lines.isEmpty ? '(nothing yet)' : lines.join('\n'),
                  style: W98.text.copyWith(fontSize: 11),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Win98Button(
              minWidth: 76,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ),
        ],
      ),
    ),
  );
}

const _tips = [
  'Pictures on the SD card are locked. Move them to Local Disk (C:) to open them — they also land in your phone\'s Photos app.',
  'Tap a selected file again to open it. Hold a file on C: to send it to a friend.',
  'The 1999 Floppy Cam fits about 15 pictures on a disk. Luckily, this disk never fills up.',
  'Hold your phone sideways and Darkroom saves the picture the right way up.',
  'The Transfer button moves everything off the card in one go.',
  'Arrange by Size to find your longest home videos.',
  'Feeling nostalgic? Try Tools > Defragment.',
  'There is no Minesweeper. We checked.',
  'Start > Run..., type RABBIT, press OK. Nothing bad will happen.',
  'Wondering what happens to your film? Run DEVELOP.BAT.',
  'PING the corkboard from Start > Run... to see how long your prints take.',
  'Every program on this computer is listed in README.TXT. Try Start > Run....',
  'All work and no play? Start > Run... SOL, BRICKS or PINBALL.',
  'Space Rabbit Pinball: light up R-A-B-B-I-T for a bonus.',
];

Future<void> showTipOfTheDay(BuildContext context) {
  var i = math.Random().nextInt(_tips.length);
  return showWin98Window<void>(
    context,
    title: 'Tip of the Day',
    width: 330,
    icon: const PixelIconView(PixelIcon.info),
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Win98Bevel(
              style: BevelStyle.sunken,
              color: const Color(0xFFFFFFE1),
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PixelIconView(PixelIcon.info, size: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Did you know...',
                          style: W98.text.copyWith(fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        Text(_tips[i]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Win98Button(
                  minWidth: 76,
                  onPressed: () => setState(() => i = (i + 1) % _tips.length),
                  child: const Text('Next Tip'),
                ),
                const SizedBox(width: 6),
                Win98Button(
                  minWidth: 76,
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

// -----------------------------------------------------------------------------
// Tools > Defragment (purely for fun)
// -----------------------------------------------------------------------------

Future<void> showDefragmenter(BuildContext context, {required int files}) => showWin98Window<void>(
  context,
  title: 'Defragmenting Drive E:',
  width: 340,
  icon: const PixelIconView(PixelIcon.removableDrive),
  builder: (context) => _Defrag(files: files),
);

class _Defrag extends StatefulWidget {
  const _Defrag({required this.files});

  final int files;

  @override
  State<_Defrag> createState() => _DefragState();
}

class _DefragState extends State<_Defrag> {
  static const _cols = 24, _rows = 10;
  final _rnd = math.Random();
  late final List<int> _cells; // 0 free, 1 fragmented, 2 done, 3 reading, 4 writing
  Timer? _timer;
  int _done = 0;

  @override
  void initState() {
    super.initState();
    final used = (_cols * _rows * (0.35 + math.min(0.4, widget.files / 60))).round();
    _cells = List<int>.generate(_cols * _rows, (i) => 0);
    for (var k = 0; k < used; k++) {
      _cells[_rnd.nextInt(_cells.length)] = 1;
    }
    _timer = Timer.periodic(const Duration(milliseconds: 90), (_) => _step());
  }

  void _step() {
    final next = _cells.indexWhere((c) => c == 1);
    setState(() {
      for (var i = 0; i < _cells.length; i++) {
        if (_cells[i] >= 3) _cells[i] = _cells[i] == 3 ? 0 : 2;
      }
      if (next < 0) {
        _timer?.cancel();
        _done = _cells.length;
        return;
      }
      _cells[next] = 3;
      final slot = _cells.indexWhere((c) => c == 0 || c == 1);
      if (slot >= 0 && slot <= next) _cells[slot] = 4;
      _done = _cells.where((c) => c == 2).length;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final finished = _timer?.isActive != true;
    final total = math.max(1, _cells.where((c) => c != 0).length);
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: _cols / _rows,
            child: Win98Bevel(
              style: BevelStyle.sunken,
              color: Colors.white,
              padding: const EdgeInsets.all(2),
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: _cols),
                itemCount: _cells.length,
                itemBuilder: (context, i) => Container(
                  margin: const EdgeInsets.all(0.5),
                  color: switch (_cells[i]) {
                    0 => Colors.white,
                    1 => const Color(0xFF00A0A0),
                    2 => const Color(0xFF0000C0),
                    3 => const Color(0xFF00C000),
                    _ => const Color(0xFFC00000),
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(finished ? 'Defragmentation of drive E: is complete.' : 'Reading drive information...'),
          const SizedBox(height: 6),
          Win98ProgressBar(value: finished ? 1 : _done / total),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Win98Button(
              minWidth: 76,
              onPressed: () => Navigator.of(context).pop(),
              child: Text(finished ? 'OK' : 'Stop'),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Start menu, Run, Shut Down, and the blue screen
// -----------------------------------------------------------------------------

enum StartAction { camera, documents, options, help, run, shutDown }

Future<StartAction?> showStartMenu(BuildContext context) {
  final bottom = MediaQuery.paddingOf(context).bottom + 32;
  return showGeneralDialog<StartAction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'start',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    transitionBuilder: (context, a, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(a),
      child: child,
    ),
    pageBuilder: (context, _, _) => Win98Scale(
      child: Stack(
        children: [
          Positioned(
            left: 6,
            bottom: bottom,
            child: Material(
              type: MaterialType.transparency,
              child: Win98Bevel(
                style: BevelStyle.window,
                padding: const EdgeInsets.all(2),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 24,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [W98.navy, W98.titleEnd],
                          ),
                        ),
                        padding: const EdgeInsets.only(top: 6, bottom: 8),
                        child: Column(
                          children: [
                            const PixelIconView(PixelIcon.rabbit),
                            const Spacer(),
                            RotatedBox(
                              quarterTurns: 3,
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'Darkroom',
                                      style: W98.text.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                      ),
                                    ),
                                    TextSpan(
                                      text: '98',
                                      style: W98.text.copyWith(color: Colors.white70, fontSize: 16),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 190,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _startItem(context, PixelIcon.camera, 'Camera', StartAction.camera),
                            _startItem(context, PixelIcon.folder, 'Documents', StartAction.documents),
                            _startItem(context, PixelIcon.views, 'Settings', StartAction.options),
                            _startItem(context, PixelIcon.question, 'Help', StartAction.help),
                            _startItem(context, PixelIcon.upFolder, 'Run...', StartAction.run),
                            const Divider(height: 6, color: W98.shadow),
                            _startItem(context, PixelIcon.computer, 'Shut Down...', StartAction.shutDown),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _startItem(BuildContext context, PixelIcon icon, String label, StartAction action) => InkWell(
  onTap: () {
    Sfx.w98Click.play();
    Navigator.of(context).pop(action);
  },
  hoverColor: W98.navy,
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    child: Row(
      children: [
        PixelIconView(icon, size: 24),
        const SizedBox(width: 10),
        Text(label, style: W98.text.copyWith(fontSize: 13)),
      ],
    ),
  ),
);

/// Start > Run. A few commands do something.
Future<String?> showRunDialog(BuildContext context) {
  final ctrl = TextEditingController();
  return showWin98Window<String>(
    context,
    title: 'Run',
    width: 330,
    builder: (context) => Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              PixelIconView(PixelIcon.upFolder, size: 32),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Type the name of a program, folder, or document, and Darkroom will open it for you.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('Open:  '),
              Expanded(
                child: Win98Bevel(
                  style: BevelStyle.sunken,
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: TextField(
                    controller: ctrl,
                    autofocus: true,
                    style: W98.text,
                    cursorColor: Colors.black,
                    decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                    onSubmitted: (v) => Navigator.of(context).pop(v),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Win98Button(
                minWidth: 76,
                onPressed: () => Navigator.of(context).pop(ctrl.text),
                child: const Text('OK'),
              ),
              const SizedBox(width: 6),
              Win98Button(
                minWidth: 76,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// The famous blue screen (hold the taskbar clock).
Future<void> showBlueScreen(BuildContext context) {
  unawaited(HapticFeedback.heavyImpact());
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      pageBuilder: (context, _, _) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: ColoredBox(
          color: const Color(0xFF0000AA),
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: DefaultTextStyle(
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.35,
                    decoration: TextDecoration.none,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        color: const Color(0xFFAAAAAA),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: const Text(
                          'Darkroom',
                          style: TextStyle(color: Color(0xFF0000AA), fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'A fatal exception 0E has occurred at 0028:C0FFEE98 in VXD SHUTTER(01) + 00001998. '
                        'The current roll will be terminated.\n\n'
                        '*  Tap anywhere to terminate the current application.\n'
                        '*  Don\'t worry, your photos are safe. This was a joke.',
                      ),
                      const SizedBox(height: 16),
                      const Text('Tap anywhere to continue _'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

// -----------------------------------------------------------------------------
// Floppy spanning (camcorder tapes live on 3½" disks in A:)
// -----------------------------------------------------------------------------

/// Copies a tape capture off a stack of floppies: reads a disk, then asks
/// for the next one ("Please insert disk 2 of 5 into drive A:"). After a few
/// swaps the program takes pity and swaps the rest itself. Returns false if
/// the user cancels.
Future<bool> showFloppySpan(BuildContext context, {required int disks, required String label}) async {
  final r = await showWin98Window<bool>(
    context,
    title: 'Copying from 3½ Floppy (A:)',
    icon: const PixelIconView(PixelIcon.floppy),
    builder: (context) => _FloppySpan(disks: disks, label: label),
  );
  return r ?? false;
}

class _FloppySpan extends StatefulWidget {
  const _FloppySpan({required this.disks, required this.label});

  final int disks;
  final String label;

  @override
  State<_FloppySpan> createState() => _FloppySpanState();
}

enum _SpanPhase { reading, insert, autoSwap }

class _FloppySpanState extends State<_FloppySpan> with SingleTickerProviderStateMixin {
  /// Prompts before "Windows" swaps the remaining disks itself.
  static const _manualSwaps = 3;

  late final AnimationController _read = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..addStatusListener(_onRead);
  int _disk = 1;
  int _swaps = 0;
  _SpanPhase _phase = _SpanPhase.reading;
  bool _auto = false;
  Timer? _grind;

  @override
  void initState() {
    super.initState();
    _startReading();
  }

  @override
  void dispose() {
    _grind?.cancel();
    _read.dispose();
    super.dispose();
  }

  void _startReading() {
    setState(() => _phase = _SpanPhase.reading);
    _read.duration = Duration(milliseconds: _auto ? 350 : 1100);
    _read.forward(from: 0);
    // The drive's head chatter, felt rather than heard.
    _grind?.cancel();
    _grind = Timer.periodic(
      const Duration(milliseconds: 140),
      (_) => unawaited(HapticFeedback.selectionClick()),
    );
  }

  void _onRead(AnimationStatus s) {
    if (s != AnimationStatus.completed || !mounted) return;
    _grind?.cancel();
    if (_disk >= widget.disks) {
      Navigator.of(context).pop(true);
      return;
    }
    _disk++;
    if (_auto) return _startReading();
    if (_swaps >= _manualSwaps && widget.disks - _disk >= 1) {
      setState(() => _phase = _SpanPhase.autoSwap);
      return;
    }
    unawaited(HapticFeedback.mediumImpact()); // disk ejects
    setState(() => _phase = _SpanPhase.insert);
  }

  void _inserted() {
    _swaps++;
    unawaited(HapticFeedback.heavyImpact()); // clunk
    _startReading();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.disks;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: AnimatedBuilder(
        animation: _read,
        builder: (context, _) {
          final progress = ((_disk - 1) + (_phase == _SpanPhase.reading ? _read.value : 0)) / n;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const PixelIconView(PixelIcon.floppy, size: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(switch (_phase) {
                      _SpanPhase.reading => 'Reading ${widget.label}\nDisk $_disk of $n…',
                      _SpanPhase.insert =>
                        'Please insert disk $_disk of $n into drive A:\n\n'
                            'Label: TAPE01 · DISK $_disk',
                      _SpanPhase.autoSwap =>
                        "You've got the hang of this.\n\n"
                            'Darkroom will swap the remaining ${n - _disk + 1} disk(s) for you.',
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Win98ProgressBar(value: progress),
              const SizedBox(height: 4),
              Text(
                '${(progress * 100).round()}% · ${formatBytes((progress * n * floppyCapacityBytes).round())} read',
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_phase == _SpanPhase.insert)
                    Win98Button(minWidth: 72, onPressed: _inserted, child: const Text('OK')),
                  if (_phase == _SpanPhase.autoSwap)
                    Win98Button(
                      minWidth: 72,
                      onPressed: () {
                        _auto = true;
                        _startReading();
                      },
                      child: const Text('Thanks!'),
                    ),
                  const SizedBox(width: 6),
                  Win98Button(
                    minWidth: 72,
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
