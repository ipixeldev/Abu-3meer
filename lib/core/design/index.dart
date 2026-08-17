// Fan League Design System — single import for the whole design language.
export 'colors.dart';
export 'typography.dart';
export 'spacing.dart';

/// Initializes Google Fonts for the app (call once at startup).
/// Falls back gracefully if fonts cannot be loaded.
Future<void> initDesignSystem() async {
  // google_fonts loads lazily on first use; this forces a warm-up
  // so the first frame doesn't jank. Non-blocking.
  try {
    await Future.wait([
      GoogleFonts.pendingFonts([
        'Barlow Condensed',
        'Inter',
      ]),
    ]);
  } catch (_) {
    // Offline / font load failed — Material defaults will be used.
  }
}

// Re-export GoogleFonts for convenience.
export 'package:google_fonts/google_fonts.dart' show GoogleFonts;
