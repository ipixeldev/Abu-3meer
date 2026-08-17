// Typography scale for the Fan League demo.
// Uses Google Fonts at runtime: Barlow Condensed (headlines/numbers) + Inter (UI/body).
// Provides TextStyle helpers with consistent weights, tracking, and line heights.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

class AppTextStyles {
  // ──────────────────────────────────────────────────────────────
  // Font families (loaded via google_fonts at runtime)
  // ──────────────────────────────────────────────────────────────
  static const String _displayFamily = 'Barlow Condensed';
  static const String _uiFamily = 'Inter';

  // ──────────────────────────────────────────────────────────────
  // Display / Headlines — Barlow Condensed, wide tracking
  // ──────────────────────────────────────────────────────────────
  static TextStyle displayLarge({
    Color color = AppColors.textPrimary,
    FontWeight weight = FontWeight.w700,
    double letterSpacing = -1.0,
    double height = 1.05,
  }) => GoogleFonts.getFont(
    _displayFamily,
    fontSize: 48,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: height,
    color: color,
  );

  static TextStyle displayMedium({
    Color color = AppColors.textPrimary,
    FontWeight weight = FontWeight.w700,
    double letterSpacing = -0.5,
    double height = 1.1,
  }) => GoogleFonts.getFont(
    _displayFamily,
    fontSize: 36,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: height,
    color: color,
  );

  static TextStyle displaySmall({
    Color color = AppColors.textPrimary,
    FontWeight weight = FontWeight.w600,
    double letterSpacing = -0.3,
    double height = 1.15,
  }) => GoogleFonts.getFont(
    _displayFamily,
    fontSize: 28,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: height,
    color: color,
  );

  // ──────────────────────────────────────────────────────────────
  // Headlines — Barlow Condensed
  // ──────────────────────────────────────────────────────────────
  static TextStyle headlineLarge({
    Color color = AppColors.textPrimary,
    FontWeight weight = FontWeight.w700,
    double letterSpacing = 0,
    double height = 1.2,
  }) => GoogleFonts.getFont(
    _displayFamily,
    fontSize: 24,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: height,
    color: color,
  );

  static TextStyle headlineMedium({
    Color color = AppColors.textPrimary,
    FontWeight weight = FontWeight.w600,
    double letterSpacing = 0.1,
    double height = 1.25,
  }) => GoogleFonts.getFont(
    _displayFamily,
    fontSize: 20,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: height,
    color: color,
  );

  static TextStyle headlineSmall({
    Color color = AppColors.textPrimary,
    FontWeight weight = FontWeight.w600,
    double letterSpacing = 0.15,
    double height = 1.3,
  }) => GoogleFonts.getFont(
    _displayFamily,
    fontSize: 17,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: height,
    color: color,
  );

  // ──────────────────────────────────────────────────────────────
  // Titles — Barlow Condensed (medium) / Inter (small)
  // ──────────────────────────────────────────────────────────────
  static TextStyle titleLarge({
    Color color = AppColors.textPrimary,
    FontWeight weight = FontWeight.w600,
    double letterSpacing = 0.2,
    double height = 1.3,
  }) => GoogleFonts.getFont(
    _displayFamily,
    fontSize: 16,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: height,
    color: color,
  );

  static TextStyle titleMedium({
    Color color = AppColors.textPrimary,
    FontWeight weight = FontWeight.w600,
    double letterSpacing = 0.25,
    double height = 1.35,
  }) => GoogleFonts.getFont(
    _uiFamily,
    fontSize: 15,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: height,
    color: color,
  );

  static TextStyle titleSmall({
    Color color = AppColors.textPrimary,
    FontWeight weight = FontWeight.w600,
    double letterSpacing = 0.3,
    double height = 1.4,
  }) => GoogleFonts.getFont(
    _uiFamily,
    fontSize: 13,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: height,
    color: color,
  );

  // ──────────────────────────────────────────────────────────────
  // Body — Inter
  // ──────────────────────────────────────────────────────────────
  static TextStyle bodyLarge({
    Color color = AppColors.textPrimary,
    FontWeight weight = FontWeight.w400,
    double letterSpacing = 0.2,
    double height = 1.5,
  }) => GoogleFonts.getFont(
    _uiFamily,
    fontSize: 16,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: height,
    color: color,
  );

  static TextStyle bodyMedium({
    Color color = AppColors.textSecondary,
    FontWeight weight = FontWeight.w400,
    double letterSpacing = 0.25,
    double height = 1.5,
  }) => GoogleFonts.getFont(
    _uiFamily,
    fontSize: 14,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: height,
    color: color,
  );

  static TextStyle bodySmall({
    Color color = AppColors.textSecondary,
    FontWeight weight = FontWeight.w400,
    double letterSpacing = 0.3,
    double height = 1.45,
  }) => GoogleFonts.getFont(
    _uiFamily,
    fontSize: 12,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: height,
    color: color,
  );

  // ──────────────────────────────────────────────────────────────
  // Labels / Captions — Inter
  // ──────────────────────────────────────────────────────────────
  static TextStyle labelLarge({
    Color color = AppColors.textPrimary,
    FontWeight weight = FontWeight.w600,
    double letterSpacing = 0.3,
    double height = 1.4,
  }) => GoogleFonts.getFont(
    _uiFamily,
    fontSize: 14,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: height,
    color: color,
  );

  static TextStyle labelMedium({
    Color color = AppColors.textSecondary,
    FontWeight weight = FontWeight.w500,
    double letterSpacing = 0.4,
    double height = 1.4,
  }) => GoogleFonts.getFont(
    _uiFamily,
    fontSize: 12,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: height,
    color: color,
  );

  static TextStyle labelSmall({
    Color color = AppColors.textMuted,
    FontWeight weight = FontWeight.w500,
    double letterSpacing = 0.5,
    double height = 1.4,
  }) => GoogleFonts.getFont(
    _uiFamily,
    fontSize: 11,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: height,
    color: color,
  );

  // ──────────────────────────────────────────────────────────────
  // Numbers / Stats — Barlow Condensed, tabular figures where possible
  // ──────────────────────────────────────────────────────────────
  static TextStyle numberDisplay({
    Color color = AppColors.textPrimary,
    FontWeight weight = FontWeight.w700,
    double letterSpacing = -1.5,
    double height = 1.0,
    double size = 64,
  }) => GoogleFonts.getFont(
    _displayFamily,
    fontSize: size,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: height,
    color: color,
  );

  static TextStyle numberLarge({
    Color color = AppColors.textPrimary,
    FontWeight weight = FontWeight.w700,
    double letterSpacing = -0.5,
    double height = 1.1,
    double size = 40,
  }) => GoogleFonts.getFont(
    _displayFamily,
    fontSize: size,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: height,
    color: color,
  );

  static TextStyle numberMedium({
    Color color = AppColors.textPrimary,
    FontWeight weight = FontWeight.w600,
    double letterSpacing = 0,
    double height = 1.2,
    double size = 28,
  }) => GoogleFonts.getFont(
    _displayFamily,
    fontSize: size,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: height,
    color: color,
  );

  static TextStyle numberSmall({
    Color color = AppColors.textSecondary,
    FontWeight weight = FontWeight.w600,
    double letterSpacing = 0.2,
    double height = 1.3,
    double size = 18,
  }) => GoogleFonts.getFont(
    _displayFamily,
    fontSize: size,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: height,
    color: color,
  );

  // ──────────────────────────────────────────────────────────────
  // Special: Rank badges, XP labels, team tags
  // ──────────────────────────────────────────────────────────────
  static TextStyle rankBadge({
    Color color = AppColors.textOnAccent,
    FontWeight weight = FontWeight.w800,
    double size = 11,
  }) => GoogleFonts.getFont(
    _displayFamily,
    fontSize: size,
    fontWeight: weight,
    letterSpacing: 0.8,
    height: 1.2,
    color: color,
  );

  static TextStyle xpLabel({
    Color color = AppColors.accentPrimary,
    FontWeight weight = FontWeight.w700,
    double size = 12,
  }) => GoogleFonts.getFont(
    _displayFamily,
    fontSize: size,
    fontWeight: weight,
    letterSpacing: 1.0,
    height: 1.2,
    color: color,
  );

  static TextStyle teamTag({
    required bool isBarcelona,
    Color? color,
    FontWeight weight = FontWeight.w700,
    double size = 10,
  }) => GoogleFonts.getFont(
    _displayFamily,
    fontSize: size,
    fontWeight: weight,
    letterSpacing: 1.2,
    height: 1.2,
    color: color ?? (isBarcelona ? AppColors.barcaBlue : AppColors.madridGold),
  );
}

/// Extension for quick access on BuildContext.
extension AppTextStylesExt on BuildContext {
  AppTextStyles get text => const AppTextStyles();
  ThemeData get theme => Theme.of(this);
  ColorScheme get cs => Theme.of(this).colorScheme;
}
