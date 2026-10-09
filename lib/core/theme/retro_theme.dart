import 'package:flutter/material.dart';

import '../../features/cameras/domain/camera_spec.dart';

/// The two skins. Film = dark pebbled leatherette + brass; Digital = brushed
/// silver plastic + backlit LCD.
@immutable
class RetroPalette extends ThemeExtension<RetroPalette> {
  const RetroPalette({
    required this.mode,
    required this.body,
    required this.bodyHighlight,
    required this.bodyShadow,
    required this.metal,
    required this.metalDark,
    required this.text,
    required this.textMuted,
    required this.accent,
    required this.danger,
    required this.screen,
    required this.screenInk,
  });

  final AppMode mode;
  final Color body;
  final Color bodyHighlight;
  final Color bodyShadow;
  final Color metal;
  final Color metalDark;
  final Color text;
  final Color textMuted;
  final Color accent;
  final Color danger;
  final Color screen;
  final Color screenInk;

  static const film = RetroPalette(
    mode: AppMode.film,
    body: Color(0xFF221C17),
    bodyHighlight: Color(0xFF3A3029),
    bodyShadow: Color(0xFF110D0A),
    metal: Color(0xFFCDB07A),
    metalDark: Color(0xFF7D6440),
    text: Color(0xFFF1E7D2),
    textMuted: Color(0xFFB3A48A),
    accent: Color(0xFFE0B25B),
    danger: Color(0xFFD9483B),
    screen: Color(0xFF0D0B09),
    screenInk: Color(0xFFF6EBD2),
  );

  static const digital = RetroPalette(
    mode: AppMode.digital,
    body: Color(0xFFC5CAD1),
    bodyHighlight: Color(0xFFEDEFF2),
    bodyShadow: Color(0xFF7D848D),
    metal: Color(0xFFE3E6EA),
    metalDark: Color(0xFF8C939C),
    text: Color(0xFF22262B),
    textMuted: Color(0xFF5A6169),
    accent: Color(0xFF2F6FD6),
    danger: Color(0xFFE53935),
    screen: Color(0xFF10140F),
    screenInk: Color(0xFFB7F5A8),
  );

  static RetroPalette of(BuildContext context) => Theme.of(context).extension<RetroPalette>() ?? film;

  static RetroPalette forMode(AppMode mode) => mode == AppMode.film ? film : digital;

  @override
  RetroPalette copyWith() => this;

  @override
  RetroPalette lerp(covariant RetroPalette? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return RetroPalette(
      mode: t < 0.5 ? mode : other.mode,
      body: c(body, other.body),
      bodyHighlight: c(bodyHighlight, other.bodyHighlight),
      bodyShadow: c(bodyShadow, other.bodyShadow),
      metal: c(metal, other.metal),
      metalDark: c(metalDark, other.metalDark),
      text: c(text, other.text),
      textMuted: c(textMuted, other.textMuted),
      accent: c(accent, other.accent),
      danger: c(danger, other.danger),
      screen: c(screen, other.screen),
      screenInk: c(screenInk, other.screenInk),
    );
  }

  ThemeData toTheme() {
    final dark = mode == AppMode.film;
    final base = dark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: body,
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        secondary: metal,
        surface: bodyHighlight,
        onSurface: text,
        error: danger,
      ),
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      // High contrast on any screen: orange when on, dark grey when off.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? const Color(0xFFFFF4EA) : const Color(0xFF9A9A9E),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? const Color(0xFFFF7A1A) : const Color(0xFF2A2A2D),
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? const Color(0xFFFF7A1A) : const Color(0xFF5A5A5E),
        ),
      ),
      extensions: [this],
    );
  }
}
