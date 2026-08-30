// Match Center Screen - Detailed match view with info, countdown, and predictions.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/design/index.dart';
import '../../core/state/provider.dart';
import '../../core/state/app_state.dart';
import '../../core/models/match.dart';
import '../../core/models/user.dart';
import '../../core/data/mock_matches.dart';
import '../../core/data/mock_users.dart';
import '../../core/navigation/routes.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/team_badges.dart';
import '../../core/widgets/progress.dart';

class MatchCenterScreen extends StatefulWidget {
  final String matchId;

  const MatchCenterScreen({super.key, required this.matchId});

  @override
  State<MatchCenterScreen> createState() => _MatchCenterScreenState();
}

class _MatchCenterScreenState extends State<MatchCenterScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late Timer _countdownTimer;
  Duration _timeToKickoff = Duration.zero;
  Duration _timeToDeadline = Duration.zero;
  bool _predictionsClosed = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..forward();
    _startCountdown();
  }

  void _startCountdown() {
    _updateCountdown();
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateCountdown(),
    );
  }

  void _updateCountdown() {
    final match = findMatchById(widget.matchId);
    if (match == null) return;

    final now = DateTime.now();
    final toKickoff = match.kickoff.difference(now);
    final toDeadline = match.predictionDeadline.difference(now);

    setState(() {
      _timeToKickoff = toKickoff.isNegative ? Duration.zero : toKickoff;
      _timeToDeadline = toDeadline.isNegative ? Duration.zero : toDeadline;
      _predictionsClosed =
          now.isAfter(match.predictionDeadline) ||
          match.status != MatchStatus.predictionsOpen;
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _countdownTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final match = findMatchById(widget.matchId);
    if (match == null) {
      return Scaffold(
        backgroundColor: AppColors.bgCanvas,
        body: Center(
          child: Text('Match not found', style: AppTextStyles.bodyLarge()),
        ),
      );
    }

    return Consumer<AppState>(
      builder: (context, state, _) {
        final user = state.currentUser;
        final predictions = user != null
            ? state.getUserPredictions(match.id)
            : null;
        final hasPredictions = predictions?.isLocked == true;
        final config = getPredictionConfig(match.id);

        return Scaffold(
          backgroundColor: AppColors.bgCanvas,
          body: CustomScrollView(
            slivers: [
              // Hero header with match info
              SliverAppBar(
                expandedHeight: 320,
                floating: false,
                pinned: true,
                backgroundColor: AppColors.bgSurface,
                flexibleSpace: FlexibleSpaceBar(
                  background: _buildMatchHeader(match, config),
                ),
                leading: IconButton(
                  icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
                  onPressed: () => context.pop(),
                ),
                actions: [
                  if (user != null && match.predictionsOpen && !hasPredictions)
                    TextButton.icon(
                      icon: Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: AppColors.accentPrimary,
                      ),
                      label: Text(
                        'PREDICT',
                        style: AppTextStyles.labelMedium(
                          color: AppColors.accentPrimary,
                        ),
                      ),
                      onPressed: () =>
                          context.go(AppRoutes.predictions(match.id)),
                    )
                  else if (user != null && (hasPredictions || match.isFinished))
                    TextButton.icon(
                      icon: Icon(
                        Icons.visibility_outlined,
                        size: 18,
                        color: AppColors.accentPrimary,
                      ),
                      label: Text(
                        'VIEW',
                        style: AppTextStyles.labelMedium(
                          color: AppColors.accentPrimary,
                        ),
                      ),
                      onPressed: () =>
                          context.go(AppRoutes.matchResult(match.id)),
                    ),
                  IconButton(
                    icon: Icon(
                      Icons.share_outlined,
                      color: AppColors.textPrimary,
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Demo: Share not implemented'),
                        ),
                      );
                    },
                  ),
                ],
              ),

              // Content
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.screenPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Match Info Cards
                      _buildInfoSection(match),
                      const SizedBox(height: AppSpacing.xl),

                      // Prediction Status / CTA
                      _buildPredictionSection(
                        match,
                        user,
                        predictions,
                        hasPredictions,
                        config,
                      ),
                      const SizedBox(height: AppSpacing.xl),

                      // Participating Fans
                      _buildParticipatingFans(match),
                      const SizedBox(height: AppSpacing.xl),

                      // Match History (H2H)
                      _buildHeadToHead(match),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMatchHeader(Match match, MatchPredictionConfig? config) {
    final isElClasico = match.isElClasico;
    final gradient = isElClasico
        ? (match.homeTeam == Team.barcelona
              ? AppColors.gradientBarca
              : AppColors.gradientMadrid)
        : AppColors.gradientSurface;

    return Container(
      decoration: BoxDecoration(gradient: gradient),
      child: Stack(
        children: [
          // Decorative elements
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -80,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.03),
              ),
            ),
          ),

          // Content
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.xl + 50,
              AppSpacing.screenPadding,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Competition badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                  child: Text(
                    match.competitionLabel,
                    style: AppTextStyles.labelMedium(color: Colors.white),
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),

                // Teams
                Row(
                  children: [
                    // Home team
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              TeamCrest(
                                isBarcelona: match.homeTeam == Team.barcelona,
                                size: 56,
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Text(
                                match.homeTeamName,
                                style: AppTextStyles.displaySmall(
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          if (match.homeScore != null)
                            Text(
                              '${match.homeScore}',
                              style: AppTextStyles.numberDisplay(
                                size: 56,
                                color: Colors.white,
                              ),
                            ),
                        ],
                      ),
                    ),

                    // VS / Score
                    Column(
                      children: [
                        if (match.isFinished)
                          Text(
                            'FT',
                            style: AppTextStyles.labelMedium(
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          )
                        else
                          Text(
                            'vs',
                            style: AppTextStyles.labelMedium(
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        if (match.homeScore != null && match.awayScore != null)
                          Text(
                            '${match.homeScore} – ${match.awayScore}',
                            style: AppTextStyles.numberMedium(
                              size: 22,
                              color: Colors.white,
                            ),
                          ),
                      ],
                    ),

                    // Away team
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                match.awayTeamName,
                                style: AppTextStyles.displaySmall(
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              TeamCrest(
                                isBarcelona: match.awayTeam == Team.barcelona,
                                size: 56,
                              ),
                            ],
                          ),
                          if (match.awayScore != null)
                            Text(
                              '${match.awayScore}',
                              style: AppTextStyles.numberDisplay(
                                size: 56,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.end,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.lg),

                // Status row
                Row(
                  children: [
                    // Countdown or status
                    if (!match.isFinished && match.predictionsOpen) ...[
                      _CountdownDisplay(
                        label: 'Predictions close in',
                        remaining: _timeToDeadline,
                        color: Colors.white,
                      ),
                      const SizedBox(width: AppSpacing.xl),
                      _CountdownDisplay(
                        label: 'Kickoff in',
                        remaining: _timeToKickoff,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ] else if (match.isLive) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusFull,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              'LIVE',
                              style: AppTextStyles.labelMedium(
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (match.isFinished) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusFull,
                          ),
                        ),
                        child: Text(
                          'FINISHED',
                          style: AppTextStyles.labelMedium(color: Colors.white),
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusFull,
                          ),
                        ),
                        child: Text(
                          'SCHEDULED',
                          style: AppTextStyles.labelMedium(color: Colors.white),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(Match match) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('MATCH INFO', style: AppTextStyles.xpLabel()),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.event_outlined,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text('Date & Time', style: AppTextStyles.labelMedium()),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      DateFormat('EEEE, MMMM d, yyyy').format(match.kickoff),
                      style: AppTextStyles.bodyMedium(),
                    ),
                    Text(
                      '${match.kickoffTime} local time',
                      style: AppTextStyles.bodySmall(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text('Venue', style: AppTextStyles.labelMedium()),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(match.stadium, style: AppTextStyles.bodyMedium()),
                    if (match.venueCity != null)
                      Text(match.venueCity!, style: AppTextStyles.bodySmall()),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          'Participating Fans',
                          style: AppTextStyles.labelMedium(),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _formatNumber(match.participatingFans),
                      style: AppTextStyles.numberLarge(
                        color: AppColors.accentPrimary,
                      ),
                    ),
                    Text(
                      'fans have made predictions',
                      style: AppTextStyles.bodySmall(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.star_outline,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          'Total XP Pool',
                          style: AppTextStyles.labelMedium(),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _formatNumber(match.totalXpPool),
                      style: AppTextStyles.numberLarge(color: AppColors.xpGold),
                    ),
                    Text(
                      'XP distributed for this match',
                      style: AppTextStyles.bodySmall(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPredictionSection(
    Match match,
    User? user,
    UserMatchPredictions? predictions,
    bool hasPredictions,
    MatchPredictionConfig? config,
  ) {
    if (user == null) {
      return SurfaceCard(
        child: Column(
          children: [
            Text('PREDICTIONS', style: AppTextStyles.xpLabel()),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Sign in to make predictions',
              style: AppTextStyles.bodyMedium(),
            ),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              label: 'SIGN IN TO PREDICT',
              onPressed: () => context.go(AppRoutes.login),
              fullWidth: true,
            ),
          ],
        ),
      );
    }

    if (match.isFinished) {
      return SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('MATCH COMPLETE', style: AppTextStyles.xpLabel()),
                const Spacer(),
                if (hasPredictions)
                  PrimaryButton(
                    label: 'VIEW RESULTS',
                    onPressed: () =>
                        context.go(AppRoutes.matchResult(match.id)),
                    leadingIcon: Icons.flag_outlined,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              hasPredictions
                  ? 'Your predictions have been resolved. Check your results!'
                  : 'You did not make predictions for this match.',
              style: AppTextStyles.bodyMedium(),
            ),
          ],
        ),
      );
    }

    if (_predictionsClosed || !match.predictionsOpen) {
      return SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'PREDICTIONS LOCKED',
                  style: AppTextStyles.xpLabel(color: AppColors.error),
                ),
                const Spacer(),
                if (hasPredictions)
                  PrimaryButton(
                    label: 'VIEW PREDICTIONS',
                    onPressed: () =>
                        context.go(AppRoutes.matchResult(match.id)),
                    leadingIcon: Icons.visibility_outlined,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              hasPredictions
                  ? 'Your predictions are locked. Results will be calculated after the match.'
                  : 'Predictions closed before kickoff. Better luck next match!',
              style: AppTextStyles.bodyMedium(),
            ),
            if (config != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'Available Predictions:',
                style: AppTextStyles.labelMedium(),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: config.xpRewards.entries.map((e) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.bgSurfaceElevated,
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusFull,
                      ),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(e.key.typeLabel, style: AppTextStyles.bodySmall()),
                        const SizedBox(width: AppSpacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.xpGold.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusFull,
                            ),
                          ),
                          child: Text(
                            '+${e.value} XP',
                            style: AppTextStyles.xpLabel(size: 10),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      );
    }

    // Predictions open
    final potentialXp = config?.totalPotentialXp ?? 0;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('MAKE YOUR PREDICTIONS', style: AppTextStyles.xpLabel()),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.xpGold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star, size: 14, color: AppColors.xpGold),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      '+$potentialXp XP',
                      style: AppTextStyles.xpLabel(size: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          if (hasPredictions) ...[
            Text(
              'You\'ve already locked your predictions. You can view them or reset to change.',
              style: AppTextStyles.bodyMedium(),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: PrimaryButton(
                    label: 'VIEW PREDICTIONS',
                    onPressed: () =>
                        context.go(AppRoutes.matchResult(match.id)),
                    leadingIcon: Icons.visibility_outlined,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: SecondaryButton(
                    label: 'RESET & RE-PREDICT',
                    onPressed: () {
                      context.appStateRead.unlockPredictionsForDemo(match.id);
                      context.go(AppRoutes.predictions(match.id));
                    },
                    leadingIcon: Icons.refresh,
                  ),
                ),
              ],
            ),
          ] else ...[
            Text(
              'Lock in your predictions before kickoff. Each correct prediction earns XP!',
              style: AppTextStyles.bodyMedium(),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'START PREDICTING',
              onPressed: () => context.go(AppRoutes.predictions(match.id)),
              fullWidth: true,
              leadingIcon: Icons.psychology_outlined,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Predictions close at ${DateFormat('HH:mm').format(match.predictionDeadline)} (30 min before kickoff)',
              style: AppTextStyles.bodySmall(),
              textAlign: TextAlign.center,
            ),
          ],

          if (config != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Divider(color: AppColors.divider),
            const SizedBox(height: AppSpacing.md),
            Text('Available Predictions:', style: AppTextStyles.labelMedium()),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: config.xpRewards.entries.map((e) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurfaceElevated,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getPredictionIcon(e.key),
                        size: 18,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(e.key.typeLabel, style: AppTextStyles.bodySmall()),
                      const SizedBox(width: AppSpacing.md),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.xpGold.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusFull,
                          ),
                        ),
                        child: Text(
                          '+${e.value} XP',
                          style: AppTextStyles.xpLabel(size: 10),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  IconData _getPredictionIcon(PredictionType type) {
    switch (type) {
      case PredictionType.matchWinner:
        return Icons.flag_outlined;
      case PredictionType.correctScore:
        return Icons.score_outlined;
      case PredictionType.firstScorer:
        return Icons.sports_soccer_outlined;
      case PredictionType.manOfMatch:
        return Icons.star_outline;
    }
  }

  Widget _buildParticipatingFans(Match match) {
    // Mock top participants
    final topFans = _mockUsers.where((u) => u.totalPredictions > 0).toList()
      ..sort((a, b) => b.xp.compareTo(a.xp));
    topFans.take(10).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('TOP PARTICIPANTS', style: AppTextStyles.xpLabel()),
            const Spacer(),
            Text(
              '${match.participatingFans} total',
              style: AppTextStyles.bodySmall(),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: topFans.length.clamp(0, 10),
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, index) {
              final fan = topFans[index];
              return _ParticipantCard(fan: fan, rank: index + 1);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeadToHead(Match match) {
    // Mock H2H data
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('HEAD TO HEAD', style: AppTextStyles.xpLabel()),
        const SizedBox(height: AppSpacing.md),
        SurfaceCard(
          child: Column(
            children: [
              _H2HRow(
                label: 'Last 5 Meetings',
                barca: 'W-D-W-W-L',
                madrid: 'L-D-L-L-W',
              ),
              Divider(height: 1, color: AppColors.divider),
              _H2HRow(label: 'Goals (Last 5)', barca: '12', madrid: '8'),
              Divider(height: 1, color: AppColors.divider),
              _H2HRow(label: 'Clean Sheets', barca: '2', madrid: '1'),
              Divider(height: 1, color: AppColors.divider),
              _H2HRow(
                label: 'Current Form',
                barca: 'W-W-W-D-W',
                madrid: 'W-L-W-W-D',
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

class _CountdownDisplay extends StatelessWidget {
  final String label;
  final Duration remaining;
  final Color color;

  const _CountdownDisplay({
    required this.label,
    required this.remaining,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final d = remaining.inDays;
    final h = remaining.inHours.remainder(24);
    final m = remaining.inMinutes.remainder(60);
    final s = remaining.inSeconds.remainder(60);

    String text;
    if (d > 0)
      text = '${d}d ${h}h';
    else if (h > 0)
      text = '${h}h ${m}m';
    else
      text = '${m}m ${s}s';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.labelSmall(color: color.withValues(alpha: 0.7)),
        ),
        Text(text, style: AppTextStyles.numberMedium(color: color, size: 18)),
      ],
    );
  }
}

class _ParticipantCard extends StatelessWidget {
  final User fan;
  final int rank;

  const _ParticipantCard({required this.fan, required this.rank});

  @override
  Widget build(BuildContext context) {
    final isTop3 = rank <= 3;
    final rankColor = rank == 1
        ? AppColors.rankGold
        : rank == 2
        ? AppColors.rankSilver
        : AppColors.rankBronze;

    return SizedBox(
      width: 120,
      child: Column(
        children: [
          if (isTop3)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: rankColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              ),
              child: Text(
                '#$rank',
                style: AppTextStyles.rankBadge(color: rankColor, size: 10),
              ),
            ),
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.bgSurfaceElevated,
            child: Text(
              fan.displayName[0].toUpperCase(),
              style: AppTextStyles.numberMedium(
                size: 20,
                color: AppColors.accentPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            fan.displayName,
            style: AppTextStyles.labelSmall(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          Text(
            '${fan.xp} XP',
            style: AppTextStyles.bodySmall(),
            textAlign: TextAlign.center,
          ),
          TeamTag(isBarcelona: fan.team == Team.barcelona, fontSize: 8),
        ],
      ),
    );
  }
}

class _H2HRow extends StatelessWidget {
  final String label;
  final String barca;
  final String madrid;

  const _H2HRow({
    required this.label,
    required this.barca,
    required this.madrid,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.md,
        horizontal: AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTextStyles.bodySmall())),
          Text(
            barca,
            style: AppTextStyles.numberSmall(color: AppColors.barcaBlue),
          ),
          const SizedBox(width: AppSpacing.xl),
          Text(
            madrid,
            style: AppTextStyles.numberSmall(color: AppColors.madridGold),
          ),
        ],
      ),
    );
  }
}
