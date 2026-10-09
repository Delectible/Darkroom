import 'dart:async';

import 'package:flutter/widgets.dart';

/// The camera bodies' art, decoded once and kept for the whole session.
/// Each image keeps a listener, so it stays a "live" image: the image cache
/// can't evict it (its size limit, or memory pressure when the app goes to
/// the background), and swapping bodies never has to decode it again.
abstract final class ArtCache {
  static final _pinned = <ImageProvider, ImageStream>{};

  /// Decodes [image] (if it isn't already) and keeps it. Completes when it
  /// is ready, or failed (it can then be tried again).
  static Future<void> pin(ImageProvider image, ImageConfiguration config) {
    if (_pinned.containsKey(image)) return Future.value();
    final done = Completer<void>();
    final stream = image.resolve(config);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        info.dispose(); // the stream keeps its own copy while listened to
        if (!done.isCompleted) done.complete();
      },
      onError: (_, _) {
        stream.removeListener(listener);
        _pinned.remove(image);
        if (!done.isCompleted) done.complete();
      },
    );
    stream.addListener(listener);
    _pinned[image] = stream;
    return done.future;
  }

  /// Pins [images] a few at a time (decoding runs in parallel off the UI
  /// thread), in order.
  static Future<void> pinAll(Iterable<ImageProvider> images, ImageConfiguration config) async {
    final list = images.toList();
    for (var i = 0; i < list.length; i += 6) {
      await Future.wait(list.skip(i).take(6).map((p) => pin(p, config)));
    }
  }

  static int get count => _pinned.length;
}
