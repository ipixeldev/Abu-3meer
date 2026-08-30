// Consistent spacing, radii, elevation tokens for the Abu 3meer Community demo.
// All values are multiples of 4px (the base unit).

class AppSpacing {
  // ──────────────────────────────────────────────────────────────
  // Base unit
  // ──────────────────────────────────────────────────────────────
  static const double _u = 4.0;

  // ──────────────────────────────────────────────────────────────
  // Spacing scale (0 – 24)
  // ──────────────────────────────────────────────────────────────
  static const double space0 = 0;
  static const double space1 = _u * 1; // 4
  static const double space2 = _u * 2; // 8
  static const double space3 = _u * 3; // 12
  static const double space4 = _u * 4; // 16
  static const double space5 = _u * 5; // 20
  static const double space6 = _u * 6; // 24
  static const double space7 = _u * 7; // 28
  static const double space8 = _u * 8; // 32
  static const double space9 = _u * 9; // 36
  static const double space10 = _u * 10; // 40
  static const double space12 = _u * 12; // 48
  static const double space14 = _u * 14; // 56
  static const double space16 = _u * 16; // 64
  static const double space20 = _u * 20; // 80
  static const double space24 = _u * 24; // 96

  // ──────────────────────────────────────────────────────────────
  // Semantic aliases
  // ──────────────────────────────────────────────────────────────
  static const double xs = space1;
  static const double sm = space2;
  static const double md = space4;
  static const double lg = space6;
  static const double xl = space8;
  static const double xxl = space12;
  static const double xxxl = space16;

  // Component-specific
  static const double cardPadding = space5; // 20
  static const double cardPaddingSm = space3; // 12
  static const double cardPaddingLg = space6; // 24
  static const double screenPadding = space5; // 20
  static const double screenPaddingLg = space6; // 24
  static const double sectionGap = space6; // 24
  static const double itemGap = space3; // 12
  static const double inlineGap = space2; // 8
  static const double iconTextGap = space2; // 8
  static const double buttonHorizontal = space6; // 24
  static const double buttonVertical = space4; // 16
  static const double inputHorizontal = space4; // 16
  static const double inputVertical = space4; // 16

  // ──────────────────────────────────────────────────────────────
  // Border radii
  // ──────────────────────────────────────────────────────────────
  static const double radiusXs = 4;
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;
  static const double radiusXxl = 24;
  static const double radiusFull = 999;

  static const BorderRadius brXs = BorderRadius.all(Radius.circular(radiusXs));
  static const BorderRadius brSm = BorderRadius.all(Radius.circular(radiusSm));
  static const BorderRadius brMd = BorderRadius.all(Radius.circular(radiusMd));
  static const BorderRadius brLg = BorderRadius.all(Radius.circular(radiusLg));
  static const BorderRadius brXl = BorderRadius.all(Radius.circular(radiusXl));
  static const BorderRadius brXxl = BorderRadius.all(
    Radius.circular(radiusXxl),
  );
  static const BorderRadius brFull = BorderRadius.all(
    Radius.circular(radiusFull),
  );

  static const BorderRadius brTopLg = BorderRadius.vertical(
    top: Radius.circular(radiusLg),
  );
  static const BorderRadius brTopXl = BorderRadius.vertical(
    top: Radius.circular(radiusXl),
  );
  static const BorderRadius brBottomLg = BorderRadius.vertical(
    bottom: Radius.circular(radiusLg),
  );

  // ──────────────────────────────────────────────────────────────
  // Elevation / shadow tokens (used sparingly)
  // ──────────────────────────────────────────────────────────────
  static const List<BoxShadow> shadowNone = [];
  static const List<BoxShadow> shadowSm = [
    BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> shadowMd = [
    BoxShadow(color: Color(0x40000000), blurRadius: 12, offset: Offset(0, 4)),
  ];
  static const List<BoxShadow> shadowLg = [
    BoxShadow(color: Color(0x4D000000), blurRadius: 24, offset: Offset(0, 8)),
  ];
  static const List<BoxShadow> shadowXl = [
    BoxShadow(color: Color(0x59000000), blurRadius: 40, offset: Offset(0, 16)),
  ];

  // ──────────────────────────────────────────────────────────────
  // Breakpoints (used by responsive layouts)
  // ──────────────────────────────────────────────────────────────
  static const double bpMobile = 480; // ≤ 479: compact phone
  static const double bpMobileLg = 640; // 480 – 639: large phone
  static const double bpTablet = 900; // 640 – 899: tablet
  static const double bpDesktop = 1200; // 900 – 1199: small desktop
  static const double bpDesktopLg = 1440; // ≥ 1200: desktop

  /// Current breakpoint enum for responsive widgets.
  static AppBreakpoint breakpointFromWidth(double width) {
    if (width < bpMobile) return AppBreakpoint.mobile;
    if (width < bpMobileLg) return AppBreakpoint.mobileLg;
    if (width < bpTablet) return AppBreakpoint.tablet;
    if (width < bpDesktop) return AppBreakpoint.desktop;
    if (width < bpDesktopLg) return AppBreakpoint.desktopLg;
    return AppBreakpoint.desktopXl;
  }
}

enum AppBreakpoint { mobile, mobileLg, tablet, desktop, desktopLg, desktopXl }

/// Responsive value helper — picks the right value for the current breakpoint.
T responsive<T>({
  required BuildContext context,
  required T mobile,
  T? mobileLg,
  T? tablet,
  T? desktop,
  T? desktopLg,
  T? desktopXl,
}) {
  final bp = AppSpacing.breakpointFromWidth(MediaQuery.of(context).size.width);
  switch (bp) {
    case AppBreakpoint.mobile:
      return mobile;
    case AppBreakpoint.mobileLg:
      return mobileLg ?? mobile;
    case AppBreakpoint.tablet:
      return tablet ?? mobileLg ?? mobile;
    case AppBreakpoint.desktop:
      return desktop ?? tablet ?? mobileLg ?? mobile;
    case AppBreakpoint.desktopLg:
      return desktopLg ?? desktop ?? tablet ?? mobileLg ?? mobile;
    case AppBreakpoint.desktopXl:
      return desktopXl ?? desktopLg ?? desktop ?? tablet ?? mobileLg ?? mobile;
  }
}
