import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/camera_spec.dart';

/// Photoreal product shot of a stock / body (pre-rendered, transparent
/// WebP). Decoded at the size it is shown at, so a carousel of eight of them
/// costs a few MB of texture memory at most.
class CameraArtwork extends StatelessWidget {
  const CameraArtwork({super.key, required this.spec});

  final CameraSpec spec;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final side = math.min(
          box.hasBoundedWidth ? box.maxWidth : 320.0,
          box.hasBoundedHeight ? box.maxHeight : 320.0,
        );
        final px = (side * dpr).round().clamp(64, 1024);
        return Image.asset(
          spec.artwork,
          fit: BoxFit.contain,
          cacheWidth: px,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          errorBuilder: (context, _, _) => Center(
            child: Icon(
              spec.recordsVideo
                  ? Icons.videocam_outlined
                  : (spec.isFilm ? Icons.camera_roll_outlined : Icons.photo_camera_outlined),
              size: side * 0.4,
              color: Colors.white24,
            ),
          ),
        );
      },
    );
  }
}
