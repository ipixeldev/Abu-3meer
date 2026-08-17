// GoRouter configuration with all routes, guards, and nested navigation.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/provider.dart';
import 'routes.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/onboarding_team_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/match/screens/match_center_screen.dart';
import '../../features/match/screens/predictions_screen.dart';
import '../../features/match/screens/match_result_screen.dart';
import '../../features/league/screens/league_screen.dart';
import '../../features/fan_war/screens/fan_war_screen.dart';
import '../../features/challenges/screens/challenges_screen.dart';
import '../../features/challenges/screens/challenge_detail_screen.dart';
import '../../features/streak/screens/streak_screen.dart';
import '../../features/achievements/screens/achievements_screen.dart';
import '../../features/achievements/screens/achievement_detail_screen.dart';
import '../../features/levels/screens/levels_screen.dart';
import '../../features/loyalty/screens/loyalty_screen.dart';
import '../../features/loyalty/screens/reward_detail_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/public_profile_screen.dart';
import '../../features/profile/screens/edit_profile_screen.dart';
import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/activity/screens/activity_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/admin/screens/admin_shell.dart';
import '../../features/admin/screens/admin_overview_screen.dart';
import '../../features/admin/screens/admin_matches_screen.dart';
import '../../features/admin/screens/admin_match_detail_screen.dart';
import '../../features/admin/screens/admin_predictions_screen.dart';
import '../../features/admin/screens/admin_challenges_screen.dart';
import '../../features/admin/screens/admin_challenge_detail_screen.dart';
import '../../features/admin/screens/admin_users_screen.dart';
import '../../features/admin/screens/admin_user_detail_screen.dart';
import '../../features/admin/screens/admin_suspicious_screen.dart';
import '../../features/admin/screens/admin_rewards_screen.dart';
import '../../features/admin/screens/admin_achievements_screen.dart';
import '../../features/admin/screens/admin_leaderboards_screen.dart';
import '../../features/admin/screens/admin_points_screen.dart';
import '../../features/admin/screens/admin_statistics_screen.dart';
import '../../features/admin/screens/admin_settings_screen.dart';
import '../../features/obs/screens/obs_overlay_screen.dart';
import '../../features/demo/screens/demo_mode_screen.dart';
import '../../core/widgets/main_shell.dart';
import '../../core/widgets/admin_shell.dart' as admin_widget;

/// Creates the GoRouter with all routes configured.
GoRouter createRouter(AppState appState) {
  return GoRouter(
    navigatorKey: NavKeys.rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: true,
    redirect: (context, state) => _redirectGuard(context, state, appState),
    routes: [
      // ─── Splash / Auth (no shell) ─────────────────────────────
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboardingTeam,
        name: 'onboardingTeam',
        builder: (context, state) => const OnboardingTeamScreen(),
      ),

      // ─── Main App Shell (Bottom Nav / Sidebar) ────────────────
      ShellRoute(
        navigatorKey: NavKeys.shellNavigatorKey,
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          // Home / Fan Hub
          GoRoute(
            path: AppRoutes.home,
            name: 'home',
            builder: (context, state) => const HomeScreen(),
          ),

          // Match Center
          GoRoute(
            path: AppRoutes.matchCenter,
            name: 'matchCenter',
            builder: (context, state) {
              final matchId = state.pathParameters['matchId']!;
              return MatchCenterScreen(matchId: matchId);
            },
            routes: [
              // Predictions (nested under match)
              GoRoute(
                path: 'predict',
                name: 'predictions',
                builder: (context, state) {
                  final matchId = state.pathParameters['matchId']!;
                  return PredictionsScreen(matchId: matchId);
                },
              ),
              // Match Result
              GoRoute(
                path: 'result',
                name: 'matchResult',
                builder: (context, state) {
                  final matchId = state.pathParameters['matchId']!;
                  return MatchResultScreen(matchId: matchId);
                },
              ),
            ],
          ),

          // Fan League
          GoRoute(
            path: AppRoutes.league,
            name: 'league',
            builder: (context, state) => const LeagueScreen(),
          ),

          // Fan War
          GoRoute(
            path: AppRoutes.fanWar,
            name: 'fanWar',
            builder: (context, state) => const FanWarScreen(),
          ),

          // Challenges
          GoRoute(
            path: AppRoutes.challenges,
            name: 'challenges',
            builder: (context, state) => const ChallengesScreen(),
          ),
          GoRoute(
            path: AppRoutes.challengeDetail,
            name: 'challengeDetail',
            builder: (context, state) {
              final challengeId = state.pathParameters['challengeId']!;
              return ChallengeDetailScreen(challengeId: challengeId);
            },
          ),

          // Streak
          GoRoute(
            path: AppRoutes.streak,
            name: 'streak',
            builder: (context, state) => const StreakScreen(),
          ),

          // Achievements
          GoRoute(
            path: AppRoutes.achievements,
            name: 'achievements',
            builder: (context, state) => const AchievementsScreen(),
          ),
          GoRoute(
            path: AppRoutes.achievementDetail,
            name: 'achievementDetail',
            builder: (context, state) {
              final achievementId = state.pathParameters['achievementId']!;
              return AchievementDetailScreen(achievementId: achievementId);
            },
          ),

          // Levels
          GoRoute(
            path: AppRoutes.levels,
            name: 'levels',
            builder: (context, state) => const LevelsScreen(),
          ),

          // Loyalty / Rewards
          GoRoute(
            path: AppRoutes.loyalty,
            name: 'loyalty',
            builder: (context, state) => const LoyaltyScreen(),
          ),
          GoRoute(
            path: AppRoutes.rewardDetail,
            name: 'rewardDetail',
            builder: (context, state) {
              final rewardId = state.pathParameters['rewardId']!;
              return RewardDetailScreen(rewardId: rewardId);
            },
          ),

          // Profile
          GoRoute(
            path: AppRoutes.profile,
            name: 'profile',
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: AppRoutes.publicProfile,
            name: 'publicProfile',
            builder: (context, state) {
              final userId = state.pathParameters['userId']!;
              return PublicProfileScreen(userId: userId);
            },
          ),
          GoRoute(
            path: AppRoutes.editProfile,
            name: 'editProfile',
            builder: (context, state) => const EditProfileScreen(),
          ),

          // Notifications
          GoRoute(
            path: AppRoutes.notifications,
            name: 'notifications',
            builder: (context, state) => const NotificationsScreen(),
          ),

          // Activity
          GoRoute(
            path: AppRoutes.activity,
            name: 'activity',
            builder: (context, state) => const ActivityScreen(),
          ),

          // Settings
          GoRoute(
            path: AppRoutes.settings,
            name: 'settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),

      // ─── Admin Shell (Sidebar on desktop, responsive) ─────────
      ShellRoute(
        navigatorKey: NavKeys.adminShellNavigatorKey,
        builder: (context, state, child) =>
            admin_widget.AdminShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.adminOverview,
            name: 'adminOverview',
            builder: (context, state) => const AdminOverviewScreen(),
          ),
          GoRoute(
            path: AppRoutes.adminMatches,
            name: 'adminMatches',
            builder: (context, state) => const AdminMatchesScreen(),
          ),
          GoRoute(
            path: AppRoutes.adminMatchDetail,
            name: 'adminMatchDetail',
            builder: (context, state) {
              final matchId = state.pathParameters['matchId']!;
              return AdminMatchDetailScreen(matchId: matchId);
            },
          ),
          GoRoute(
            path: AppRoutes.adminPredictions,
            name: 'adminPredictions',
            builder: (context, state) => const AdminPredictionsScreen(),
          ),
          GoRoute(
            path: AppRoutes.adminChallenges,
            name: 'adminChallenges',
            builder: (context, state) => const AdminChallengesScreen(),
          ),
          GoRoute(
            path: AppRoutes.adminChallengeDetail,
            name: 'adminChallengeDetail',
            builder: (context, state) {
              final challengeId = state.pathParameters['challengeId']!;
              return AdminChallengeDetailScreen(challengeId: challengeId);
            },
          ),
          GoRoute(
            path: AppRoutes.adminUsers,
            name: 'adminUsers',
            builder: (context, state) => const AdminUsersScreen(),
          ),
          GoRoute(
            path: AppRoutes.adminUserDetail,
            name: 'adminUserDetail',
            builder: (context, state) {
              final userId = state.pathParameters['userId']!;
              return AdminUserDetailScreen(userId: userId);
            },
          ),
          GoRoute(
            path: AppRoutes.adminSuspicious,
            name: 'adminSuspicious',
            builder: (context, state) => const AdminSuspiciousScreen(),
          ),
          GoRoute(
            path: AppRoutes.adminRewards,
            name: 'adminRewards',
            builder: (context, state) => const AdminRewardsScreen(),
          ),
          GoRoute(
            path: AppRoutes.adminAchievements,
            name: 'adminAchievements',
            builder: (context, state) => const AdminAchievementsScreen(),
          ),
          GoRoute(
            path: AppRoutes.adminLeaderboards,
            name: 'adminLeaderboards',
            builder: (context, state) => const AdminLeaderboardsScreen(),
          ),
          GoRoute(
            path: AppRoutes.adminPoints,
            name: 'adminPoints',
            builder: (context, state) => const AdminPointsScreen(),
          ),
          GoRoute(
            path: AppRoutes.adminStatistics,
            name: 'adminStatistics',
            builder: (context, state) => const AdminStatisticsScreen(),
          ),
          GoRoute(
            path: AppRoutes.adminSettings,
            name: 'adminSettings',
            builder: (context, state) => const AdminSettingsScreen(),
          ),
        ],
      ),

      // ─── Special Routes (no shell) ────────────────────────────
      GoRoute(
        path: AppRoutes.obsOverlay,
        name: 'obsOverlay',
        builder: (context, state) => const ObsOverlayScreen(),
      ),
      GoRoute(
        path: AppRoutes.demoMode,
        name: 'demoMode',
        builder: (context, state) => const DemoModeScreen(),
      ),
    ],
  );
}

/// Redirect guard for authentication and admin access.
String? _redirectGuard(
  BuildContext context,
  GoRouterState state,
  AppState appState,
) {
  final location = state.uri.toString();
  final isAuthRoute =
      location.startsWith(AppRoutes.login) ||
      location.startsWith(AppRoutes.register) ||
      location.startsWith(AppRoutes.onboardingTeam) ||
      location.startsWith(AppRoutes.splash);
  final isAdminRoute = location.startsWith(AppRoutes.admin);
  final isSpecialRoute =
      location.startsWith(AppRoutes.obsOverlay) ||
      location.startsWith(AppRoutes.demoMode);

  // Allow special routes always
  if (isSpecialRoute) return null;

  // Redirect to splash if not initialized
  if (appState.isLoading) {
    return AppRoutes.splash;
  }

  // Auth routes - redirect authenticated users to home
  if (isAuthRoute && appState.isAuthenticated) {
    return AppRoutes.home;
  }

  // Protected routes - redirect to login if not authenticated
  if (!isAuthRoute && !appState.isAuthenticated && !isAdminRoute) {
    return AppRoutes.login;
  }

  // Admin routes - require admin user
  if (isAdminRoute) {
    if (!appState.isAuthenticated) {
      return AppRoutes.login;
    }
    if (appState.currentUser?.isAdmin != true) {
      return AppRoutes.home;
    }
  }

  // Onboarding - if user has no team, force team selection
  if (appState.isAuthenticated &&
      appState.currentUser != null &&
      location == AppRoutes.home) {
    // This check is now handled in the home screen itself
  }

  return null;
}

/// Navigation helper methods.
extension GoRouterExt on GoRouter {
  void goHome() => go(AppRoutes.home);
  void goLogin() => go(AppRoutes.login);
  void goRegister() => go(AppRoutes.register);
  void goOnboardingTeam() => go(AppRoutes.onboardingTeam);
  void goMatchCenter(String matchId) => go(AppRoutes.matchCenter(matchId));
  void goPredictions(String matchId) => go(AppRoutes.predictions(matchId));
  void goMatchResult(String matchId) => go(AppRoutes.matchResult(matchId));
  void goLeague() => go(AppRoutes.league);
  void goFanWar() => go(AppRoutes.fanWar);
  void goChallenges() => go(AppRoutes.challenges);
  void goChallengeDetail(String challengeId) =>
      go(AppRoutes.challengeDetail(challengeId));
  void goStreak() => go(AppRoutes.streak);
  void goAchievements() => go(AppRoutes.achievements);
  void goAchievementDetail(String achievementId) =>
      go(AppRoutes.achievementDetail(achievementId));
  void goLevels() => go(AppRoutes.levels);
  void goLoyalty() => go(AppRoutes.loyalty);
  void goRewardDetail(String rewardId) => go(AppRoutes.rewardDetail(rewardId));
  void goProfile() => go(AppRoutes.profile);
  void goPublicProfile(String userId) => go(AppRoutes.publicProfile(userId));
  void goEditProfile() => go(AppRoutes.editProfile);
  void goNotifications() => go(AppRoutes.notifications);
  void goActivity() => go(AppRoutes.activity);
  void goSettings() => go(AppRoutes.settings);
  void goAdmin() => go(AppRoutes.adminOverview);
  void goAdminOverview() => go(AppRoutes.adminOverview);
  void goAdminMatches() => go(AppRoutes.adminMatches);
  void goAdminMatchDetail(String matchId) =>
      go(AppRoutes.adminMatchDetail(matchId));
  void goAdminPredictions() => go(AppRoutes.adminPredictions);
  void goAdminChallenges() => go(AppRoutes.adminChallenges);
  void goAdminChallengeDetail(String challengeId) =>
      go(AppRoutes.adminChallengeDetail(challengeId));
  void goAdminUsers() => go(AppRoutes.adminUsers);
  void goAdminUserDetail(String userId) =>
      go(AppRoutes.adminUserDetail(userId));
  void goAdminSuspicious() => go(AppRoutes.adminSuspicious);
  void goAdminRewards() => go(AppRoutes.adminRewards);
  void goAdminAchievements() => go(AppRoutes.adminAchievements);
  void goAdminLeaderboards() => go(AppRoutes.adminLeaderboards);
  void goAdminPoints() => go(AppRoutes.adminPoints);
  void goAdminStatistics() => go(AppRoutes.adminStatistics);
  void goAdminSettings() => go(AppRoutes.adminSettings);
  void goObsOverlay() => go(AppRoutes.obsOverlay);
  void goDemoMode() => go(AppRoutes.demoMode);
}
