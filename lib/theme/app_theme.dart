import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryCyan = Color(0xFF63E6BE);

  static const Color accentPurple = Color(0xFF9B8AFB);
  static const Color accentBlue = Color(0xFF5B9CFF);

  static const Color statusOnline = Color(0xFF4ADE80);
  static const Color statusDown = Color(0xFFFB7185);
  static const Color statusUnknown = Color(0xFFFBBF24);

  static const Color backgroundDark = Color(0xFF090C11);
  static const Color backgroundCard = Color(0xFF11161E);
  static const Color backgroundCardElevated = Color(0xFF171D27);
  static const Color backgroundCardGlass = Color(0x0FFFFFFF);
  static const Color borderSubtle = Color(0xFF252D38);

  static const Color textPrimary = Color(0xFFF5F7FA);
  static const Color textSecondary = Color(0xFF9AA6B2);
  static const Color textTertiary = Color(0xFF687483);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryCyan, Color(0xFF34D399)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF7C6DF2), Color(0xFF4F8CF7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFF090C11), Color(0xFF0D1118), Color(0xFF090C11)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF151B24), Color(0xFF11161E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusXLarge = 20.0;

  static List<BoxShadow> glowShadow(Color color, {double intensity = 0.3}) {
    return [
      BoxShadow(
        color: color.withValues(alpha: intensity * 0.45),
        blurRadius: 18,
        spreadRadius: 0,
      ),
    ];
  }

  static List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.22),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];

  static BoxDecoration glassDecoration({
    double radius = radiusLarge,
    Color? borderColor,
  }) {
    return BoxDecoration(
      color: backgroundCard,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? borderSubtle,
        width: 1,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: primaryCyan,
      scaffoldBackgroundColor: backgroundDark,
      fontFamily: 'Inter',
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: primaryCyan,
        secondary: accentPurple,
        surface: backgroundCard,
        onPrimary: Color(0xFF06110E),
        onSecondary: Colors.white,
        onSurface: textPrimary,
        error: statusDown,
      ),
      dividerColor: borderSubtle,
      splashColor: primaryCyan.withValues(alpha: 0.06),
      highlightColor: primaryCyan.withValues(alpha: 0.03),
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundDark,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: textSecondary),
      ),
      cardTheme: CardThemeData(
        color: backgroundCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          side: const BorderSide(color: borderSubtle),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryCyan,
          foregroundColor: const Color(0xFF06110E),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: borderSubtle),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: backgroundCardElevated,
        contentTextStyle: const TextStyle(color: textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: textPrimary,
          fontSize: 30,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
        ),
        headlineMedium: TextStyle(
          color: textPrimary,
          fontSize: 23,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(color: textSecondary, fontSize: 16),
        bodyMedium: TextStyle(color: textSecondary, fontSize: 14),
        bodySmall: TextStyle(color: textTertiary, fontSize: 12),
        labelLarge: TextStyle(
          color: textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class AnimatedGradientBackground extends StatelessWidget {
  final Widget child;

  const AnimatedGradientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
      child: child,
    );
  }
}
