import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/db/media_repository.dart';
import 'media_actions.dart';

/// A single photo (pinch-zoomable) or video (tap to play/pause, loops).
class MediaView extends StatelessWidget {
  const MediaView({super.key, required this.item, this.background = Colors.black});

  final MediaItem item;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final path = item.outputPath;
    if (path == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (item.isVideo) return _VideoPane(path: path, background: background);
    return ColoredBox(
      color: background,
      child: InteractiveViewer(
        maxScale: 6,
        child: Center(
          child: Image.file(
            File(path),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }
}

class _VideoPane extends StatefulWidget {
  const _VideoPane({required this.path, required this.background});

  final String path;
  final Color background;

  @override
  State<_VideoPane> createState() => _VideoPaneState();
}

class _VideoPaneState extends State<_VideoPane> {
  late final VideoPlayerController _c = VideoPlayerController.file(File(widget.path));
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      await _c.initialize();
      await _c.setLooping(true);
      await _c.play();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Cannot play this clip');
    }
  }

  @override
  void dispose() {
    unawaited(_c.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: widget.background,
      child: _error != null
          ? Center(
              child: Text(_error!, style: const TextStyle(color: Colors.white70)),
            )
          : !_ready
          ? const Center(child: CircularProgressIndicator())
          : GestureDetector(
              onTap: () => setState(() => _c.value.isPlaying ? _c.pause() : _c.play()),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AspectRatio(aspectRatio: _c.value.aspectRatio, child: VideoPlayer(_c)),
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: _c,
                    builder: (context, v, _) => AnimatedOpacity(
                      opacity: v.isPlaying ? 0 : 1,
                      duration: const Duration(milliseconds: 150),
                      child: const Icon(Icons.play_circle_fill, size: 64, color: Colors.white70),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: VideoProgressIndicator(_c, allowScrubbing: true),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: _c,
                      builder: (context, v, _) => Text(
                        '${formatDuration(v.position.inMilliseconds)} / ${formatDuration(v.duration.inMilliseconds)}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
