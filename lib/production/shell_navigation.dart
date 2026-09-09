import 'package:flutter/widgets.dart';

/// Navigation contract for the five persistent mobile root tabs.
///
/// Leaderboard, settings, and staff pages are shell pages, but are not root
/// tabs. They intentionally map to `-1` so the bottom bar does not pretend
/// that Home is selected while one of those pages is visible.
abstract final class ProductionShellNavigation {
  static const List<int> mobileRootPageIndexes = <int>[0, 1, 2, 3, 5];

  static int rootTabForPage(int shellPageIndex) =>
      mobileRootPageIndexes.indexOf(shellPageIndex);

  static int pageForRootTab(int rootTabIndex) {
    if (rootTabIndex < 0 || rootTabIndex >= mobileRootPageIndexes.length) {
      throw RangeError.index(
        rootTabIndex,
        mobileRootPageIndexes,
        'rootTabIndex',
      );
    }
    return mobileRootPageIndexes[rootTabIndex];
  }

  /// A persistent-root selection always dismisses routes pushed above the
  /// shell. This makes selecting or reselecting Home deterministic even after
  /// opening a nested detail page.
  static void popToRoot(NavigatorState navigator) {
    navigator.popUntil((route) => route.isFirst);
  }
}

/// Forwards the one tap that `glass_liquid_navbar` suppresses when a non-root
/// shell page uses a neutral placeholder index for layout.
///
/// Pointer events still reach [child], so all ordinary root-tab taps continue
/// through the navbar's native animation and callback. Only the placeholder
/// tab is forwarded, preventing duplicate callbacks.
class ProductionRootTabTapForwarder extends StatelessWidget {
  const ProductionRootTabTapForwarder({
    super.key,
    required this.selectedRootTab,
    required this.rootTabCount,
    required this.textDirection,
    required this.onSelect,
    required this.child,
  });

  final int selectedRootTab;
  final int rootTabCount;
  final TextDirection textDirection;
  final ValueChanged<int> onSelect;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Listener(
      behavior: HitTestBehavior.translucent,
      onPointerUp: selectedRootTab >= 0 || rootTabCount <= 0
          ? null
          : (event) {
              final width = constraints.maxWidth;
              if (!width.isFinite || width <= 0) return;
              final visualIndex =
                  (event.localPosition.dx / (width / rootTabCount))
                      .floor()
                      .clamp(0, rootTabCount - 1);
              final logicalIndex = textDirection == TextDirection.rtl
                  ? rootTabCount - 1 - visualIndex
                  : visualIndex;
              // The neutral layout placeholder is logical root tab zero.
              if (logicalIndex == 0) onSelect(0);
            },
      child: child,
    ),
  );
}
