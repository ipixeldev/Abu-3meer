// Premium dark theme colour palette.
// Near-black base, elevated surfaces, high-contrast text, strong accent colours.
// Barcelona / Real Madrid colours used only contextually — never as global theme.

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

/// Semantic colour tokens used across the app.
class AppColors {
  // ── Base surfaces ──────────────────────────────────────────────
  /// Near-black canvas background.
  static const Color bgCanvas = Color(0xFF0A0A0A);

  /// Slightly elevated card / sheet surface.
  static const Color bgSurface = Color(0xFF141414);

  /// Higher elevation (modals, dropdowns, tooltips).
  static const Color bgSurfaceElevated = Color(0xFF1E1E1E);

  /// Subtle divider / hairline.
  static const Color divider = Color(0xFF2A2A2A);

  /// Pressed / active surface state.
  static const Color bgSurfacePressed = Color(0xFF222222);

  // ── Text hierarchy ─────────────────────────────────────────────
  static const Color textPrimary = Color(
    0xFFFFFFFF,
  ); // Headlines, important numbers
  static const Color textSecondary = Color(0xFFB3B3B3); // Body, labels
  static const Color textMuted = Color(0xFF7A7A7A); // Placeholders, hints
  static const Color textOnAccent = Color(
    0xFF0A0A0A,
  ); // Text on coloured buttons
  static const Color textInverse = Color(0xFF0A0A0A); // Rare, on light surfaces

  // ── Accent / Brand ─────────────────────────────────────────────
  /// Primary brand accent — electric amber/gold used for CTAs, highlights.
  static const Color accentPrimary = Color(0xFFFFB800);
  static const Color accentPrimaryDim = Color(0xCCFFB800);
  static const Color accentPrimaryDark = Color(0xFFE6A600);

  /// Secondary accent — cool cyan for info, progress, XP.
  static const Color accentSecondary = Color(0xFF00E5CC);
  static const Color accentSecondaryDim = Color(0xCC00E5CC);

  /// Success / reward green.
  static const Color success = Color(0xFF22C55E);
  static const Color successDim = Color(0xCC22C55E);

  /// Error / destructive red.
  static const Color error = Color(0xFFEF4444);
  static const Color errorDim = Color(0xCCEF4444);

  // ── Team contextual colours (used ONLY where team identity is shown) ─────
  /// Barcelona — blaugrana.
  static const Color barcaBlue = Color(0xFF004D98);
  static const Color barcaRed = Color(0xFFA50044);

  /// Real Madrid — white / gold trim.
  static const Color madridWhite = Color(0xFFFFFFFF);
  static const Color madridGold = Color(0xFFC8962E);
  static const Color madridNavy = Color(0xFF00529F);

  // ── Gradients (used sparingly, only for hierarchy) ─────────────
  static const LinearGradient gradientPrimary = LinearGradient(
    colors: [Color(0xFFFFB800), Color(0xFFFF8A00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient gradientSurface = LinearGradient(
    colors: [Color(0xFF1A1A1A), Color(0xFF121212)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient gradientBarca = LinearGradient(
    colors: [Color(0xFF004D98), Color(0xFFA50044)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient gradientMadrid = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFC8962E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── XP / Rank specific ─────────────────────────────────────────
  static const Color xpGold = Color(0xFFFFB800);
  static const Color xpCyan = Color(0xFF00E5CC);
  static const Color rankGold = Color(0xFFFFD700);
  static const Color rankSilver = Color(0xFFC0C0C0);
  static const Color rankBronze = Color(0xFFCD7F32);
}

/// Light theme is intentionally unsupported — this is a premium dark app.
/// The colour scheme below is built ONLY for the dark theme.

ColorScheme _darkScheme() => const ColorScheme.dark(
  primary: AppColors.accentPrimary,
  onPrimary: AppColors.textOnAccent,
  primaryContainer: AppColors.accentPrimaryDark,
  onPrimaryContainer: AppColors.textOnAccent,
  secondary: AppColors.accentSecondary,
  onSecondary: AppColors.textOnAccent,
  secondaryContainer: AppColors.accentSecondaryDim,
  onSecondaryContainer: AppColors.textOnAccent,
  tertiary: AppColors.success,
  onTertiary: AppColors.textOnAccent,
  error: AppColors.error,
  onError: AppColors.textOnAccent,
  surface: AppColors.bgSurface,
  onSurface: AppColors.textPrimary,
  surfaceContainerHighest: AppColors.bgSurfaceElevated,
  onSurfaceVariant: AppColors.textSecondary,
  outline: AppColors.divider,
  outlineVariant: AppColors.divider,
  shadow: Colors.black,
  scrim: Colors.black87,
  inverseSurface: Colors.white,
  onInverseSurface: Colors.black,
  inversePrimary: AppColors.accentPrimaryDark,
);

/// Base dark theme used by the whole app.
ThemeData buildDarkTheme() {
  final cs = _darkScheme();
  final base = ThemeData.dark(useMaterial3: true).copyWith(
    colorScheme: cs,
    scaffoldBackgroundColor: AppColors.bgCanvas,
    canvasColor: AppColors.bgCanvas,
    cardColor: AppColors.bgSurface,
    dividerColor: AppColors.divider,
    shadowColor: Colors.black,
  );

  return base.copyWith(
    // ── AppBar ───────────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.bgSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      iconTheme: IconThemeData(color: cs.onSurface, size: 24),
      actionsIconTheme: IconThemeData(color: cs.onSurface, size: 24),
    ),

    // ── Cards / Containers ───────────────────────────────────────
    cardTheme: CardThemeData(
      color: AppColors.bgSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.zero,
      shadowColor: Colors.black,
    ),

    // ── Buttons ──────────────────────────────────────────────────
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accentPrimary,
        foregroundColor: AppColors.textOnAccent,
        disabledBackgroundColor: AppColors.accentPrimary.withValues(
          alpha: 0.35,
        ),
        disabledForegroundColor: AppColors.textOnAccent.withValues(alpha: 0.5),
        elevation: 0,
        shadowColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: 15,
          letterSpacing: 0.2,
        ),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accentPrimary,
        foregroundColor: AppColors.textOnAccent,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: 15,
          letterSpacing: 0.2,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: BorderSide(color: AppColors.divider, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accentPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    ),

    // ── Inputs ───────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bgSurfaceElevated,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: TextStyle(
        color: AppColors.textMuted,
        fontFamily: 'Inter',
        fontSize: 15,
      ),
      labelStyle: TextStyle(
        color: AppColors.textSecondary,
        fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      floatingLabelStyle: TextStyle(
        color: AppColors.accentPrimary,
        fontFamily: 'Inter',
        fontWeight: FontWeight.w600,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.accentPrimary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.error, width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.divider.withValues(alpha: 0.5)),
      ),
      errorStyle: TextStyle(
        color: AppColors.error,
        fontFamily: 'Inter',
        fontSize: 12,
      ),
      prefixIconColor: AppColors.textMuted,
      suffixIconColor: AppColors.textMuted,
    ),

    // ── Chips ────────────────────────────────────────────────────
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.bgSurfaceElevated,
      disabledColor: AppColors.bgSurfaceElevated.withValues(alpha: 0.5),
      selectedColor: AppColors.accentPrimary.withValues(alpha: 0.2),
      secondarySelectedColor: AppColors.accentPrimary,
      labelStyle: TextStyle(
        color: AppColors.textPrimary,
        fontFamily: 'Inter',
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      secondaryLabelStyle: TextStyle(
        color: AppColors.textOnAccent,
        fontFamily: 'Inter',
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.divider),
      ),
      side: BorderSide(color: AppColors.divider),
      brightness: Brightness.dark,
    ),

    // ── Dialogs / Bottom Sheets ──────────────────────────────────
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.bgSurfaceElevated,
      surfaceTintColor: Colors.transparent,
      elevation: 24,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontFamily: 'Inter',
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: TextStyle(
        color: AppColors.textSecondary,
        fontFamily: 'Inter',
        fontSize: 15,
      ),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.bgSurfaceElevated,
      surfaceTintColor: Colors.transparent,
      elevation: 24,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      modalBackgroundColor: AppColors.bgSurfaceElevated,
      dragHandleColor: AppColors.divider,
    ),

    // ── Navigation / Tabs ────────────────────────────────────────
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.bgSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      height: 72,
      indicatorColor: AppColors.accentPrimary.withValues(alpha: 0.15),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.accentPrimary,
          );
        }
        return TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.textMuted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: AppColors.accentPrimary, size: 24);
        }
        return IconThemeData(color: AppColors.textMuted, size: 24);
      }),
    ),

    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.accentPrimary,
      unselectedLabelColor: AppColors.textMuted,
      indicatorColor: AppColors.accentPrimary,
      indicatorSize: TabBarIndicatorSize.label,
      labelStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
      unselectedLabelStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      dividerColor: AppColors.divider,
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return AppColors.accentPrimary.withValues(alpha: 0.1);
        }
        return Colors.transparent;
      }),
    ),

    // ── Lists / Tiles ────────────────────────────────────────────
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontFamily: 'Inter',
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      subtitleTextStyle: TextStyle(
        color: AppColors.textSecondary,
        fontFamily: 'Inter',
        fontSize: 13,
      ),
      leadingAndTrailingTextStyle: TextStyle(
        color: AppColors.textSecondary,
        fontFamily: 'Inter',
        fontSize: 13,
      ),
      iconColor: AppColors.textSecondary,
      selectedTileColor: AppColors.accentPrimary.withValues(alpha: 0.1),
      selectedColor: AppColors.accentPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    // ── Sliders / Progress ───────────────────────────────────────
    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.accentPrimary,
      inactiveTrackColor: AppColors.divider,
      thumbColor: AppColors.accentPrimary,
      overlayColor: AppColors.accentPrimary.withValues(alpha: 0.15),
      valueIndicatorColor: AppColors.accentPrimary,
      valueIndicatorTextStyle: TextStyle(
        color: AppColors.textOnAccent,
        fontFamily: 'Inter',
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      trackHeight: 6,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 10),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: AppColors.accentPrimary,
      linearTrackColor: AppColors.divider,
      circularTrackColor: AppColors.divider,
    ),

    // ── SnackBar ─────────────────────────────────────────────────
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.bgSurfaceElevated,
      contentTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontFamily: 'Inter',
        fontSize: 14,
      ),
      actionTextColor: AppColors.accentPrimary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 8,
    ),

    // ── Tooltips ─────────────────────────────────────────────────
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.bgSurfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      textStyle: TextStyle(
        color: AppColors.textPrimary,
        fontFamily: 'Inter',
        fontSize: 12,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      preferBelow: false,
    ),

    // ── Dividers ─────────────────────────────────────────────────
    dividerTheme: DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 1,
      indent: 0,
      endIndent: 0,
    ),

    // ── Scrollbar ────────────────────────────────────────────────
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(AppColors.divider),
      trackColor: WidgetStateProperty.all(Colors.transparent),
      thickness: WidgetStateProperty.all(6),
      radius: Radius.circular(3),
      crossAxisMargin: 4,
      mainAxisMargin: 4,
    ),

    // ── Text Selection ───────────────────────────────────────────
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: AppColors.accentPrimary,
      selectionColor: AppColors.accentPrimary.withValues(alpha: 0.3),
      selectionHandleColor: AppColors.accentPrimary,
    ),

    // ── Platform-specific overrides ──────────────────────────────
    cupertinoOverrideTheme: const CupertinoThemeData(
      brightness: Brightness.dark,
      primaryColor: AppColors.accentPrimary,
      scaffoldBackgroundColor: AppColors.bgCanvas,
      barBackgroundColor: AppColors.bgSurface,
      textTheme: CupertinoTextThemeData(
        textStyle: TextStyle(fontFamily: 'Inter', color: AppColors.textPrimary),
        navTitleTextStyle: TextStyle(
          fontFamily: 'Inter',
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 17,
        ),
        navLargeTitleTextStyle: TextStyle(
          fontFamily: 'Inter',
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 34,
        ),
        actionTextStyle: TextStyle(
          fontFamily: 'Inter',
          color: AppColors.accentPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 17,
        ),
      ),
    ),
  );
}
