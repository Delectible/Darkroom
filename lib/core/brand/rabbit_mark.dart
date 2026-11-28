import 'package:flutter/widgets.dart';

import 'app_look.dart';

/// The rabbit picture (welcome tour, launch curtain, dialogs): X'd-out eyes
/// with the original icon, no face with any other (Look.eyes). Changes the
/// moment the icon does.
class RabbitMark extends StatelessWidget {
  const RabbitMark({super.key, this.width, this.height});

  final double? width, height;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLook>(
      valueListenable: Look.notifier,
      builder: (context, _, _) => Image.asset(
        Look.rabbitAsset,
        width: width,
        height: height,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
      ),
    );
  }
}
