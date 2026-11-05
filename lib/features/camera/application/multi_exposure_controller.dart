import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import 'camera_ui_state.dart';

/// Multiple exposure (35 mm stills): armed on the viewfinder's ME chip, the
/// next shot is held as the first exposure (no frame used); the one after
/// lands on it and the two develop as one print. Disarming, or changing
/// camera, lets the held exposure go.
@immutable
class MultiExposureState {
  const MultiExposureState({this.armed = false, this.first});

  final bool armed;

  /// The first exposure, waiting for the second.
  final String? first;

  bool get holding => first != null;
}

final multiExposureProvider = NotifierProvider<MultiExposureController, MultiExposureState>(
  MultiExposureController.new,
);

class MultiExposureController extends Notifier<MultiExposureState> {
  @override
  MultiExposureState build() {
    ref.listen(activeSpecProvider, (_, _) => cancel());
    return const MultiExposureState();
  }

  /// Where the first exposure waits (outside the capture cache, which is
  /// swept of files no row refers to).
  String get _firstPath => '${ref.read(appPathsProvider).supportDir.path}/multi_exposure_first.jpg';

  void toggle() => state.armed ? cancel() : state = const MultiExposureState(armed: true);

  /// Holds the capture at [captured] as the first exposure.
  Future<void> hold(String captured) async {
    final dest = _firstPath;
    try {
      await File(captured).rename(dest);
    } on FileSystemException {
      await File(captured).copy(dest);
      await File(captured).delete();
    }
    state = MultiExposureState(armed: true, first: dest);
  }

  /// The second exposure is in: done (the held one is consumed by the caller).
  void done() => state = const MultiExposureState();

  void cancel() {
    final f = state.first;
    if (f != null) {
      try {
        File(f).deleteSync();
      } catch (_) {}
    }
    state = const MultiExposureState();
  }
}
