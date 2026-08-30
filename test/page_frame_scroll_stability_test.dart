import 'package:abu_3meer/demo/fan_league_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mobile page frames clamp pull-down overscroll', (tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: FanLeagueShell()));
    await tester.pump();

    final pageFrame = find.byType(SingleChildScrollView).first;
    final scrollView = tester.widget<SingleChildScrollView>(pageFrame);
    expect(scrollView.physics, isA<ClampingScrollPhysics>());

    final scrollable = find.descendant(
      of: pageFrame,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.pixels, position.minScrollExtent);

    await tester.drag(pageFrame, const Offset(0, 180));
    await tester.pumpAndSettle();

    expect(position.pixels, position.minScrollExtent);
    expect(position.outOfRange, isFalse);
  });
}
