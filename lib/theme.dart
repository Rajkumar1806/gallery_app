import 'package:flutter/material.dart';

/// Soft lavender "frosted glass" look inspired by the ColorOS gallery.
class GalleryColors {
  static const accent = Color(0xFF5A5FD8);

  static List<Color> backgroundGradient(Brightness b) => b == Brightness.light
      ? const [Color(0xFFF1EEFB), Color(0xFFDDE2FA), Color(0xFFE9E4F8)]
      : const [Color(0xFF15151F), Color(0xFF1B1D2C), Color(0xFF17151F)];

  static Color glass(Brightness b) => b == Brightness.light
      ? Colors.white.withOpacity(0.55)
      : Colors.white.withOpacity(0.08);

  static Color glassBorder(Brightness b) => b == Brightness.light
      ? Colors.white.withOpacity(0.7)
      : Colors.white.withOpacity(0.12);

  static Color subtle(Brightness b) => b == Brightness.light
      ? const Color(0xFF8A8DA6)
      : const Color(0xFF9A9CB4);
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: GalleryColors.accent,
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    splashFactory: InkSparkle.splashFactory,
    textTheme: Typography.material2021(platform: TargetPlatform.android)
        .black
        .apply(
          bodyColor: brightness == Brightness.light
              ? const Color(0xFF2B2D42)
              : const Color(0xFFE8E8F2),
          displayColor: brightness == Brightness.light
              ? const Color(0xFF2B2D42)
              : const Color(0xFFE8E8F2),
        ),
  );
}

/// Full-screen gradient used behind every page.
class GradientBackground extends StatelessWidget {
  const GradientBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: GalleryColors.backgroundGradient(b),
        ),
      ),
      child: child,
    );
  }
}
