import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Developer switches from Win98 Help > Debug. Not saved: a restart clears
/// them.
class DebugFlag extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}
