import 'package:flutter/material.dart';

// ─── Stitch Design System Tokens ──────────────────────────────────────────
/// Material Design 3 dark color palette from Stitch mobile mockups.
class Stitch {
  Stitch._();

  // Surface hierarchy (darkest → lightest)
  static const background = Color(0xFF0E1416);
  static const surface = Color(0xFF0E1416);
  static const surfaceDim = Color(0xFF0E1416);
  static const surfaceLowest = Color(0xFF090F11);
  static const surfaceLow = Color(0xFF171D1E);
  static const container = Color(0xFF1B2122);
  static const containerHigh = Color(0xFF252B2D);
  static const containerHighest = Color(0xFF303638);
  static const surfaceBright = Color(0xFF343A3C);
  static const surfaceVariant = Color(0xFF303638);

  // On-surface text
  static const onBackground = Color(0xFFDEE3E6);
  static const onSurface = Color(0xFFDEE3E6);
  static const onSurfaceVariant = Color(0xFFBCC9CD);

  // Primary (cyan)
  static const primary = Color(0xFF4CD7F6);
  static const onPrimary = Color(0xFF003640);
  static const primaryContainer = Color(0xFF06B6D4);
  static const onPrimaryContainer = Color(0xFF00424F);
  static const primaryFixedDim = Color(0xFF4CD7F6);

  // Secondary (green)
  static const secondary = Color(0xFF4EDEA3);
  static const onSecondary = Color(0xFF003824);
  static const secondaryContainer = Color(0xFF00A572);
  static const onSecondaryContainer = Color(0xFF00311F);

  // Tertiary (amber)
  static const tertiary = Color(0xFFFFB95F);
  static const onTertiary = Color(0xFF472A00);
  static const tertiaryContainer = Color(0xFFE79400);
  static const onTertiaryContainer = Color(0xFF563400);
  static const tertiaryFixedDim = Color(0xFFFFB95F);

  // Error
  static const error = Color(0xFFFFB4AB);
  static const onError = Color(0xFF690005);
  static const errorContainer = Color(0xFF93000A);
  static const onErrorContainer = Color(0xFFFFDAD6);

  // Outline
  static const outline = Color(0xFF869397);
  static const outlineVariant = Color(0xFF3D494C);

  // Semantic helpers
  static Color severity(int level) {
    if (level >= 4) return error;
    if (level >= 3) return tertiaryContainer;
    if (level >= 2) return tertiary;
    return secondary;
  }
}

/// Material 3 dark color system with Inter typography.
class AppColors {
  AppColors._();

  static const background = Color(0xFF0a0e14);
  static const surface0 = Color(0xFF0e1219);
  static const surface1 = Color(0xFF131a24);
  static const surface2 = Color(0xFF19222e);

  static const textPrimary = Color(0xFFe6edf3);
  static const textSecondary = Color(0xFF7d8590);
  // WCAG AA requires 4.5:1 on surface0 #0e1219; old 0xFF484f58 gave 2.1:1 (illegible on projector). Lift to 0xFF8b949e ≈ 4.6:1
  static const textMuted = Color(0xFF8b949e);

  static const accent = Color(0xFF22d3ee);

  static const alertRed = Color(0xFFf87171);
  static const alertOrange = Color(0xFFfb923c);
  static const alertAmber = Color(0xFFfbbf24);
  static const focusedGreen = Color(0xFF34d399);
  static const offlineYellow = Color(0xFFfbbf24);

  static const gaugeTrack = Color(0x15ffffff);

  /// Primary gradient used for hero cards and accents.
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF34d399), Color(0xFF22d3ee)],
  );

  /// Subtle card gradient.
  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [surface1, surface2],
  );

  static Color severity(int level) {
    if (level >= 4) return alertRed;
    if (level >= 3) return alertOrange;
    if (level >= 2) return alertAmber;
    return accent;
  }
}

/// Shared text styles for consistent typography.
class AppTextStyles {
  AppTextStyles._();

  static const _fontFamily = 'Inter';

  // Headlines
  static const headlineLg = TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
      letterSpacing: -1,
      fontFamily: _fontFamily);
  static const headlineMd = TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
      letterSpacing: -0.5,
      fontFamily: _fontFamily);
  static const headlineSm = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
      fontFamily: _fontFamily);

  // Body
  static const bodyLg = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: AppColors.textPrimary,
      fontFamily: _fontFamily);
  static const bodyMd = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: AppColors.textSecondary,
      fontFamily: _fontFamily);
  static const bodySm = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: AppColors.textSecondary,
      fontFamily: _fontFamily);

  // Data (monospace)
  static const dataLg = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
      fontFamily: 'monospace');
  static const dataMd = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: AppColors.textPrimary,
      fontFamily: 'monospace');
  static const dataSm = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: AppColors.textPrimary,
      fontFamily: 'monospace');

  // Labels
  static const labelCaps = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      color: AppColors.textSecondary,
      fontFamily: _fontFamily);
  static const labelSm = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      color: AppColors.textSecondary,
      fontFamily: _fontFamily);

  // Mono
  static const mono = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      fontFamily: 'monospace',
      color: AppColors.textPrimary);
}

/// Responsive layout breakpoints.
class AppBreakpoints {
  AppBreakpoints._();
  static const double compact = 600;
  static const double medium = 900;
  static const double expanded = 1100;
}
