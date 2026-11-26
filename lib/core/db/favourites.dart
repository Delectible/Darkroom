import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/camera/application/camera_ui_state.dart' show PrefKeys;
import '../monetization/pro.dart' show prefsOf;

/// Starred photos and reels (the star in the viewers), kept on the phone.
/// The corkboard and Darkroom 98 can show just these.
class Favourites extends Notifier<Set<String>> {
  @override
  Set<String> build() => (prefsOf(ref)?.getStringList(PrefKeys.favourites) ?? const []).toSet();

  void toggle(String id) {
    state = state.contains(id) ? ({...state}..remove(id)) : {...state, id};
    prefsOf(ref)?.setStringList(PrefKeys.favourites, state.toList());
  }
}

final favouritesProvider = NotifierProvider<Favourites, Set<String>>(Favourites.new);
