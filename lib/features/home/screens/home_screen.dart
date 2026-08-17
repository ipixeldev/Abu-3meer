// Home / Fan Hub - The main dashboard screen.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/design/index.dart';
import '../../core/state/provider.dart';
import '../../core/state/app_state.dart';
import '../../core/models/user.dart';
import '../../core/models/match.dart';
import '../../core/models/challenge.dart';
import '../../core/navigation/routes.dart';
import '../../core/data/mock_users.dart';
import '../../core/data/mock_matches.dart';
import '../../core/data/mock_challenges.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/progress.dart';
import '../../core/widgets/team_badges.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        if (!state.isAuthenticated || state.currentUser == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final user = state.currentUser!;
        final nextMatch = getNextMatch();
        final activeChallenges = getActiveChallengesForUser(user);
        final fanWarStats = FanWarStats(
          barcaTotalXp: barcaTotalXp,
          madridTotalXp: madridTotalXp,
          barcaActiveFans: barcaActiveFans,
          madridActiveFans: madridActiveFans,
          barcaAvgXp: barcaAvgXp,
          madridAvgXp: madridAvgXp,
          barcaWeeklyXp: barcaWeeklyXp,
          madridWeeklyXp: madridWeeklyXp,
          barcaTopContributorId: barcaTopContributorId,
          madridTopContributorId: madridTopContributorId,
          barcaTopContributorXp: barcaTopContributorXp,
          madridTopContributorXp: madridTopContributorXp,
          lastUpdated: DateTime.now(),
        );

        return CustomScrollView(
          slivers: [
            // App Bar with XP/Level
            SliverAppBar(
              expandedHeight: 140,
              floating: false,
              pinned: true,
              backgroundColor: AppColors.bgSurface,
              flexibleSpace: FlexibleSpaceBar(
                background: _buildProfileHeader(user),
              ),
              actions: [
                IconButton(
                  icon: Icon(Icons.notifications_outlined, color: AppColors.textPrimary),
                  onPressed: () => context.go(AppRoutes.notifications),
                ),
                IconButton(
                  icon: Icon(Icons.settings_outlined, color: AppColors.textPrimary),
                  onPressed: () => context.go(AppRoutes.settings),
                ),
              ],
            ),

            // Content
            SliverToBoxAdapter(
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, _) {
                  return Padding(
                    padding: const EdgeInsets.all(AppSpacing.screenPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // XP Progress Bar
                        _buildXpProgress(user),
                        const SizedBox(height: AppSpacing.xl),

                        // Next Match
                        if (nextMatch != null) _buildNextMatchCard(nextMatch, user),
                        if (nextMatch != null) const SizedBox(height: AppSpacing.xl),

                        // Fan War Preview
                        _buildFanWarPreview(fanWarStats),
                        const SizedBox(height: AppSpacing.xl),

                        // Active Challenges
                        if (activeChallenges.isNotEmpty) ...[
                          _buildActiveChallenges(activeChallenges, user),
                          const SizedBox(height: AppSpacing.xl),
                        ],

                        // Recent Activity
                        _buildRecentActivity(state),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProfileHeader(User user) {
    final greeting = _getGreeting();

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.xl + 50, // Account for status bar
        AppSpacing.screenPadding,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.bgSurfaceElevated,
                child: Text(
                  user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : user.username[0].toUpperCase(),
                  style: AppTextStyles.numberMedium(size: 24, color: AppColors.accentPrimary),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$greeting, ${user.displayName}', style: AppTextStyles.headlineSmall()),
                    Row(
                      children: [
                        TeamTag(isBarcelona: user.team == Team.barcelona, fontSize: 10),
                        const SizedBox(width: AppSpacing.sm),
                        if (user.membershipTier != MembershipTier.none)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accentPrimary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                            ),
                            child: Text(
                              user.membershipLabel,
                              style: AppTextStyles.labelSmall(color: AppColors.accentPrimary),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Level badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              gradient: AppColors.gradientPrimary,
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star, size: 16, color: AppColors.textOnAccent),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'LEVEL ${user.level} — ${user.levelName}',
                  style: AppTextStyles.xpLabel(size: 13, color: AppColors.textOnAccent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _buildXpProgress(User user) {
    return XpProgressBar(
      currentXp: user.xp,
      targetXp: user.xpForNextLevel,
      level: user.level,
      levelName: user.levelName,
      onTap: () => context.go(AppRoutes.levels),
    );
  }

  Widget _buildNextMatchCard(Match match, User user) {
    final predictions = context.appStateRead.getUserPredictions(match.id);
    final hasPredictions = predictions?.isLocked == true;

    return GradientCard(
      gradient: match.isElClasico
          ? (match.homeTeam == Team.barcelona ? AppColors.gradientBarca : AppColors.gradientMadrid)
          : AppColors.gradientSurface,
      onTap: () => context.go(AppRoutes.matchCenter(match.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: Text(
                  match.competitionLabel,
                  style: AppTextStyles.labelSmall(color: Colors.white),
                ),
              ),
              const Spacer(),
              if (match.predictionsOpen)
                _CountdownToKickoff(kickoff: match.kickoff, deadline: match.predictionDeadline)
              else if (match.isFinished)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                  child: Text('FINISHED', style: AppTextStyles.labelSmall(color: Colors.white)),
                ),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),

          // Teams
          Row(
            children: [
              // Home
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TeamCrest(isBarcelona: match.homeTeam == Team.barcelona, size: 40),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          match.homeTeamName,
                          style: AppTextStyles.headlineMedium(color: Colors.white),
                        ),
                      ],
                    ),
                    if (match.homeScore != null)
                      Text(
                        '${match.homeScore}',
                        style: AppTextStyles.numberDisplay(size: 40, color: Colors.white),
                      ),
                  ],
                ),
              ),

              // VS
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text(
                  match.isFinished ? 'FT' : 'vs',
                  style: AppTextStyles.labelMedium(color: Colors.white.withValues(alpha: 0.8)),
                ),
              ),

              // Away
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          match.awayTeamName,
                          style: AppTextStyles.headlineMedium(color: Colors.white),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        TeamCrest(isBarcelona: match.awayTeam == Team.barcelona, size: 40),
                      ],
                    ),
                    if (match.awayScore != null)
                      Text(
                        '${match.awayScore}',
                        style: AppTextStyles.numberDisplay(size: 40, color: Colors.white),
                        textAlign: TextAlign.end,
                      ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          // Details
          Row(
            children: [
              Icon(Icons.location_on_outlined, size: 14, color: Colors.white.withValues(alpha: 0.7)),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '${match.stadium}${match.venueCity != null ? ', ${match.venueCity}' : ''}',
                style: AppTextStyles.bodySmall(color: Colors.white.withValues(alpha: 0.7)),
              ),
              const Spacer(),
              if (!match.isFinished)
                Text(
                  'Kickoff: ${match.kickoffTime}',
                  style: AppTextStyles.bodySmall(color: Colors.white.withValues(alpha: 0.7)),
                ),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),

          // CTA
          PrimaryButton(
            label: hasPredictions ? 'VIEW PREDICTIONS' : 'MAKE YOUR PREDICTIONS',
            onPressed: () => hasPredictions
                ? context.go(AppRoutes.matchResult(match.id))
                : context.go(AppRoutes.predictions(match.id)),
            fullWidth: true,
            leadingIcon: hasPredictions ? Icons.visibility_outlined : Icons.edit_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildFanWarPreview(FanWarStats stats) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('FAN WAR', style: AppTextStyles.xpLabel()),
              const Spacer(),
              GestureDetector(
                onTap: () => context.go(AppRoutes.fanWar),
                child: Text('View All', style: AppTextStyles.labelMedium(color: AppColors.accentPrimary)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Progress bar
          FanWarProgress(
            barcaXp: stats.barcaTotalXp,
            madridXp: stats.madridTotalXp,
            height: 10,
            showLabels: true,
          ),

          const SizedBox(height: AppSpacing.md),

          // Stats row
          Row(
            children: [
              Expanded(
                child: _FanWarStat(
                  label: 'Active Fans',
                  barcaValue: stats.barcaActiveFans.toString(),
                  madridValue: stats.madridActiveFans.toString(),
                ),
              ),
              Expanded(
                child: _FanWarStat(
                  label: 'Avg XP/Fan',
                  barcaValue: stats.barcaAvgXp.toStringAsFixed(0),
                  madridValue: stats.madridAvgXp.toStringAsFixed(0),
                ),
              ),
              Expanded(
                child: _FanWarStat(
                  label: 'This Week',
                  barcaValue: '+${_formatNumber(stats.barcaWeeklyXp)}',
                  madridValue: '+${_formatNumber(stats.madridWeeklyXp)}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  Widget _buildActiveChallenges(List<Challenge> challenges, User user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('ACTIVE CHALLENGES', style: AppTextStyles.xpLabel()),
            const Spacer(),
            GestureDetector(
              onTap: () => context.go(AppRoutes.challenges),
              child: Text('View All', style: AppTextStyles.labelMedium(color: AppColors.accentPrimary)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: challenges.length.clamp(0, 3),
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) {
            final challenge = challenges[index];
            final progress = context.appStateRead.getChallengeProgress(challenge.id);
            final completed = progress?.completed == true;

            return SurfaceCard(
              onTap: () => context.go(AppRoutes.challengeDetail(challenge.id)),
              interactive: true,
              child: Row(
                children: [
                  // Category icon
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _getChallengeCategoryColor(challenge.category).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: Icon(
                      challenge.categoryIcon,
                      color: _getChallengeCategoryColor(challenge.category),
                      size: 24,
                    ),
                  ),

                  const SizedBox(width: AppSpacing.md),

                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                challenge.title,
                                style: AppTextStyles.titleMedium(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (challenge.memberOnly)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.accentPrimary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                                ),
                                child: Text('MEMBER', style: AppTextStyles.labelSmall(color: AppColors.accentPrimary)),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          challenge.description,
                          style: AppTextStyles.bodySmall(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Icon(Icons.star_outline, size: 14, color: AppColors.xpGold),
                            const SizedBox(width: AppSpacing.xs),
                            Text('+${challenge.xpReward} XP', style: AppTextStyles.labelSmall(color: AppColors.xpGold)),
                            const SizedBox(width: AppSpacing.md),
                            Icon(Icons.monetization_on_outlined, size: 14, color: AppColors.accentPrimary),
                            const SizedBox(width: AppSpacing.xs),
                            Text('+${challenge.loyaltyReward} LP', style: AppTextStyles.labelSmall(color: AppColors.accentPrimary)),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Status/CTA
                  if (completed)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle, size: 16, color: AppColors.success),
                          const SizedBox(width: AppSpacing.xs),
                          Text('COMPLETED', style: AppTextStyles.labelSmall(color: AppColors.success)),
                        ],
                      ),
                    )
                  else
                    PrimaryButton(
                      label: challenge.type == ChallengeType.secretPhrase ? 'ENTER PHRASE' : 'PLAY',
                      onPressed: () => context.go(AppRoutes.challengeDetail(challenge.id)),
                      height: 36,
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Color _getChallengeCategoryColor(ChallengeCategory category) {
    switch (category) {
      case ChallengeCategory.video:
        return AppColors.accentSecondary;
      case ChallengeCategory.match:
        return AppColors.accentPrimary;
      case ChallengeCategory.general:
        return AppColors.success;
      case ChallengeCategory.special:
        return AppColors.accentPrimary;
    }
  }

  Widget _buildRecentActivity(AppState state) {
    final user = state.currentUser!;
    final activities = state.getUserActivity().take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('RECENT ACTIVITY', style: AppTextStyles.xpLabel()),
            const Spacer(),
            GestureDetector(
              onTap: () => context.go(AppRoutes.activity),
              child: Text('View All', style: AppTextStyles.labelMedium(color: AppColors.accentPrimary)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (activities.isEmpty)
          SurfaceCard(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text('No recent activity', style: AppTextStyles.bodyMedium()),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: activities.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.divider),
            itemBuilder: (context, index) {
              final txn = activities[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: txn.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                      child: Icon(txn.icon, size: 20, color: txn.color),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(txn.description, style: AppTextStyles.bodySmall()),
                          Text(
                            DateFormat('MMM d, HH:mm').format(txn.createdAt),
                            style: AppTextStyles.labelSmall(),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${txn.isCredit ? '+' : ''}${txn.amount} ${txn.type.name.toUpperCase()}',
                      style: AppTextStyles.numberSmall(color: txn.color),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

class _CountdownToKickoff extends StatefulWidget {
  final DateTime kickoff;
  final DateTime deadline;

  const _CountdownToKickoff({required this.kickoff, required this.deadline});

  @override
  State<_CountdownToKickoff> createState() => _CountdownToKickoffState();
}

class _CountdownToKickoffState extends State<_CountdownToKickoff> {
  late Timer _timer;
  Duration _remaining = Duration.zero;
  bool _predictionsClosed = false;

  @override
  void initState() {
    super.initState();
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  void _update() {
    final now = DateTime.now();
    if (now.isAfter(widget.deadline)) {
      if (!_predictionsClosed) {
        setState(() => _predictionsClosed = true);
      }
      _timer.cancel();
      return;
    }
    setState(() => _remaining = widget.deadline.difference(now));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_predictionsClosed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        ),
        child: Text('PREDICTIONS LOCKED', style: AppTextStyles.labelSmall(color: Colors.white)),
      );
    }

    final h = _remaining.inHours;
    final m = _remaining.inMinutes.remainder(60);
    final s = _remaining.inSeconds.remainder(60);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule, size: 12, color: Colors.white),
          const SizedBox(width: AppSpacing.xs),
          Text(
            h > 0 ? '${h}h ${m}m' : '${m}m ${s}s',
            style: AppTextStyles.labelSmall(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _FanWarStat extends StatelessWidget {
  final String label;
  final String barcaValue;
  final String madridValue;

  const _FanWarStat({
    required this.label,
    required this.barcaValue,
    required this.madridValue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: AppTextStyles.labelSmall(), textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(barcaValue, style: AppTextStyles.numberSmall(color: AppColors.barcaBlue, size: 14)),
            const SizedBox(width: AppSpacing.sm),
            Text(madridValue, style: AppTextStyles.numberSmall(color: AppColors.madridGold, size: 14)),
          ],
        ),
      ],
    );
  }
}

import 'dart:async';
