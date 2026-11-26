import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'debug_flags.dart';

/// Debug > Marketing > Hide Photos: a button on the corkboard and in Darkroom
/// 98 that turns on "hide mode", where a tap marks a photo hidden (or shows
/// it again) instead of opening it. Out of hide mode the marked photos are
/// left off the board and the file lists, for clean screenshots. Switched
/// off, everything shows. Not saved: a restart shows every photo again.
final hidePhotosButtonProvider = NotifierProvider<DebugFlag, bool>(DebugFlag.new);

/// Picking photos to hide (taps toggle instead of open).
final hideModeProvider = NotifierProvider<DebugFlag, bool>(DebugFlag.new);

class HiddenPhotos extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String id) => state = state.contains(id) ? ({...state}..remove(id)) : {...state, id};
}

final hiddenPhotosProvider = NotifierProvider<HiddenPhotos, Set<String>>(HiddenPhotos.new);

/// Ids to leave out right now (none while picking, or with the switch off).
final photosToHideProvider = Provider<Set<String>>((ref) {
  if (!ref.watch(hidePhotosButtonProvider) || ref.watch(hideModeProvider)) return const {};
  return ref.watch(hiddenPhotosProvider);
});

/// Whether a photo shows as marked (only while picking).
final markedHiddenProvider = Provider.family<bool, String>((ref, id) {
  if (!ref.watch(hidePhotosButtonProvider) || !ref.watch(hideModeProvider)) return false;
  return ref.watch(hiddenPhotosProvider).contains(id);
});
