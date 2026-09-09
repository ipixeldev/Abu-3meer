import 'package:abu_3meer/production/shell_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only the five persistent shell pages map to root tabs', () {
    expect(ProductionShellNavigation.rootTabForPage(0), 0);
    expect(ProductionShellNavigation.rootTabForPage(1), 1);
    expect(ProductionShellNavigation.rootTabForPage(2), 2);
    expect(ProductionShellNavigation.rootTabForPage(3), 3);
    expect(ProductionShellNavigation.rootTabForPage(5), 4);

    // Leaderboard, settings, and Admin Studio must not highlight Home.
    expect(ProductionShellNavigation.rootTabForPage(4), -1);
    expect(ProductionShellNavigation.rootTabForPage(6), -1);
    expect(ProductionShellNavigation.rootTabForPage(7), -1);
  });

  test('root tab positions resolve to their actual shell pages', () {
    expect(ProductionShellNavigation.pageForRootTab(0), 0);
    expect(ProductionShellNavigation.pageForRootTab(4), 5);
    expect(() => ProductionShellNavigation.pageForRootTab(5), throwsRangeError);
  });

  testWidgets('selecting a root tab pops nested routes to the shell root', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('Root')),
      ),
    );

    navigatorKey.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Nested')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nested'), findsOneWidget);

    ProductionShellNavigation.popToRoot(navigatorKey.currentState!);
    await tester.pumpAndSettle();
    expect(find.text('Root'), findsOneWidget);
    expect(find.text('Nested'), findsNothing);
  });

  testWidgets('non-root placeholder forwards Home taps in LTR and RTL', (
    tester,
  ) async {
    final selections = <int>[];

    Future<void> pump(TextDirection direction) => tester.pumpWidget(
      Directionality(
        textDirection: direction,
        child: Center(
          child: SizedBox(
            width: 500,
            height: 80,
            child: ProductionRootTabTapForwarder(
              key: const ValueKey<String>('root-forwarder'),
              selectedRootTab: -1,
              rootTabCount: 5,
              textDirection: direction,
              onSelect: selections.add,
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      ),
    );

    await pump(TextDirection.ltr);
    final ltrOrigin = tester.getTopLeft(
      find.byKey(const ValueKey<String>('root-forwarder')),
    );
    await tester.tapAt(ltrOrigin + const Offset(50, 40));
    expect(selections, <int>[0]);

    await pump(TextDirection.rtl);
    final rtlOrigin = tester.getTopLeft(
      find.byKey(const ValueKey<String>('root-forwarder')),
    );
    await tester.tapAt(rtlOrigin + const Offset(450, 40));
    expect(selections, <int>[0, 0]);
  });
}
