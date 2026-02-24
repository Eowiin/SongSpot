import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum ColorBlindnessMode { none, deuteranopia, protanopia, tritanopia }

class AppTheme {
  // Colors
  static const Color primaryColor = Color(0xFF6C63FF);
  static const Color secondaryColor = Color(0xFFFF6584);
  static const Color accentColor = Color(0xFF4ECDC4);
  static const Color backgroundColor = Color(0xFF1A1A2E);
  static const Color surfaceColor = Color(0xFF16213E);
  static const Color errorColor = Color(0xFFFF4444);
  static const Color successColor = Color(0xFF00C851);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B0B0);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryColor, Color(0xFF9D5CFF)],
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [backgroundColor, Color(0xFF0F0F1E)],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [surfaceColor, Color(0xFF1E2A4A)],
  );

  // Theme Data
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColor,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: secondaryColor,
        surface: surfaceColor,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        onError: Colors.white,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(
        const TextTheme(
          displayLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
          displayMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
          displaySmall: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
          headlineMedium: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
          titleLarge: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            color: textPrimary,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            color: textSecondary,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: errorColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        hintStyle: const TextStyle(color: textSecondary),
      ),
      cardTheme: const CardThemeData(
        color: surfaceColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
    );
  }

  // Common padding and margins
  static const EdgeInsets pagePadding = EdgeInsets.all(24.0);
  static const EdgeInsets cardPadding = EdgeInsets.all(16.0);
  static const double borderRadius = 12.0;
  static const double cardBorderRadius = 16.0;

  // High contrast theme — solid backgrounds, white text, vivid accents
  static ThemeData get highContrastTheme {
    const Color hcBackground = Color(0xFF000000);
    const Color hcSurface = Color(0xFF1A1A1A);
    const Color hcPrimary = Color(0xFFFFFF00); // yellow on black = max contrast
    const Color hcText = Color(0xFFFFFFFF);
    const Color hcSecondaryText = Color(0xFFE0E0E0);
    const Color hcError = Color(0xFFFF6B6B);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: hcPrimary,
      scaffoldBackgroundColor: hcBackground,
      colorScheme: const ColorScheme.dark(
        primary: hcPrimary,
        secondary: hcPrimary,
        surface: hcSurface,
        error: hcError,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: hcText,
        onError: Colors.black,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(TextTheme(
        displayLarge: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: hcText),
        displayMedium: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: hcText),
        displaySmall: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: hcText),
        headlineMedium: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: hcText),
        titleLarge: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: hcText),
        bodyLarge: const TextStyle(fontSize: 16, color: hcText),
        bodyMedium: const TextStyle(fontSize: 14, color: hcSecondaryText),
      )),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: hcPrimary,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: hcPrimary, width: 2),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: hcSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: hcPrimary, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: hcText, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: hcPrimary, width: 3),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        hintStyle: const TextStyle(color: hcSecondaryText),
      ),
      cardTheme: CardThemeData(
        color: hcSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: hcText.withValues(alpha: 0.4), width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: hcText),
        iconTheme: IconThemeData(color: hcText),
      ),
    );
  }

  // Color blindness adapted themes
  static ThemeData getThemeForColorBlindness(ColorBlindnessMode mode) {
    switch (mode) {
      case ColorBlindnessMode.none:
        return darkTheme;
      case ColorBlindnessMode.deuteranopia:
      case ColorBlindnessMode.protanopia:
        // Avoid red/green distinction: replace pink/red with orange, keep purple
        return _buildAdaptedTheme(
          primary: const Color(0xFF6C63FF), // keep purple
          secondary: const Color(0xFFFF8C00), // orange replaces pink/red
          accent: const Color(0xFF00BFFF), // deep sky blue replaces teal
        );
      case ColorBlindnessMode.tritanopia:
        // Avoid blue/yellow distinction: replace teal/blue with pink
        return _buildAdaptedTheme(
          primary: const Color(0xFFBB44FF), // violet/magenta replaces purple-blue
          secondary: const Color(0xFFFF6584), // keep pink (no blue)
          accent: const Color(0xFFFF4DA6), // hot pink replaces teal
        );
    }
  }

  static ThemeData _buildAdaptedTheme({
    required Color primary,
    required Color secondary,
    required Color accent,
  }) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: primary,
      scaffoldBackgroundColor: backgroundColor,
      colorScheme: ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: surfaceColor,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        onError: Colors.white,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(const TextTheme(
        displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: textPrimary),
        displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textPrimary),
        displaySmall: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textPrimary),
        headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: textPrimary),
        titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
        bodyLarge: TextStyle(fontSize: 16, color: textPrimary),
        bodyMedium: TextStyle(fontSize: 14, color: textSecondary),
      )),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceColor,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: primary, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: errorColor, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        hintStyle: const TextStyle(color: textSecondary),
      ),
      cardTheme: const CardThemeData(
        color: surfaceColor,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: textPrimary),
        iconTheme: IconThemeData(color: textPrimary),
      ),
    );
  }
}
