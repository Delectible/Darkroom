import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Is the live viewfinder actually getting new frames? The camera saying
/// "ready" only means it opened: a stream that never starts (or stops) looks
/// exactly like a frozen picture. Two tiny pictures of the raw preview (under
/// the look and lens), a moment apart: a live sensor never gives the same
/// pixels twice.
class PreviewProbe {
  PreviewProbe._();

  /// Around the plugin's own preview texture (viewport.dart).
  static final key = GlobalKey(debugLabel: 'preview probe');

  /// The preview is on screen to be looked at (not under a still).
  static bool get mounted => key.currentContext?.findRenderObject() is RenderRepaintBoundary;

  /// true: frames are coming. false: the same picture twice. null: can't
  /// tell (not on screen, or the picture couldn't be read).
  static Future<bool?> moving({Duration gap = const Duration(milliseconds: 450)}) async {
    final a = await _grab();
    if (a == null) return null;
    await Future<void>.delayed(gap);
    final b = await _grab();
    if (b == null || b.length != a.length) return null;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return true;
    }
    return false;
  }

  /// How bright the raw preview is, 0..1 (the front flash's auto: fire in
  /// the dark), or null when it can't be read.
  static Future<double?> brightness() async {
    final px = await _grab();
    if (px == null || px.isEmpty) return null;
    var sum = 0.0;
    var n = 0;
    for (var i = 0; i + 2 < px.length; i += 4) {
      sum += 0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2];
      n++;
    }
    return n == 0 ? null : sum / n / 255;
  }

  static Future<Uint8List?> _grab() async {
    final ro = key.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary || !ro.attached || !ro.hasSize) return null;
    final side = ro.size.longestSide;
    if (side <= 0) return null;
    ui.Image? img;
    try {
      img = await ro.toImage(pixelRatio: 64 / side);
      final data = await img.toByteData();
      if (data == null) return null;
      final px = data.buffer.asUint8List();
      // Nothing drawn at all (a texture this phone won't read back): no answer.
      var alpha = false;
      for (var i = 3; i < px.length; i += 4) {
        if (px[i] != 0) {
          alpha = true;
          break;
        }
      }
      return alpha ? px : null;
    } catch (_) {
      return null;
    } finally {
      img?.dispose();
    }
  }
}
