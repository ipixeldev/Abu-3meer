// Route definitions and navigation helpers.

/// App route paths.
class AppRoutes {
  // Auth
  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String onboardingTeam = '/onboarding/team';

  // Main app (user)
  static const String home = '/home';
  static const String matchCenter = '/match/:matchId';
  static const String predictions = '/match/:matchId/predict';
  static const String matchResult = '/match/:matchId/result';
  static const String league = '/league';
  static const String fanWar = '/fan-war';
  static const String challenges = '/challenges';
  static const String challengeDetail = '/challenges/:challengeId';
  static const String streak = '/streak';
  static const String achievements = '/achievements';
  static const String achievementDetail = '/achievements/:achievementId';
  static const String levels = '/levels';
  static const String loyalty = '/loyalty';
  static const String rewardDetail = '/loyalty/:rewardId';
  static const String profile = '/profile';
  static const String publicProfile = '/profile/:userId';
  static const String editProfile = '/profile/edit';
  static const String notifications = '/notifications';
  static const String activity = '/activity';
  static const String settings = '/settings';

  // Admin
  static const String admin = '/admin';
  static const String adminOverview = '/admin/overview';
  static const String adminMatches = '/admin/matches';
  static const String adminMatchDetail = '/admin/matches/:matchId';
  static const String adminPredictions = '/admin/predictions';
  static const String adminChallenges = '/admin/challenges';
  static const String adminChallengeDetail = '/admin/challenges/:challengeId';
  static const String adminUsers = '/admin/users';
  static const String adminUserDetail = '/admin/users/:userId';
  static const String adminSuspicious = '/admin/suspicious';
  static const String adminRewards = '/admin/rewards';
  static const String adminAchievements = '/admin/achievements';
  static const String adminLeaderboards = '/admin/leaderboards';
  static const String adminPoints = '/admin/points';
  static const String adminStatistics = '/admin/statistics';
  static const String adminSettings = '/admin/settings';

  // Special
  static const String obsOverlay = '/obs/leaderboard';
  static const String demoMode = '/demo';

  // Helper to build routes with parameters
  static String matchCenter(String matchId) => '/match/$matchId';
  static String predictions(String matchId) => '/match/$matchId/predict';
  static String matchResult(String matchId) => '/match/$matchId/result';
  static String challengeDetail(String challengeId) =>
      '/challenges/$challengeId';
  static String achievementDetail(String achievementId) =>
      '/achievements/$achievementId';
  static String publicProfile(String userId) => '/profile/$userId';
  static String rewardDetail(String rewardId) => '/loyalty/$rewardId';
  static String adminMatchDetail(String matchId) => '/admin/matches/$matchId';
  static String adminChallengeDetail(String challengeId) =>
      '/admin/challenges/$challengeId';
  static String adminUserDetail(String userId) => '/admin/users/$userId';
}

/// Navigation keys for programmatic navigation.
class NavKeys {
  static final GlobalKey<NavigatorState> rootNavigatorKey =
      GlobalKey<NavigatorState>();
  static final GlobalKey<NavigatorState> shellNavigatorKey =
      GlobalKey<NavigatorState>();
  static final GlobalKey<NavigatorState> adminShellNavigatorKey =
      GlobalKey<NavigatorState>();
}
