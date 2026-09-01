import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lottie/lottie.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:file_selector/file_selector.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:glass_liquid_navbar/glass_liquid_navbar.dart' as glass_nav;

import '../production/brand.dart';
import '../production/api_client.dart';
import '../production/admin_dashboard_stats.dart';
import '../production/api_production_repository.dart';
import '../production/app_preferences.dart';
import '../production/external_content_service.dart';
import '../production/ehzerha_embed.dart';
import '../production/models.dart';
import '../production/production_repository.dart';
import '../production/location_service.dart';
import '../production/notification_service.dart';
import '../production/youtube_membership_snapshot.dart';
import '../features/match/screens/match_facts_screen.dart';
import '../features/videos/exclusive_videos_view.dart';

part 'fan_league_extended.dart';
part 'trivia_arena.dart';
part 'production_ui.dart';
part 'production_features.dart';
part 'phase3_admin_points.dart';
part 'youtube_membership_snapshot_admin.dart';
part 'admin_dashboard_stats.dart';

const _ink = Color(0xFF080B10);
const _surface = Color(0xFF11161E);
const _surface2 = Color(0xFF181F2A);
const _line = Color(0xFF28313E);
const _lime = Color(0xFFC8FF38);
const _gold = Color(0xFFFFC857);
const _muted = Color(0xFF929CAA);
const _blue = Color(0xFF3878FF);
const _red = Color(0xFFFF4D62);

// Retained as internal fallbacks for shared theme-building code. The app is
// locked to ThemeMode.dark and no light-mode control is exposed to users.
const _lightInk = Color(0xFF172033);
const _lightCanvas = Color(0xFFF3F6FB);
const _lightSurface = Color(0xFFFFFFFF);
const _lightSurface2 = Color(0xFFE9EFF8);
const _lightLine = Color(0xFFD4DDEA);
const _lightMuted = Color(0xFF66758A);
const _lightPrimary = Color(0xFF2457D6);
const _lightPrimaryDark = Color(0xFF173B98);
const _lightAccent = Color(0xFFC44762);
const _lightSuccess = Color(0xFF087F5B);

bool _isDarkTheme(BuildContext context) => true;

/// Abu 3meer uses the stadium-lime accent throughout its dark-only interface.
Color _productionPrimary(BuildContext context) => _lime;

Color _productionOnPrimary(BuildContext context) => _ink;

Color _productionSurface(BuildContext context) => _surface;

Color _productionLine(BuildContext context) => _line;

Color _productionMuted(BuildContext context) => _muted;

const _latestVideoId = 'u_pHQ5jAoWk';
const _latestVideoUrl = 'https://www.youtube.com/watch?v=$_latestVideoId';
const _latestVideoTitle = '🚨 يلي أهلو ما ربوه ميسي يربيه 🔥 انجلترا ❌ ارجنتين';

class Abu3meerBootstrap extends StatefulWidget {
  const Abu3meerBootstrap({super.key, required this.initializeFirebase});

  final Future<void> Function() initializeFirebase;

  @override
  State<Abu3meerBootstrap> createState() => _Abu3meerBootstrapState();
}

class _Abu3meerBootstrapState extends State<Abu3meerBootstrap> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await widget.initializeFirebase();
    } catch (_) {}
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: _ready
        ? const FanLeagueApp(key: ValueKey('fan-league-app'))
        : const _PremiumSplash(key: ValueKey('premium-splash')),
  );
}

class _PremiumSplash extends StatelessWidget {
  const _PremiumSplash({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: _ink,
      body: Stack(
        children: [
          const Positioned.fill(child: _PitchBackdrop()),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 150,
                  height: 150,
                  child: Lottie.asset(
                    'assets/animations/splashscreen.json',
                    repeat: true,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const _LogoMark(size: 74),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  AbuBrand.appName.toUpperCase(),
                  style: _display(35, spacing: 1.6),
                ),
                const SizedBox(height: 8),
                const Text(
                  'THE MATCH NEVER ENDS',
                  style: TextStyle(
                    color: _lime,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.4,
                  ),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: 62,
                  height: 62,
                  child: Lottie.asset(
                    'assets/animations/ball-loading.json',
                    repeat: true,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const CircularProgressIndicator(
                      color: _lime,
                      strokeWidth: 3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class FanLeagueApp extends StatelessWidget {
  const FanLeagueApp({super.key});

  @override
  Widget build(BuildContext context) {
    final preferences = AbuAppPreferences.instance;
    return AnimatedBuilder(
      animation: preferences,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: AbuBrand.appName,
        locale: preferences.locale,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        themeMode: preferences.themeMode,
        theme: _abuTheme(brightness: Brightness.light),
        darkTheme: _abuTheme(brightness: Brightness.dark),
        builder: (context, child) => Directionality(
          textDirection: preferences.isArabic
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: child!,
        ),
        home: const _ProductionGate(),
      ),
    );
  }
}

ThemeData _abuTheme({required Brightness brightness}) {
  final dark = brightness == Brightness.dark;
  final base = dark
      ? ThemeData.dark(useMaterial3: true)
      : ThemeData.light(useMaterial3: true);
  final surface = dark ? _surface : _lightSurface;
  final surface2 = dark ? _surface2 : _lightSurface2;
  final line = dark ? _line : _lightLine;
  final scheme = dark
      ? const ColorScheme.dark(
          primary: _lime,
          secondary: _gold,
          surface: _surface,
        )
      : const ColorScheme.light(
          primary: _lightPrimary,
          onPrimary: Colors.white,
          primaryContainer: Color(0xFFDCE6FF),
          onPrimaryContainer: _lightPrimaryDark,
          secondary: _lightAccent,
          onSecondary: Colors.white,
          secondaryContainer: Color(0xFFFFE0E7),
          onSecondaryContainer: Color(0xFF7F243A),
          tertiary: _lightSuccess,
          onTertiary: Colors.white,
          tertiaryContainer: Color(0xFFD4F3E8),
          onTertiaryContainer: Color(0xFF075A42),
          error: Color(0xFFB42318),
          onError: Colors.white,
          surface: _lightSurface,
          onSurface: _lightInk,
          surfaceContainerHighest: _lightSurface2,
          onSurfaceVariant: _lightMuted,
          outline: _lightLine,
          outlineVariant: Color(0xFFE2E8F2),
        );
  return base.copyWith(
    scaffoldBackgroundColor: dark ? _ink : _lightCanvas,
    canvasColor: dark ? base.canvasColor : _lightCanvas,
    colorScheme: scheme,
    dividerColor: dark ? base.dividerColor : line,
    textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: dark ? Colors.white : _lightInk,
      displayColor: dark ? Colors.white : _lightInk,
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: dark ? 0 : 2,
      shadowColor: dark
          ? Colors.black.withValues(alpha: .04)
          : _lightInk.withValues(alpha: .08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: dark ? _lime : _lightPrimary, width: 1.5),
      ),
    ),
    filledButtonTheme: dark
        ? base.filledButtonTheme
        : FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: _lightPrimary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _lightPrimary.withValues(alpha: .25),
              disabledForegroundColor: _lightMuted,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
    outlinedButtonTheme: dark
        ? base.outlinedButtonTheme
        : OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: _lightPrimaryDark,
              side: const BorderSide(color: _lightLine),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
    segmentedButtonTheme: dark
        ? base.segmentedButtonTheme
        : SegmentedButtonThemeData(
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Colors.white
                    : _lightInk,
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? _lightPrimary
                    : Colors.transparent,
              ),
              side: const WidgetStatePropertyAll(BorderSide(color: _lightLine)),
            ),
          ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: dark
          ? _lime.withValues(alpha: .18)
          : _lightPrimary.withValues(alpha: .12),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? _ink : _lightSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      iconTheme: IconThemeData(color: dark ? Colors.white : _lightInk),
      titleTextStyle: TextStyle(
        color: dark ? Colors.white : _lightInk,
        fontWeight: FontWeight.w900,
        fontSize: 18,
      ),
    ),
  );
}

class _DemoGate extends StatefulWidget {
  const _DemoGate();

  @override
  State<_DemoGate> createState() => _DemoGateState();
}

class _DemoGateState extends State<_DemoGate> {
  int _stage = 0;

  @override
  Widget build(BuildContext context) {
    if (_stage == 2) return const FanLeagueShell();
    if (_stage == 1) {
      return _RegistrationFlow(
        onBack: () => setState(() => _stage = 0),
        onComplete: () => setState(() => _stage = 2),
      );
    }
    return _WelcomeScreen(
      onStart: () => setState(() => _stage = 2),
      onCreateAccount: () => setState(() => _stage = 1),
    );
  }
}

class _WelcomeScreen extends StatefulWidget {
  const _WelcomeScreen({required this.onStart, required this.onCreateAccount});
  final VoidCallback onStart;
  final VoidCallback onCreateAccount;

  @override
  State<_WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<_WelcomeScreen> {
  final _email = TextEditingController(text: 'ahmed@fanleague.demo');
  final _password = TextEditingController(text: 'legend18');
  bool _hidden = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compactPhone = MediaQuery.sizeOf(context).width < 430;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _PitchBackdrop()),
          Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                compactPhone ? 18 : 24,
                compactPhone ? 18 : 24,
                compactPhone ? 18 : 24,
                32,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final wide = box.maxWidth > 760;
                    final intro = const _BrandIntro();
                    final form = Card(
                      child: Padding(
                        padding: EdgeInsets.all(compactPhone ? 20 : 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('WELCOME BACK', style: _display(28)),
                            const SizedBox(height: 6),
                            const Text(
                              'Your league. Your club. Your legacy.',
                              style: TextStyle(color: _muted),
                            ),
                            SizedBox(height: compactPhone ? 20 : 26),
                            TextField(
                              controller: _email,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.mail_outline),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _password,
                              obscureText: _hidden,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  onPressed: () =>
                                      setState(() => _hidden = !_hidden),
                                  icon: Icon(
                                    _hidden
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: compactPhone ? 18 : 22),
                            FilledButton(
                              onPressed: widget.onStart,
                              style: FilledButton.styleFrom(
                                backgroundColor: _lime,
                                foregroundColor: _ink,
                                padding: const EdgeInsets.all(18),
                              ),
                              child: const Text(
                                'ENTER THE LEAGUE',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: widget.onCreateAccount,
                              child: const Text('CREATE A DEMO ACCOUNT'),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Demo credentials are pre-filled',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: _muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    );
                    if (!wide) {
                      return Column(
                        children: [
                          intro,
                          SizedBox(height: compactPhone ? 22 : 28),
                          form,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: intro),
                        const SizedBox(width: 70),
                        Expanded(child: form),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandIntro extends StatelessWidget {
  const _BrandIntro();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 430;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LogoMark(size: compact ? 54 : 64),
        SizedBox(height: compact ? 18 : 24),
        Text(
          'ABU 3MEER\nCOMMUNITY',
          style: _display(compact ? 52 : 64, height: .88),
        ),
        SizedBox(height: compact ? 14 : 18),
        Text(
          'WATCH. PREDICT. COMPETE.',
          style: _display(
            compact ? 14 : 17,
            color: _lime,
            spacing: compact ? 2 : 2.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Turn every match into a game. Earn XP, back your club, and climb beyond the crowd.',
          style: TextStyle(
            color: _muted,
            height: 1.55,
            fontSize: compact ? 14 : 16,
          ),
        ),
      ],
    );
  }
}

class FanLeagueShell extends StatefulWidget {
  const FanLeagueShell({super.key});

  @override
  State<FanLeagueShell> createState() => _FanLeagueShellState();
}

class _FanLeagueShellState extends State<FanLeagueShell> {
  int _index = 0;
  int _homeScore = 2;
  int _awayScore = 1;
  bool _predictionLocked = false;
  final _destinations = const [
    (Icons.grid_view_rounded, 'Community'),
    (Icons.sports_soccer_rounded, 'Predict'),
    (Icons.leaderboard_rounded, 'League'),
    (Icons.bolt_rounded, 'Challenges'),
    (Icons.person_rounded, 'Profile'),
    (Icons.fact_check_rounded, 'Match Result'),
    (Icons.local_fire_department_rounded, 'Streak'),
    (Icons.emoji_events_rounded, 'Achievements'),
    (Icons.military_tech_rounded, 'Levels'),
    (Icons.card_giftcard_rounded, 'Loyalty Store'),
    (Icons.notifications_rounded, 'Notifications'),
    (Icons.history_rounded, 'Activity'),
    (Icons.settings_rounded, 'Settings'),
    (Icons.science_rounded, 'Demo Mode'),
    (Icons.admin_panel_settings_rounded, 'Admin Console'),
    (Icons.scoreboard_rounded, 'Match Center'),
    (Icons.extension_rounded, 'Challenge Lab'),
    (Icons.badge_rounded, 'Profile Studio'),
    (Icons.sports_esports_rounded, 'Trivia Arena'),
    (Icons.live_tv_rounded, 'OBS Overlay'),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final desktop = box.maxWidth >= 900;
        final page = [
          _HomePage(onNavigate: (i) => setState(() => _index = i)),
          _PredictPage(
            homeScore: _homeScore,
            awayScore: _awayScore,
            locked: _predictionLocked,
            onHomeChanged: (v) => setState(() => _homeScore = v),
            onAwayChanged: (v) => setState(() => _awayScore = v),
            onLock: () => setState(() => _predictionLocked = true),
          ),
          const _LeaguePage(),
          const _ChallengesPage(),
          const _ProfilePage(),
          const _MatchResultPage(),
          const _StreakPage(),
          const _AchievementsPage(),
          const _LevelsPage(),
          const _LoyaltyPage(),
          const _NotificationsPage(),
          const _ActivityPage(),
          const _SettingsPage(),
          const _DemoModePage(),
          const _AdminConsolePage(),
          _MatchCenterPage(onPredict: () => setState(() => _index = 1)),
          const _ChallengeLabPage(),
          const _ProfileStudioPage(),
          const _TriviaArenaPage(),
          _ObsOverlayPage(onExit: () => setState(() => _index = 0)),
        ][_index];

        if (_index == 19) return page;

        if (!desktop) {
          return Scaffold(
            appBar: _TopBar(
              compact: true,
              onNavigate: (value) => setState(() => _index = value),
            ),
            body: page,
            bottomNavigationBar: NavigationBar(
              height: 66,
              selectedIndex: _index < 5 ? _index : 4,
              onDestinationSelected: (value) => setState(() => _index = value),
              backgroundColor: _surface,
              indicatorColor: _lime.withValues(alpha: .15),
              destinations: _destinations
                  .take(5)
                  .map(
                    (e) => NavigationDestination(icon: Icon(e.$1), label: e.$2),
                  )
                  .toList(),
            ),
          );
        }
        return Scaffold(
          body: Row(
            children: [
              Container(
                width: 238,
                color: _surface,
                padding: const EdgeInsets.fromLTRB(18, 28, 18, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        _LogoMark(size: 38),
                        SizedBox(width: 12),
                        Text(
                          'COMMUNITY',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: ListView(
                        children: List.generate(
                          _destinations.length,
                          (i) => Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: _SideItem(
                              icon: _destinations[i].$1,
                              label: _destinations[i].$2,
                              selected: i == _index,
                              onTap: () => setState(() => _index = i),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Divider(color: _line),
                    const SizedBox(height: 12),
                    const Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: _lime,
                          foregroundColor: _ink,
                          child: Text(
                            'A',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ahmed Karim',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              Text(
                                'LEVEL 18 · ULTRA',
                                style: TextStyle(color: _lime, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1, color: _line),
              Expanded(
                child: Column(
                  children: [
                    _TopBar(
                      compact: false,
                      onNavigate: (value) => setState(() => _index = value),
                    ),
                    Expanded(child: page),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopBar({required this.compact, required this.onNavigate});
  final bool compact;
  final ValueChanged<int> onNavigate;
  @override
  Size get preferredSize => const Size.fromHeight(66);
  @override
  Widget build(BuildContext context) {
    final narrow = compact && MediaQuery.sizeOf(context).width < 430;
    return AppBar(
      backgroundColor: _ink,
      automaticallyImplyLeading: false,
      leadingWidth: compact ? 50 : null,
      leading: compact
          ? const Padding(
              padding: EdgeInsets.only(left: 16),
              child: Center(child: _LogoMark(size: 30)),
            )
          : null,
      titleSpacing: compact ? 10 : NavigationToolbar.kMiddleSpacing,
      title: compact
          ? Text(
              narrow ? 'ABU' : 'COMMUNITY',
              maxLines: 1,
              overflow: TextOverflow.fade,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
            )
          : const Text(
              'Season 24/25',
              style: TextStyle(color: _muted, fontSize: 13),
            ),
      actions: [
        if (!narrow) ...[
          _Pill(
            icon: Icons.local_fire_department_rounded,
            text: '12 DAY',
            color: _red,
          ),
          const SizedBox(width: 8),
        ],
        _Pill(
          icon: Icons.stars_rounded,
          text: narrow ? '2.4K' : '2,480',
          color: _gold,
          compact: narrow,
        ),
        SizedBox(width: narrow ? 2 : 8),
        SizedBox(
          width: narrow ? 38 : 48,
          child: IconButton(
            tooltip: 'Notifications',
            onPressed: () => onNavigate(10),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
        ),
        PopupMenuButton<int>(
          tooltip: 'More features',
          onSelected: onNavigate,
          itemBuilder: (context) => const [
            PopupMenuItem(value: 6, child: Text('Streak')),
            PopupMenuItem(value: 7, child: Text('Achievements')),
            PopupMenuItem(value: 8, child: Text('Levels')),
            PopupMenuItem(value: 9, child: Text('Loyalty Store')),
            PopupMenuItem(value: 11, child: Text('Activity')),
            PopupMenuItem(value: 12, child: Text('Settings')),
            PopupMenuItem(value: 13, child: Text('Demo Mode')),
            PopupMenuItem(value: 14, child: Text('Admin Console')),
            PopupMenuItem(value: 15, child: Text('Match Center')),
            PopupMenuItem(value: 16, child: Text('Challenge Lab')),
            PopupMenuItem(value: 17, child: Text('Profile Studio')),
            PopupMenuItem(value: 18, child: Text('Trivia Arena')),
            PopupMenuItem(value: 19, child: Text('OBS Overlay')),
          ],
          icon: const Icon(Icons.apps_rounded),
        ),
        SizedBox(width: narrow ? 4 : 12),
      ],
    );
  }
}

class _PageFrame extends StatelessWidget {
  const _PageFrame({
    required this.title,
    required this.kicker,
    required this.child,
  });
  final String title;
  final String kicker;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 430;
    final desktop = width >= 900;
    final primary = _productionPrimary(context);
    final surface = _productionSurface(context);
    final line = _productionLine(context);
    final muted = _productionMuted(context);
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        compact
            ? 16
            : desktop
            ? 40
            : 22,
        compact
            ? 18
            : desktop
            ? 30
            : 24,
        compact
            ? 16
            : desktop
            ? 40
            : 22,
        desktop ? 64 : 160,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: desktop ? 1440 : 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (desktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            kicker.toUpperCase(),
                            style: TextStyle(
                              color: primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 1.8,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(title, style: _display(44)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: line),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.desktop_windows_rounded,
                            size: 15,
                            color: primary,
                          ),
                          SizedBox(width: 7),
                          Text(
                            'DESKTOP WORKSPACE',
                            style: TextStyle(
                              color: muted,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              if (!desktop) ...[
                Text(
                  kicker.toUpperCase(),
                  style: TextStyle(
                    color: primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: 1.8,
                  ),
                ),
                const SizedBox(height: 7),
                Text(title, style: _display(compact ? 32 : 38)),
              ],
              SizedBox(
                height: compact
                    ? 18
                    : desktop
                    ? 30
                    : 24,
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage({required this.onNavigate});
  final ValueChanged<int> onNavigate;
  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: 'Thursday, 13 August',
    title: 'Good evening, Ahmed',
    child: LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth > 820;
        final hero = _ProgressHero(onPredict: () => onNavigate(1));
        final side = Column(
          children: const [_StatStrip(), SizedBox(height: 16), _FanWarMini()],
        );
        return Column(
          children: [
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: hero),
                  const SizedBox(width: 18),
                  Expanded(flex: 3, child: side),
                ],
              )
            else ...[
              hero,
              const SizedBox(height: 16),
              side,
            ],
            const SizedBox(height: 28),
            const _LatestVideoCard(),
            const SizedBox(height: 28),
            _SectionTitle(title: 'Your next moves', action: 'VIEW ALL'),
            const SizedBox(height: 12),
            _ResponsiveGrid(
              children: [
                _ActionCard(
                  icon: Icons.play_circle_fill_rounded,
                  color: _red,
                  tag: 'VIDEO CHALLENGE',
                  title: 'Spot the secret phrase',
                  detail: 'Watch the latest episode · +250 XP',
                  progress: .7,
                ),
                _ActionCard(
                  icon: Icons.auto_awesome_rounded,
                  color: _gold,
                  tag: 'ACHIEVEMENT',
                  title: 'Prediction machine',
                  detail: '8 of 10 correct picks · +500 XP',
                  progress: .8,
                ),
                _ActionCard(
                  icon: Icons.calendar_month_rounded,
                  color: _lime,
                  tag: 'STREAK',
                  title: 'Keep the fire alive',
                  detail: 'Check in today · 12 day streak',
                  progress: .86,
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

class _ProgressHero extends StatelessWidget {
  const _ProgressHero({required this.onPredict});
  final VoidCallback onPredict;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final compact = box.maxWidth < 430;
      final matchInfo = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _TeamCrest(
            label: 'BAR',
            colors: const [_blue, _red],
            size: compact ? 44 : 46,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'EL CLÁSICO',
                  style: TextStyle(
                    color: _gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                Text(
                  'Barcelona vs Real Madrid',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _display(compact ? 18 : 20),
                ),
                const Text(
                  'Saturday · 21:00 · Camp Nou',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      );
      final predictButton = FilledButton(
        onPressed: onPredict,
        style: FilledButton.styleFrom(
          backgroundColor: _lime,
          foregroundColor: _ink,
        ),
        child: const Text(
          'PREDICT',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      );
      return Container(
        padding: EdgeInsets.all(compact ? 18 : 24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFF182313), _surface],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: _lime.withValues(alpha: .35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Text(
                  'LEVEL 18',
                  style: TextStyle(
                    color: _lime,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                Spacer(),
                _LiveDot(text: 'TOP 1%'),
              ],
            ),
            const SizedBox(height: 10),
            Text('ULTRA', style: _display(compact ? 40 : 48)),
            const SizedBox(height: 4),
            const Text('8,420 / 10,000 XP', style: TextStyle(color: _muted)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: const LinearProgressIndicator(
                value: .842,
                minHeight: 9,
                backgroundColor: _line,
                color: _lime,
              ),
            ),
            const SizedBox(height: 25),
            const Divider(color: _line),
            const SizedBox(height: 17),
            if (compact) ...[
              matchInfo,
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: predictButton),
            ] else
              Row(
                children: [
                  Expanded(child: matchInfo),
                  const SizedBox(width: 16),
                  predictButton,
                ],
              ),
          ],
        ),
      );
    },
  );
}

class _StatStrip extends StatelessWidget {
  const _StatStrip();
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: const [
          Expanded(
            child: _Metric(value: '#342', label: 'SEASON RANK', color: _lime),
          ),
          Expanded(
            child: _Metric(value: '↑ 18', label: 'THIS WEEK', color: _lime),
          ),
          Expanded(
            child: _Metric(value: '68%', label: 'ACCURACY', color: _gold),
          ),
        ],
      ),
    ),
  );
}

class _FanWarMini extends StatelessWidget {
  const _FanWarMini();
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text(
                'FAN WAR',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              Spacer(),
              _LiveDot(text: 'LIVE'),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _TeamCrest(
                    label: 'BAR',
                    colors: [_blue, _red],
                    size: 34,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    children: [
                      Text('51.8%', style: _display(26)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('—'),
                      ),
                      Text('48.2%', style: _display(26)),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _TeamCrest(
                    label: 'RMA',
                    colors: [Colors.white, Color(0xFFCBCBD4)],
                    size: 34,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: Row(
              children: [
                Expanded(flex: 518, child: Container(height: 8, color: _blue)),
                Expanded(
                  flex: 482,
                  child: Container(height: 8, color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Barcelona leads by 184,320 XP',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class _PredictPage extends StatefulWidget {
  const _PredictPage({
    required this.homeScore,
    required this.awayScore,
    required this.locked,
    required this.onHomeChanged,
    required this.onAwayChanged,
    required this.onLock,
  });
  final int homeScore;
  final int awayScore;
  final bool locked;
  final ValueChanged<int> onHomeChanged;
  final ValueChanged<int> onAwayChanged;
  final VoidCallback onLock;
  @override
  State<_PredictPage> createState() => _PredictPageState();
}

class _PredictPageState extends State<_PredictPage> {
  String winner = 'Barcelona';
  String scorer = 'Lamine Yamal';
  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: 'Predictions close in 02:14:36',
    title: 'El Clásico predictions',
    child: Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Text(
                  'LA LIGA · MATCHDAY 3',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 11,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Expanded(
                      child: _Club(
                        label: 'Barcelona',
                        code: 'BAR',
                        colors: [_blue, _red],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          Text('SAT 21:00', style: _display(18)),
                          const Text(
                            'CAMP NOU',
                            style: TextStyle(color: _muted, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    const Expanded(
                      child: _Club(
                        label: 'Real Madrid',
                        code: 'RMA',
                        colors: [Colors.white, Color(0xFFCBCBD4)],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, box) {
            final cards = [
              _PredictionCard(
                title: 'MATCH WINNER',
                xp: 100,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['Barcelona', 'Draw', 'Real Madrid']
                      .map(
                        (v) => ChoiceChip(
                          label: Text(v),
                          selected: winner == v,
                          onSelected: widget.locked
                              ? null
                              : (_) => setState(() => winner = v),
                        ),
                      )
                      .toList(),
                ),
              ),
              _PredictionCard(
                title: 'CORRECT SCORE',
                xp: 300,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ScorePicker(
                      value: widget.homeScore,
                      onChanged: widget.locked ? null : widget.onHomeChanged,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text('—', style: _display(30, color: _muted)),
                    ),
                    _ScorePicker(
                      value: widget.awayScore,
                      onChanged: widget.locked ? null : widget.onAwayChanged,
                    ),
                  ],
                ),
              ),
              _PredictionCard(
                title: 'FIRST SCORER',
                xp: 250,
                child: DropdownButtonFormField<String>(
                  initialValue: scorer,
                  items:
                      [
                            'Lamine Yamal',
                            'Robert Lewandowski',
                            'Kylian Mbappé',
                            'Vinícius Jr.',
                          ]
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                  onChanged: widget.locked
                      ? null
                      : (v) => setState(() => scorer = v!),
                ),
              ),
            ];
            if (box.maxWidth > 760) {
              return _ResponsiveGrid(minWidth: 340, children: cards);
            }
            return Column(
              children: cards
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: e,
                    ),
                  )
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _surface2,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: widget.locked ? _lime : _line),
          ),
          child: Row(
            children: [
              Icon(
                widget.locked ? Icons.lock_rounded : Icons.stars_rounded,
                color: widget.locked ? _lime : _gold,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.locked ? 'PREDICTIONS LOCKED' : 'POTENTIAL REWARD',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      widget.locked
                          ? '$winner · ${widget.homeScore}–${widget.awayScore} · $scorer'
                          : 'Up to 800 XP',
                      style: const TextStyle(color: _muted),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: widget.locked ? null : widget.onLock,
                style: FilledButton.styleFrom(
                  backgroundColor: _lime,
                  foregroundColor: _ink,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                ),
                child: Text(
                  widget.locked ? 'SUBMITTED' : 'LOCK PICKS',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _LeaguePage extends StatefulWidget {
  const _LeaguePage();
  @override
  State<_LeaguePage> createState() => _LeaguePageState();
}

class _LeaguePageState extends State<_LeaguePage> {
  int tab = 0;
  final fans = const [
    ('NoraGOAT', '🇸🇪', 'RMA', '12,940'),
    ('CuleKing', '🇪🇸', 'BAR', '12,610'),
    ('Yousef10', '🇦🇪', 'BAR', '11,884'),
    ('Madridista', '🇲🇦', 'RMA', '11,720'),
    ('Ahmed Karim', '🇸🇦', 'BAR', '8,420'),
    ('LeoFan', '🇦🇷', 'BAR', '8,260'),
  ];
  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: 'Global competition',
    title: 'Community',
    child: Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('SEASON')),
              ButtonSegment(value: 1, label: Text('MONTHLY')),
              ButtonSegment(value: 2, label: Text('ALL TIME')),
            ],
            selected: {tab},
            onSelectionChanged: (v) => setState(() => tab = v.first),
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, box) => box.maxWidth > 760
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: _Leaderboard(fans: fans)),
                    const SizedBox(width: 18),
                    const Expanded(flex: 3, child: _FanWarFull()),
                  ],
                )
              : Column(
                  children: [
                    _Leaderboard(fans: fans),
                    const SizedBox(height: 18),
                    const _FanWarFull(),
                  ],
                ),
        ),
      ],
    ),
  );
}

class _Leaderboard extends StatelessWidget {
  const _Leaderboard({required this.fans});
  final List<(String, String, String, String)> fans;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const _SectionTitle(title: 'Top fans', action: '18,492 PLAYERS'),
          const SizedBox(height: 12),
          ...List.generate(fans.length, (i) {
            final f = fans[i];
            final mine = f.$1 == 'Ahmed Karim';
            return InkWell(
              onTap: () => showDialog<void>(
                context: context,
                builder: (context) => _PublicFanDialog(fan: f),
              ),
              borderRadius: BorderRadius.circular(13),
              child: Container(
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: mine ? _lime.withValues(alpha: .1) : _surface2,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: mine ? _lime : _line),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 30,
                      child: Text(
                        i < 3
                            ? ['🥇', '🥈', '🥉'][i]
                            : '#${i == 4 ? 342 : i + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _TeamCrest(
                      label: f.$3,
                      colors: f.$3 == 'BAR'
                          ? const [_blue, _red]
                          : const [Colors.white, Color(0xFFCBCBD4)],
                      size: 34,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${f.$2}  ${f.$1}',
                        style: TextStyle(
                          fontWeight: mine ? FontWeight.w900 : FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      f.$3,
                      style: TextStyle(
                        color: f.$3 == 'BAR' ? _blue : Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '${f.$4} XP',
                      style: const TextStyle(
                        color: _lime,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    ),
  );
}

class _FanWarFull extends StatelessWidget {
  const _FanWarFull();
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text(
                'BARÇA vs MADRID',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              Spacer(),
              _LiveDot(text: 'LIVE'),
            ],
          ),
          const SizedBox(height: 22),
          Center(
            child: SizedBox(
              width: 190,
              height: 190,
              child: CustomPaint(
                painter: _WarRingPainter(),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('51.8%', style: _display(36)),
                    const Text(
                      'BARÇA LEADS',
                      style: TextStyle(
                        color: _blue,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          const Row(
            children: [
              Expanded(
                child: _Metric(value: '8.42M', label: 'BARÇA XP', color: _blue),
              ),
              Expanded(
                child: _Metric(
                  value: '7.84M',
                  label: 'MADRID XP',
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Your contribution',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 6),
          const Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: .72,
                  minHeight: 7,
                  backgroundColor: _line,
                  color: _lime,
                ),
              ),
              SizedBox(width: 12),
              Text('8,420 XP', style: TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ChallengesPage extends StatelessWidget {
  const _ChallengesPage();
  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: 'Earn more. Rise faster.',
    title: 'Challenges',
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              colors: [Color(0xFF2B1419), _surface],
            ),
            border: Border.all(color: _red.withValues(alpha: .4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.play_circle_fill_rounded, color: _red, size: 52),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'FEATURED · VIDEO CHALLENGE',
                      style: TextStyle(
                        color: _red,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text('Find the hidden phrase', style: _display(27)),
                    const Text(
                      'Watch the latest episode and submit the secret phrase before Friday.',
                      style: TextStyle(color: _muted),
                    ),
                  ],
                ),
              ),
              const _RewardChip(text: '+250 XP'),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const _ResponsiveGrid(
          children: [
            _ChallengeCard(
              icon: Icons.psychology_alt_rounded,
              color: _blue,
              title: 'El Clásico IQ',
              detail: '10 question football quiz',
              reward: '400 XP',
              progress: .4,
            ),
            _ChallengeCard(
              icon: Icons.sports_soccer_rounded,
              color: _lime,
              title: 'Perfect Predictor',
              detail: 'Complete all five match picks',
              reward: '300 XP',
              progress: .8,
            ),
            _ChallengeCard(
              icon: Icons.groups_rounded,
              color: _gold,
              title: 'Back Your Club',
              detail: 'Contribute 1,000 Fan War XP',
              reward: '200 XP',
              progress: .62,
            ),
            _ChallengeCard(
              icon: Icons.local_fire_department_rounded,
              color: _red,
              title: 'Seven-Day Heat',
              detail: 'Maintain a 7-day activity streak',
              reward: '350 XP',
              progress: 1,
            ),
          ],
        ),
      ],
    ),
  );
}

class _ProfilePage extends StatelessWidget {
  const _ProfilePage();
  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: 'Member since 2024',
    title: 'Ahmed Karim',
    child: LayoutBuilder(
      builder: (context, box) {
        final profile = Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 42,
                      backgroundColor: _lime,
                      foregroundColor: _ink,
                      child: Text(
                        'AK',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('@ahmed.legend', style: _display(22)),
                    const Text(
                      '🇸🇦  Barcelona Supporter',
                      style: TextStyle(color: _muted),
                    ),
                    const SizedBox(height: 18),
                    const Row(
                      children: [
                        Expanded(
                          child: _Metric(
                            value: '#342',
                            label: 'RANK',
                            color: _lime,
                          ),
                        ),
                        Expanded(
                          child: _Metric(
                            value: '68%',
                            label: 'ACCURACY',
                            color: _gold,
                          ),
                        ),
                        Expanded(
                          child: _Metric(
                            value: '12',
                            label: 'STREAK',
                            color: _red,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.stars_rounded, color: _gold),
                        SizedBox(width: 9),
                        Text(
                          'LOYALTY WALLET',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Spacer(),
                        Text(
                          '2,480',
                          style: TextStyle(
                            color: _gold,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: null,
                        child: Text('EXPLORE REWARDS'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
        final detail = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(
              title: 'Achievement cabinet',
              action: '12 / 20',
            ),
            const SizedBox(height: 12),
            const _ResponsiveGrid(
              minWidth: 160,
              children: [
                _Badge(
                  icon: '🎯',
                  title: 'Sharp Shooter',
                  detail: '10 correct scores',
                ),
                _Badge(icon: '🔥', title: 'On Fire', detail: '10 day streak'),
                _Badge(icon: '👑', title: 'Top 500', detail: 'Season rank'),
                _Badge(icon: '⚔️', title: 'Fan Warrior', detail: '5K club XP'),
              ],
            ),
            const SizedBox(height: 24),
            const _SectionTitle(
              title: 'Recent activity',
              action: 'VIEW HISTORY',
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: const [
                  _Activity(
                    icon: Icons.check_circle_rounded,
                    color: _lime,
                    title: 'Prediction won',
                    detail: 'Barcelona vs Sevilla',
                    value: '+300 XP',
                  ),
                  Divider(height: 1, color: _line),
                  _Activity(
                    icon: Icons.bolt_rounded,
                    color: _gold,
                    title: 'Challenge complete',
                    detail: 'Matchday knowledge',
                    value: '+180 XP',
                  ),
                  Divider(height: 1, color: _line),
                  _Activity(
                    icon: Icons.card_giftcard_rounded,
                    color: _blue,
                    title: 'Reward redeemed',
                    detail: 'Creator wallpaper pack',
                    value: '−600 LP',
                  ),
                ],
              ),
            ),
          ],
        );
        return box.maxWidth > 800
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 350, child: profile),
                  const SizedBox(width: 20),
                  Expanded(child: detail),
                ],
              )
            : Column(children: [profile, const SizedBox(height: 24), detail]);
      },
    ),
  );
}

class _MatchResultPage extends StatelessWidget {
  const _MatchResultPage();

  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: 'Full time · Matchday rewards resolved',
    title: 'Match result',
    child: Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                const _LiveDot(text: 'FINAL'),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: _Club(
                        label: 'Barcelona',
                        code: 'BAR',
                        colors: [_blue, _red],
                      ),
                    ),
                    Text('3 — 1', style: _display(56)),
                    const Expanded(
                      child: _Club(
                        label: 'Real Madrid',
                        code: 'RMA',
                        colors: [Colors.white, Color(0xFFCBCBD4)],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Yamal 18′  ·  Lewandowski 54′  ·  Raphinha 79′',
                  style: TextStyle(color: _muted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        const _ResponsiveGrid(
          children: [
            _ResultTile(
              title: 'Match winner',
              pick: 'Barcelona',
              result: 'Correct',
              xp: '+100 XP',
              correct: true,
            ),
            _ResultTile(
              title: 'Correct score',
              pick: '2 — 1',
              result: 'Result: 3 — 1',
              xp: '+0 XP',
              correct: false,
            ),
            _ResultTile(
              title: 'First scorer',
              pick: 'Lamine Yamal',
              result: 'Correct',
              xp: '+250 XP',
              correct: true,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Row(
              children: [
                const Icon(Icons.celebration_rounded, color: _gold, size: 38),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Great matchday, Ahmed!', style: _display(23)),
                      const Text(
                        '2 of 3 predictions correct · You climbed 18 places.',
                        style: TextStyle(color: _muted),
                      ),
                    ],
                  ),
                ),
                Text('+350 XP', style: _display(27, color: _lime)),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _StreakPage extends StatelessWidget {
  const _StreakPage();
  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: 'Consistency creates legends',
    title: '12 day streak',
    child: LayoutBuilder(
      builder: (context, box) {
        final calendar = Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle(
                  title: 'August activity',
                  action: '12 ACTIVE DAYS',
                ),
                const SizedBox(height: 18),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 7,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: List.generate(28, (i) {
                    final active = i < 12;
                    final today = i == 12;
                    return Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active ? _red.withValues(alpha: .16) : _surface2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: today
                              ? _lime
                              : active
                              ? _red
                              : _line,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            active
                                ? Icons.local_fire_department_rounded
                                : Icons.circle_outlined,
                            size: 16,
                            color: active ? _red : _muted,
                          ),
                          Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: today ? _lime : Colors.white,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        );
        final milestones = Column(
          children: const [
            _Milestone(days: 7, reward: '150 XP', done: true),
            SizedBox(height: 10),
            _Milestone(days: 14, reward: '300 XP', done: false),
            SizedBox(height: 10),
            _Milestone(days: 30, reward: 'Legend Flame badge', done: false),
          ],
        );
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _red.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _red.withValues(alpha: .35)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: _red),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your streak is at risk. Complete one action before midnight.',
                    ),
                  ),
                  _RewardChip(text: '04:21:18 LEFT'),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (box.maxWidth > 780)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: calendar),
                  const SizedBox(width: 18),
                  Expanded(flex: 3, child: milestones),
                ],
              )
            else ...[
              calendar,
              const SizedBox(height: 18),
              milestones,
            ],
          ],
        );
      },
    ),
  );
}

class _AchievementsPage extends StatefulWidget {
  const _AchievementsPage();
  @override
  State<_AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends State<_AchievementsPage> {
  int category = 0;
  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: '12 unlocked · 8 in progress',
    title: 'Achievements',
    child: Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('ALL')),
              ButtonSegment(value: 1, label: Text('PREDICTIONS')),
              ButtonSegment(value: 2, label: Text('STREAKS')),
              ButtonSegment(value: 3, label: Text('SECRET')),
            ],
            selected: {category},
            onSelectionChanged: (v) => setState(() => category = v.first),
          ),
        ),
        const SizedBox(height: 18),
        const _ResponsiveGrid(
          minWidth: 220,
          children: [
            _AchievementCard(
              icon: '🎯',
              title: 'Sharp Shooter',
              detail: 'Predict 10 exact scores',
              progress: .8,
              reward: '500 XP',
            ),
            _AchievementCard(
              icon: '🔥',
              title: 'On Fire',
              detail: 'Reach a 14 day streak',
              progress: .86,
              reward: '300 XP',
            ),
            _AchievementCard(
              icon: '👑',
              title: 'Elite Company',
              detail: 'Finish inside the top 500',
              progress: 1,
              reward: 'Unlocked',
            ),
            _AchievementCard(
              icon: '⚔️',
              title: 'Fan Warrior',
              detail: 'Contribute 10K XP to your club',
              progress: .64,
              reward: '450 XP',
            ),
            _AchievementCard(
              icon: '🔐',
              title: 'Hidden Legend',
              detail: 'Keep playing to discover this',
              progress: 0,
              reward: 'Secret',
            ),
            _AchievementCard(
              icon: '🧠',
              title: 'Football Brain',
              detail: 'Complete 20 knowledge quizzes',
              progress: .55,
              reward: '600 XP',
            ),
          ],
        ),
      ],
    ),
  );
}

class _LevelsPage extends StatelessWidget {
  const _LevelsPage();
  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: 'Your path to greatness',
    title: 'Levels & perks',
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF182313), _surface],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _lime.withValues(alpha: .35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Text(
                    'CURRENT LEVEL',
                    style: TextStyle(
                      color: _lime,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                  Spacer(),
                  Text(
                    '1,580 XP TO LEVEL 19',
                    style: TextStyle(color: _muted, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('18 — ULTRA', style: _display(42)),
              const SizedBox(height: 12),
              const LinearProgressIndicator(
                value: .842,
                minHeight: 9,
                backgroundColor: _line,
                color: _lime,
              ),
              const SizedBox(height: 15),
              const Text(
                'Next unlock: Animated profile border and 1.2× daily loyalty bonus',
                style: TextStyle(color: _muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const _ResponsiveGrid(
          minWidth: 210,
          children: [
            _LevelCard(
              level: '1–5',
              name: 'ROOKIE',
              icon: '⚽',
              detail: 'Predictions and basic challenges',
              active: false,
            ),
            _LevelCard(
              level: '6–12',
              name: 'FAN',
              icon: '📣',
              detail: 'Fan War and weekly leagues',
              active: false,
            ),
            _LevelCard(
              level: '13–20',
              name: 'ULTRA',
              icon: '🔥',
              detail: 'Bonus rewards and profile flair',
              active: true,
            ),
            _LevelCard(
              level: '21–29',
              name: 'LEGEND',
              icon: '👑',
              detail: 'Exclusive challenges and drops',
              active: false,
            ),
            _LevelCard(
              level: '30',
              name: 'GOAT',
              icon: '🐐',
              detail: 'Ultimate status and permanent badge',
              active: false,
            ),
          ],
        ),
      ],
    ),
  );
}

class _LoyaltyPage extends StatefulWidget {
  const _LoyaltyPage();
  @override
  State<_LoyaltyPage> createState() => _LoyaltyPageState();
}

class _LoyaltyPageState extends State<_LoyaltyPage> {
  int balance = 2480;
  void redeem(String reward, int cost) {
    if (balance < cost) return;
    setState(() => balance -= cost);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$reward redeemed — check your rewards history.')),
    );
  }

  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: 'Your loyalty balance',
    title: '$balance points',
    child: Column(
      children: [
        const _SectionTitle(
          title: 'Reward store',
          action: 'DIGITAL · EXPERIENCES · MERCH',
        ),
        const SizedBox(height: 12),
        _ResponsiveGrid(
          children: [
            _RewardCard(
              icon: Icons.wallpaper_rounded,
              title: 'Creator wallpaper pack',
              cost: 600,
              available: true,
              onRedeem: () => redeem('Wallpaper pack', 600),
            ),
            _RewardCard(
              icon: Icons.discount_rounded,
              title: '15% merch discount',
              cost: 1200,
              available: true,
              onRedeem: () => redeem('Merch discount', 1200),
            ),
            _RewardCard(
              icon: Icons.video_call_rounded,
              title: 'Live watch-along seat',
              cost: 3000,
              available: false,
              onRedeem: () {},
            ),
            _RewardCard(
              icon: Icons.checkroom_rounded,
              title: 'Signed club shirt draw',
              cost: 5000,
              available: false,
              onRedeem: () {},
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _SectionTitle(title: 'Redemption history', action: '2 REWARDS'),
        const SizedBox(height: 12),
        const Card(
          child: Column(
            children: [
              _Activity(
                icon: Icons.check_circle_rounded,
                color: _lime,
                title: 'Matchday wallpaper pack',
                detail: 'Redeemed 2 August',
                value: '−600 LP',
              ),
              Divider(height: 1, color: _line),
              _Activity(
                icon: Icons.check_circle_rounded,
                color: _lime,
                title: 'Digital badge bundle',
                detail: 'Redeemed 18 July',
                value: '−400 LP',
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _NotificationsPage extends StatefulWidget {
  const _NotificationsPage();
  @override
  State<_NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<_NotificationsPage> {
  bool unreadOnly = false;
  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: 'Stay in the game',
    title: 'Notifications',
    child: Column(
      children: [
        Row(
          children: [
            FilterChip(
              label: const Text('Unread only'),
              selected: unreadOnly,
              onSelected: (v) => setState(() => unreadOnly = v),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => setState(() => unreadOnly = false),
              icon: const Icon(Icons.done_all_rounded),
              label: const Text('MARK ALL READ'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              const _Notice(
                icon: Icons.alarm_rounded,
                color: _red,
                title: 'Predictions close soon',
                detail: 'El Clásico locks in 2 hours',
                time: '8 min',
                unread: true,
              ),
              const Divider(height: 1, color: _line),
              const _Notice(
                icon: Icons.emoji_events_rounded,
                color: _gold,
                title: 'Achievement nearly unlocked',
                detail: 'Two more correct predictions for Sharp Shooter',
                time: '1 hr',
                unread: true,
              ),
              if (!unreadOnly) ...const [
                Divider(height: 1, color: _line),
                _Notice(
                  icon: Icons.trending_up_rounded,
                  color: _lime,
                  title: 'You climbed 18 places',
                  detail: 'Your new season rank is #342',
                  time: 'Yesterday',
                  unread: false,
                ),
                Divider(height: 1, color: _line),
                _Notice(
                  icon: Icons.card_giftcard_rounded,
                  color: _blue,
                  title: 'New reward available',
                  detail: 'The creator wallpaper pack is live',
                  time: '2 days',
                  unread: false,
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _ActivityPage extends StatelessWidget {
  const _ActivityPage();
  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: 'Every point accounted for',
    title: 'Activity history',
    child: Column(
      children: [
        const _ResponsiveGrid(
          children: [
            _SummaryCard(
              label: 'XP EARNED',
              value: '+1,840',
              detail: 'Last 30 days',
              color: _lime,
            ),
            _SummaryCard(
              label: 'LOYALTY EARNED',
              value: '+920',
              detail: 'Last 30 days',
              color: _gold,
            ),
            _SummaryCard(
              label: 'PREDICTIONS',
              value: '17',
              detail: '68% correct',
              color: _blue,
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Card(
          child: Column(
            children: [
              _Activity(
                icon: Icons.sports_soccer_rounded,
                color: _lime,
                title: 'Correct first scorer',
                detail: 'Barcelona vs Sevilla · Prediction',
                value: '+250 XP',
              ),
              Divider(height: 1, color: _line),
              _Activity(
                icon: Icons.psychology_alt_rounded,
                color: _gold,
                title: 'El Clásico IQ',
                detail: 'Knowledge challenge',
                value: '+400 XP',
              ),
              Divider(height: 1, color: _line),
              _Activity(
                icon: Icons.card_giftcard_rounded,
                color: _blue,
                title: 'Wallpaper pack',
                detail: 'Loyalty redemption',
                value: '−600 LP',
              ),
              Divider(height: 1, color: _line),
              _Activity(
                icon: Icons.local_fire_department_rounded,
                color: _red,
                title: '10 day milestone',
                detail: 'Streak reward',
                value: '+300 XP',
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SettingsPage extends StatefulWidget {
  const _SettingsPage();
  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  bool matchAlerts = true, streakAlerts = true, rewardAlerts = false;
  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: 'Make it yours',
    title: 'Settings',
    child: LayoutBuilder(
      builder: (context, box) {
        final account = Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle(title: 'Account & team', action: 'EDIT'),
                const SizedBox(height: 16),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _TeamCrest(label: 'BAR', colors: [_blue, _red]),
                  title: Text('Barcelona'),
                  subtitle: Text(
                    'Your Fan War team · Change available next season',
                  ),
                ),
                const Divider(color: _line),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.language_rounded),
                  title: Text('Language'),
                  trailing: Text('English', style: TextStyle(color: _muted)),
                ),
              ],
            ),
          ),
        );
        final alerts = Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle(title: 'Notifications', action: ''),
                _PremiumToggleTile(
                  title: const Text('Match reminders'),
                  subtitle: const Text('Before predictions lock'),
                  value: matchAlerts,
                  onChanged: (v) => setState(() => matchAlerts = v),
                ),
                _PremiumToggleTile(
                  title: const Text('Streak alerts'),
                  subtitle: const Text('When your streak is at risk'),
                  value: streakAlerts,
                  onChanged: (v) => setState(() => streakAlerts = v),
                ),
                _PremiumToggleTile(
                  title: const Text('New rewards'),
                  subtitle: const Text('Store drops and creator exclusives'),
                  value: rewardAlerts,
                  onChanged: (v) => setState(() => rewardAlerts = v),
                ),
              ],
            ),
          ),
        );
        return box.maxWidth > 760
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: account),
                  const SizedBox(width: 18),
                  Expanded(child: alerts),
                ],
              )
            : Column(children: [account, const SizedBox(height: 18), alerts]);
      },
    ),
  );
}

class _DemoModePage extends StatefulWidget {
  const _DemoModePage();
  @override
  State<_DemoModePage> createState() => _DemoModePageState();
}

class _DemoModePageState extends State<_DemoModePage> {
  int active = 0;
  final scenarios = const [
    (
      'Normal season',
      'Balanced user data and upcoming fixtures',
      Icons.calendar_month_rounded,
    ),
    (
      'El Clásico live',
      'Fan War surge and live match activity',
      Icons.sports_soccer_rounded,
    ),
    (
      'Reward moment',
      'Achievement, level-up and loyalty animations',
      Icons.celebration_rounded,
    ),
    (
      'Admin incident',
      'Suspicious activity requiring moderation',
      Icons.shield_rounded,
    ),
  ];
  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: 'Client presentation controls',
    title: 'Demo mode',
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _gold.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _gold.withValues(alpha: .3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: _gold),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Choose a scenario to instantly reshape the mock data shown across the demo. No backend or real user data is involved.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _ResponsiveGrid(
          children: List.generate(scenarios.length, (i) {
            final s = scenarios[i];
            return Card(
              child: InkWell(
                onTap: () => setState(() => active = i),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            s.$3,
                            color: active == i ? _lime : _muted,
                            size: 30,
                          ),
                          const Spacer(),
                          Icon(
                            active == i
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_off_rounded,
                            color: active == i ? _lime : _muted,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(s.$1, style: _display(21)),
                      const SizedBox(height: 5),
                      Text(
                        s.$2,
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${scenarios[active].$1} scenario activated'),
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _lime,
              foregroundColor: _ink,
              padding: const EdgeInsets.all(17),
            ),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text(
              'ACTIVATE SCENARIO',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    ),
  );
}

class _AdminConsolePage extends StatefulWidget {
  const _AdminConsolePage();
  @override
  State<_AdminConsolePage> createState() => _AdminConsolePageState();
}

class _AdminConsolePageState extends State<_AdminConsolePage> {
  int section = 0;
  final sections = const [
    'Overview',
    'Matches',
    'Predictions',
    'Challenges',
    'Users',
    'Suspicious',
    'Rewards',
    'Achievements',
    'Leaderboards',
    'Points',
    'Statistics',
    'Settings',
  ];

  Future<void> _openEditor() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => _AdminEditorDialog(section: sections[section]),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${sections[section]} demo record created')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: 'Community operations',
    title: 'Admin console',
    child: Column(
      children: [
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: sections.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => ChoiceChip(
              label: Text(sections[i]),
              selected: section == i,
              onSelected: (_) => setState(() => section = i),
            ),
          ),
        ),
        const SizedBox(height: 18),
        const _ResponsiveGrid(
          children: [
            _SummaryCard(
              label: 'ACTIVE USERS',
              value: '18,492',
              detail: '+12.4% this month',
              color: _lime,
            ),
            _SummaryCard(
              label: 'PREDICTIONS',
              value: '84,210',
              detail: '72% resolved',
              color: _blue,
            ),
            _SummaryCard(
              label: 'XP AWARDED',
              value: '12.8M',
              detail: 'Across all activities',
              color: _gold,
            ),
            _SummaryCard(
              label: 'FLAGGED EVENTS',
              value: '12',
              detail: '3 require review',
              color: _red,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(sections[section], style: _display(24)),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _openEditor,
                      icon: const Icon(Icons.add_rounded),
                      label: Text('NEW ${sections[section].toUpperCase()}'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const _AdminRow(
                  name: 'El Clásico · Barcelona vs Real Madrid',
                  status: 'Predictions open',
                  metric: '14,820 entries',
                ),
                const Divider(color: _line),
                const _AdminRow(
                  name: 'Hidden phrase · Episode 42',
                  status: 'Active',
                  metric: '4,112 entries',
                ),
                const Divider(color: _line),
                const _AdminRow(
                  name: 'Unusual points velocity · user #1842',
                  status: 'Review',
                  metric: 'Risk 86%',
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.title,
    required this.pick,
    required this.result,
    required this.xp,
    required this.correct,
  });
  final String title, pick, result, xp;
  final bool correct;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: correct ? _lime : _red,
          ),
          const SizedBox(height: 14),
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: _muted,
              fontWeight: FontWeight.w800,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 5),
          Text(pick, style: _display(21)),
          Text(
            result,
            style: TextStyle(color: correct ? _lime : _red, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Text(
            xp,
            style: const TextStyle(color: _gold, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    ),
  );
}

class _Milestone extends StatelessWidget {
  const _Milestone({
    required this.days,
    required this.reward,
    required this.done,
  });
  final int days;
  final String reward;
  final bool done;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(17),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: done ? _lime : _surface2,
            foregroundColor: done ? _ink : _muted,
            child: Icon(
              done ? Icons.check_rounded : Icons.local_fire_department_rounded,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$days DAY MILESTONE',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(reward, style: const TextStyle(color: _muted)),
              ],
            ),
          ),
          if (!done)
            Text(
              '${days - 12} DAYS',
              style: const TextStyle(
                color: _gold,
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
        ],
      ),
    ),
  );
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.progress,
    required this.reward,
  });
  final String icon, title, detail, reward;
  final double progress;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(19),
      child: Column(
        children: [
          Text(
            icon,
            style: TextStyle(
              fontSize: 38,
              color: progress == 0 ? _muted : null,
            ),
          ),
          const SizedBox(height: 9),
          Text(title, style: _display(20)),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 11),
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: _line,
            color: progress == 1 ? _gold : _lime,
          ),
          const SizedBox(height: 7),
          Text(
            reward,
            style: TextStyle(
              color: progress == 1 ? _gold : _muted,
              fontWeight: FontWeight.w900,
              fontSize: 10,
            ),
          ),
        ],
      ),
    ),
  );
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({
    required this.level,
    required this.name,
    required this.icon,
    required this.detail,
    required this.active,
  });
  final String level, name, icon, detail;
  final bool active;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(19),
    decoration: BoxDecoration(
      color: active ? _lime.withValues(alpha: .1) : _surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: active ? _lime : _line),
    ),
    child: Column(
      children: [
        Text(icon, style: const TextStyle(fontSize: 34)),
        const SizedBox(height: 10),
        Text(
          'LEVEL $level',
          style: const TextStyle(
            color: _muted,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(name, style: _display(23, color: active ? _lime : Colors.white)),
        const SizedBox(height: 5),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, fontSize: 11),
        ),
      ],
    ),
  );
}

class _RewardCard extends StatelessWidget {
  const _RewardCard({
    required this.icon,
    required this.title,
    required this.cost,
    required this.available,
    required this.onRedeem,
  });
  final IconData icon;
  final String title;
  final int cost;
  final bool available;
  final VoidCallback onRedeem;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(19),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: _gold, size: 30),
          ),
          const SizedBox(height: 18),
          Text(title, style: _display(20)),
          const SizedBox(height: 6),
          Text(
            '$cost LOYALTY POINTS',
            style: const TextStyle(
              color: _gold,
              fontWeight: FontWeight.w900,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: available ? onRedeem : null,
              child: Text(available ? 'REDEEM' : 'KEEP EARNING'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.time,
    required this.unread,
  });
  final IconData icon;
  final Color color;
  final String title, detail, time;
  final bool unread;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
    leading: CircleAvatar(
      backgroundColor: color.withValues(alpha: .12),
      child: Icon(icon, color: color),
    ),
    title: Text(
      title,
      style: TextStyle(fontWeight: unread ? FontWeight.w900 : FontWeight.w600),
    ),
    subtitle: Text(detail),
    trailing: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(time, style: const TextStyle(color: _muted, fontSize: 10)),
        if (unread)
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: CircleAvatar(radius: 4, backgroundColor: _lime),
          ),
      ],
    ),
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
  });
  final String label, value, detail;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _muted,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 9),
          Text(value, style: _display(31, color: color)),
          Text(detail, style: const TextStyle(color: _muted, fontSize: 11)),
        ],
      ),
    ),
  );
}

class _AdminRow extends StatelessWidget {
  const _AdminRow({
    required this.name,
    required this.status,
    required this.metric,
  });
  final String name, status, metric;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 13),
    child: Row(
      children: [
        const CircleAvatar(
          backgroundColor: _surface2,
          child: Icon(Icons.chevron_right_rounded, color: _lime),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        _RewardChip(text: status),
        const SizedBox(width: 18),
        Text(metric, style: const TextStyle(color: _muted)),
      ],
    ),
  );
}

class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({required this.children, this.minWidth = 260});
  final List<Widget> children;
  final double minWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final count = math.max(1, (box.maxWidth / minWidth).floor());
      final width = (box.maxWidth - (count - 1) * 12) / count;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: children
            .map((e) => SizedBox(width: width, child: e))
            .toList(),
      );
    },
  );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.color,
    required this.tag,
    required this.title,
    required this.detail,
    required this.progress,
  });
  final IconData icon;
  final Color color;
  final String tag, title, detail;
  final double progress;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 20),
          Text(
            tag,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(title, style: _display(19)),
          const SizedBox(height: 4),
          Text(detail, style: const TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(height: 15),
          LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            backgroundColor: _line,
            color: color,
          ),
        ],
      ),
    ),
  );
}

class _LatestVideoCard extends StatelessWidget {
  const _LatestVideoCard();

  Future<void> _watch() async {
    await launchUrl(
      Uri.parse(_latestVideoUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: _watch,
    borderRadius: BorderRadius.circular(26),
    child: Container(
      height: 310,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: .14)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/latest_abu3meer.jpg', fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xEE080B10)],
              ),
            ),
          ),
          Positioned(
            top: 18,
            left: 18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _red,
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Text(
                'LATEST FROM ABU 3MEER',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          Center(
            child: SizedBox(
              width: 188,
              height: 62,
              child: Lottie.asset(
                'assets/animations/youtube.json',
                repeat: true,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.play_circle_fill_rounded,
                  color: _red,
                  size: 62,
                ),
              ),
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            bottom: 20,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'NEW VIDEO · ABU 3MEER',
                        style: TextStyle(
                          color: _lime,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _latestVideoTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _display(22, height: 1.1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                FilledButton.icon(
                  onPressed: _watch,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('WATCH NOW'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _PremiumToggleTile extends StatelessWidget {
  const _PremiumToggleTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Widget title;
  final Widget subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: title,
    subtitle: subtitle,
    trailing: _AnimatedToggle(value: value, onChanged: onChanged),
    onTap: onChanged == null ? null : () => onChanged!(!value),
  );
}

class _AnimatedToggle extends StatefulWidget {
  const _AnimatedToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  State<_AnimatedToggle> createState() => _AnimatedToggleState();
}

class _AnimatedToggleState extends State<_AnimatedToggle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _controller.value = widget.value ? 1 : 0;
  }

  @override
  void didUpdateWidget(covariant _AnimatedToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      widget.value ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    toggled: widget.value,
    button: true,
    child: InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: widget.onChanged == null
          ? null
          : () => widget.onChanged!(!widget.value),
      child: SizedBox(
        width: 58,
        height: 42,
        child: Lottie.asset(
          'assets/animations/toggle.json',
          controller: _controller,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              Switch(value: widget.value, onChanged: widget.onChanged),
        ),
      ),
    ),
  );
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.reward,
    required this.progress,
  });
  final IconData icon;
  final Color color;
  final String title, detail, reward;
  final double progress;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(19),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const Spacer(),
              _RewardChip(text: reward),
            ],
          ),
          const SizedBox(height: 18),
          Text(title, style: _display(21)),
          const SizedBox(height: 5),
          Text(detail, style: const TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(height: 18),
          LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: _line,
            color: color,
          ),
          const SizedBox(height: 7),
          Text(
            progress == 1
                ? 'COMPLETED'
                : '${(progress * 100).round()}% COMPLETE',
            style: TextStyle(
              color: progress == 1 ? _lime : _muted,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    ),
  );
}

class _PredictionCard extends StatelessWidget {
  const _PredictionCard({
    required this.title,
    required this.xp,
    required this.child,
  });
  final String title;
  final int xp;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              _RewardChip(text: '+$xp XP'),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    ),
  );
}

class _ScorePicker extends StatelessWidget {
  const _ScorePicker({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int>? onChanged;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      IconButton(
        onPressed: onChanged == null
            ? null
            : () => onChanged!(math.min(9, value + 1)),
        icon: const Icon(Icons.keyboard_arrow_up),
      ),
      Text('$value', style: _display(48)),
      IconButton(
        onPressed: onChanged == null || value == 0
            ? null
            : () => onChanged!(value - 1),
        icon: const Icon(Icons.keyboard_arrow_down),
      ),
    ],
  );
}

class _Club extends StatelessWidget {
  const _Club({required this.label, required this.code, required this.colors});
  final String label, code;
  final List<Color> colors;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      _TeamCrest(label: code, colors: colors, size: 58),
      const SizedBox(height: 10),
      Text(label, textAlign: TextAlign.center, style: _display(18)),
    ],
  );
}

class _TeamCrest extends StatelessWidget {
  const _TeamCrest({required this.label, required this.colors, this.size = 46});
  final String label;
  final List<Color> colors;
  final double size;
  @override
  Widget build(BuildContext context) =>
      _FallbackCrest(label: label, colors: colors, size: size);
}

class _FallbackCrest extends StatelessWidget {
  const _FallbackCrest({
    required this.label,
    required this.colors,
    required this.size,
  });
  final String label;
  final List<Color> colors;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(colors: colors),
      border: Border.all(color: Colors.white24, width: 2),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: colors.first == Colors.white ? _ink : Colors.white,
        fontWeight: FontWeight.w900,
        fontSize: size * .25,
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.value,
    required this.label,
    required this.color,
  });
  final String value, label;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value, style: _display(22, color: color)),
      const SizedBox(height: 3),
      Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: _muted,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: .8,
        ),
      ),
    ],
  );
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.text,
    required this.color,
    this.compact = false,
    this.onTap,
  });
  final IconData icon;
  final String text;
  final Color color;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 6 : 7,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 13 : 14, color: color),
          SizedBox(width: compact ? 4 : 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: body,
        ),
      );
    }
    return body;
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final primary = _productionPrimary(context);
    final muted = _productionMuted(context);
    return Material(
      color: selected ? primary.withValues(alpha: .11) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
          child: Row(
            children: [
              Icon(icon, color: selected ? primary : muted, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? (_isDarkTheme(context) ? Colors.white : primary)
                        : muted,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.action});
  final String title, action;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(title, style: _display(21)),
      const Spacer(),
      Text(
        action,
        style: const TextStyle(
          color: _muted,
          fontWeight: FontWeight.w800,
          fontSize: 10,
          letterSpacing: 1,
        ),
      ),
    ],
  );
}

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final primary = _productionPrimary(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          CircleAvatar(radius: 3, backgroundColor: primary),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: primary,
              fontWeight: FontWeight.w900,
              fontSize: 9,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _RewardChip extends StatelessWidget {
  const _RewardChip({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: _gold.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: _gold,
        fontWeight: FontWeight.w900,
        fontSize: 10,
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.title, required this.detail});
  final String icon, title, detail;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 34)),
          const SizedBox(height: 9),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 10),
          ),
        ],
      ),
    ),
  );
}

class _Activity extends StatelessWidget {
  const _Activity({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.value,
  });
  final IconData icon;
  final Color color;
  final String title, detail, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(detail, style: const TextStyle(color: _muted, fontSize: 11)),
            ],
          ),
        ),
        Text(
          value,
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}

class _LogoMark extends StatefulWidget {
  const _LogoMark({required this.size});
  final double size;

  @override
  State<_LogoMark> createState() => _LogoMarkState();
}

class _LogoMarkState extends State<_LogoMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void stop() {
    controller
      ..stop()
      ..value = 0;
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) {
      if (controller.duration != null) controller.repeat();
    },
    onExit: (_) => stop(),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (controller.duration != null) controller.forward(from: 0);
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _productionPrimary(context),
          borderRadius: BorderRadius.circular(widget.size * .28),
        ),
        child: Padding(
          padding: EdgeInsets.all(widget.size * .08),
          child: Lottie.asset(
            'assets/animations/ball-loading.json',
            controller: controller,
            repeat: false,
            fit: BoxFit.contain,
            onLoaded: (composition) {
              controller.duration = composition.duration;
              controller.value = 0;
            },
            errorBuilder: (_, _, _) => Icon(
              Icons.sports_soccer_rounded,
              color: _productionOnPrimary(context),
              size: widget.size * .62,
            ),
          ),
        ),
      ),
    ),
  );
}

class _PitchBackdrop extends StatelessWidget {
  const _PitchBackdrop();
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _PitchPainter());
}

class _PitchPainter extends CustomPainter {
  const _PitchPainter();
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = _lime.withValues(alpha: .035)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    c.drawCircle(Offset(s.width * .2, s.height * .2), s.width * .28, p);
    c.drawCircle(Offset(s.width * .85, s.height * .8), s.width * .35, p);
    for (double x = 0; x < s.width; x += 80) {
      c.drawLine(Offset(x, 0), Offset(x, s.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WarRingPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final r = Rect.fromLTWH(8, 8, s.width - 16, s.height - 16);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    c.drawArc(r, -math.pi / 2, math.pi * 2, false, p..color = _line);
    c.drawArc(r, -math.pi / 2, math.pi * 2 * .518, false, p..color = _blue);
    c.drawArc(
      r,
      -math.pi / 2 + math.pi * 2 * .518,
      math.pi * 2 * .482,
      false,
      p..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

TextStyle _display(
  double size, {
  Color? color,
  double height = 1,
  double spacing = -.4,
}) => GoogleFonts.barlowCondensed(
  fontSize: size,
  fontWeight: FontWeight.w800,
  color: color,
  height: height,
  letterSpacing: spacing,
);
