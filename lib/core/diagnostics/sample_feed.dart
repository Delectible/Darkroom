import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'debug_flags.dart';

/// Debug > Sample Viewfinder: when on, photo viewers (corkboard and Darkroom
/// 98) offer "Use in viewfinder", and the camera's viewfinder then shows that
/// picture instead of the live feed, for screen recordings. Only the
/// viewfinder: shots still come from the real camera. Not saved.
final sampleFeedButtonProvider = NotifierProvider<DebugFlag, bool>(DebugFlag.new);

class SampleFeed extends Notifier<String?> {
  @override
  String? build() => null;

  void use(String? path) => state = path;
}

/// The picture shown in the viewfinder instead of the camera (null: live).
final sampleFeedProvider = NotifierProvider<SampleFeed, String?>(SampleFeed.new);
