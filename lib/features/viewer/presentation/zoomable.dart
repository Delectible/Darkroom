import 'package:flutter/material.dart';

/// Pinch-zoomable content that reports whether it is zoomed in, so a
/// surrounding pager can stop swiping while the user pans around.
class Zoomable extends StatefulWidget {
  const Zoomable({super.key, required this.child, this.onZoomChanged, this.maxScale = 6});

  final Widget child;
  final ValueChanged<bool>? onZoomChanged;
  final double maxScale;

  @override
  State<Zoomable> createState() => _ZoomableState();
}

class _ZoomableState extends State<Zoomable> {
  final _t = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _t.addListener(_onChange);
  }

  @override
  void dispose() {
    _t.dispose();
    // A page scrolled away while zoomed must not leave the pager locked.
    if (_zoomed) widget.onZoomChanged?.call(false);
    super.dispose();
  }

  void _onChange() {
    final zoomed = _t.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed == _zoomed) return;
    _zoomed = zoomed;
    widget.onZoomChanged?.call(zoomed);
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(transformationController: _t, maxScale: widget.maxScale, child: widget.child);
  }
}

/// Swipe-between-pages viewer whose swipe is switched off while the current
/// page is zoomed in: a zoomed photo pans instead of flipping to the next one.
class ZoomPageView extends StatefulWidget {
  const ZoomPageView({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.itemBuilder,
    this.onPageChanged,
  });

  final PageController controller;
  final int itemCount;
  final ValueChanged<int>? onPageChanged;

  /// Build page [index]; wrap zoomable content in a [Zoomable] that forwards
  /// [onZoomChanged].
  final Widget Function(BuildContext context, int index, ValueChanged<bool> onZoomChanged) itemBuilder;

  @override
  State<ZoomPageView> createState() => _ZoomPageViewState();
}

class _ZoomPageViewState extends State<ZoomPageView> {
  bool _locked = false;

  void _onZoom(bool zoomed) {
    if (zoomed == _locked || !mounted) return;
    // Zoom callbacks can arrive mid-build (e.g. a page being disposed).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _locked != zoomed) setState(() => _locked = zoomed);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: widget.controller,
      itemCount: widget.itemCount,
      physics: _locked ? const NeverScrollableScrollPhysics() : null,
      onPageChanged: (i) {
        _locked = false;
        widget.onPageChanged?.call(i);
      },
      itemBuilder: (context, i) => widget.itemBuilder(context, i, _onZoom),
    );
  }
}
