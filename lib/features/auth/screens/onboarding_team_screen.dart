// Team Selection Onboarding Screen - Choose Barcelona or Real Madrid.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/index.dart';
import '../../core/state/provider.dart';
import '../../core/state/app_state.dart';
import '../../core/models/user.dart';
import '../../core/navigation/routes.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/team_badges.dart';

class OnboardingTeamScreen extends StatefulWidget {
  const OnboardingTeamScreen({super.key});

  @override
  State<OnboardingTeamScreen> createState() => _OnboardingTeamScreenState();
}

class _OnboardingTeamScreenState extends State<OnboardingTeamScreen>
    with SingleTickerProviderStateMixin {
  Team? _selectedTeam;
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
          ),
        );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _selectTeam(Team team) {
    setState(() => _selectedTeam = team);
    // Haptic feedback
    // HapticFeedback.lightImpact();
  }

  Future<void> _completeOnboarding() async {
    if (_selectedTeam == null) return;

    final appState = context.appStateRead;
    if (appState.currentUser != null) {
      // Update user with team selection
      appState.updateProfile(team: _selectedTeam);

      // Grant "First Steps" achievement if first time
      appState.unlockAchievement(
        'ach_first_prediction',
      ); // Will be granted on first prediction instead

      // Show welcome and navigate to home
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Welcome to the Fan League, ${appState.currentUser!.displayName}!',
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
          ),
        );
        context.go(AppRoutes.home);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgCanvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPaddingLg),
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Column(
                children: [
                  const SizedBox(height: AppSpacing.xl),

                  // Title
                  Text(
                    'Choose Your Team',
                    style: AppTextStyles.displayMedium(),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: AppSpacing.sm),

                  Text(
                    'Your choice determines your Fan War allegiance.\nThis can be changed later in settings.',
                    style: AppTextStyles.bodyMedium(),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: AppSpacing.xxl),

                  // Team cards
                  Expanded(
                    child: Row(
                      children: [
                        // Barcelona
                        Expanded(
                          child: TeamSelectionCard(
                            isBarcelona: true,
                            selected: _selectedTeam == Team.barcelona,
                            onTap: () => _selectTeam(Team.barcelona),
                            title: 'Barcelona',
                            subtitle: 'Mes que un club',
                          ),
                        ),

                        const SizedBox(width: AppSpacing.md),

                        // Real Madrid
                        Expanded(
                          child: TeamSelectionCard(
                            isBarcelona: false,
                            selected: _selectedTeam == Team.realMadrid,
                            onTap: () => _selectTeam(Team.realMadrid),
                            title: 'Real Madrid',
                            subtitle: 'Hala Madrid',
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  // Continue button
                  PrimaryButton(
                    label: 'Join the Fan League',
                    onPressed: _selectedTeam != null
                        ? _completeOnboarding
                        : null,
                    fullWidth: true,
                    height: 56,
                    leadingIcon: Icons.flag_outlined,
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  // Skip for demo
                  TextButton(
                    onPressed: () {
                      // Default to Barcelona for demo
                      _selectTeam(Team.barcelona);
                      Future.delayed(
                        const Duration(milliseconds: 100),
                        _completeOnboarding,
                      );
                    },
                    child: Text(
                      'Skip (Demo: Auto-select Barcelona)',
                      style: AppTextStyles.labelSmall(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
