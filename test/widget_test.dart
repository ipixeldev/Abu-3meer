import 'package:fan_league/demo/fan_league_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('bootstrap transitions from splash into the app', (tester) async {
    await tester.pumpWidget(
      FanLeagueBootstrap(initializeFirebase: () => Future<Object?>.value()),
    );
    expect(find.byKey(const ValueKey('premium-splash')), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('ENTER THE LEAGUE'), findsOneWidget);
  });

  testWidgets('launches the Fan League client demo', (tester) async {
    await tester.pumpWidget(const FanLeagueApp());
    await tester.pumpAndSettle();

    expect(find.text('THE FAN\nLEAGUE'), findsOneWidget);
    expect(find.text('ENTER THE LEAGUE'), findsOneWidget);
  });

  testWidgets('enters the responsive product shell', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const FanLeagueApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('ENTER THE LEAGUE'));
    await tester.pumpAndSettle();

    expect(find.text('Good evening, Ahmed'), findsOneWidget);
    expect(find.text('Fan Hub'), findsOneWidget);
    expect(find.text('Match Result'), findsOneWidget);
  });

  testWidgets('opens the three-step account flow', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const FanLeagueApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('CREATE A DEMO ACCOUNT'));
    await tester.tap(find.text('CREATE A DEMO ACCOUNT'));
    await tester.pumpAndSettle();

    expect(find.text('CREATE YOUR ACCOUNT'), findsOneWidget);
    expect(find.text('STEP 1 / 3'), findsOneWidget);
    await tester.tap(find.text('CONTINUE'));
    await tester.pumpAndSettle();
    expect(find.text('BUILD YOUR PROFILE'), findsOneWidget);
  });

  testWidgets('opens and starts the football trivia arena', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const FanLeagueApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('ENTER THE LEAGUE'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More features'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trivia Arena'));
    await tester.pumpAndSettle();

    expect(find.text('WHO KNOWS\nFOOTBALL BEST?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('start-trivia')));
    await tester.pump();
    expect(
      find.text('Which stadium is Real Madrid’s home ground?'),
      findsOneWidget,
    );
  });
}
