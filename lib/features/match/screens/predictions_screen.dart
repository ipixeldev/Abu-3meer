// Predictions Screen - 5 prediction types with live XP calculator.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/index.dart';
import '../../core/state/provider.dart';
import '../../core/state/app_state.dart';
import '../../core/models/match.dart';
import '../../core/models/user.dart';
import '../../core/data/mock_matches.dart';
import '../../core/navigation/routes.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/team_badges.dart';
import '../../core/widgets/progress.dart';

class PredictionsScreen extends StatefulWidget {
  final String matchId;

  const PredictionsScreen({super.key, required this.matchId});

  @override
  State<PredictionsScreen> createState() => _PredictionsScreenState();
}

class _PredictionsScreenState extends State<PredictionsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  bool _isLocking = false;
  int _totalPotentialXp = 0;

  // Prediction controllers
  Team? _matchWinner;
  String _correctScore = '2-1';
  String? _firstScorerId;
  String? _manOfMatchId;
  bool _bothTeamsScore = false;

  final TextEditingController _scoreController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..forward();

    final match = findMatchById(widget.matchId);
    if (match != null) {
      final config = getPredictionConfig(match.id);
      _totalPotentialXp = config?.totalPotentialXp ?? 0;
      _scoreController.text = _correctScore;
    }

    // Load existing predictions if any
    _loadExistingPredictions();
  }

  void _loadExistingPredictions() {
    final state = context.appStateRead;
    final predictions = state.getUserPredictions(widget.matchId);
    if (predictions != null) {
      for (final p in predictions.predictions) {
        switch (p.type) {
          case PredictionType.matchWinner:
            _matchWinner = p.value as Team?;
            break;
          case PredictionType.correctScore:
            _correctScore = p.value as String;
            _scoreController.text = _correctScore;
            break;
          case PredictionType.firstScorer:
            _firstScorerId = p.value as String?;
            break;
          case PredictionType.manOfMatch:
            _manOfMatchId = p.value as String?;
            break;
          case PredictionType.bothTeamsScore:
            _bothTeamsScore = p.value as bool;
            break;
        }
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scoreController.dispose();
    super.dispose();
  }

  void _updatePotentialXp() {
    final match = findMatchById(widget.matchId);
    if (match == null) return;

    final config = getPredictionConfig(match.id);
    if (config == null) return;

    int total = 0;
    if (_matchWinner != null)
      total += config.xpRewards[PredictionType.matchWinner] ?? 0;
    if (_correctScore.isNotEmpty)
      total += config.xpRewards[PredictionType.correctScore] ?? 0;
    if (_firstScorerId != null)
      total += config.xpRewards[PredictionType.firstScorer] ?? 0;
    if (_manOfMatchId != null)
      total += config.xpRewards[PredictionType.manOfMatch] ?? 0;
    if (_bothTeamsScore)
      total += config.xpRewards[PredictionType.bothTeamsScore] ?? 0;

    setState(() => _totalPotentialXp = total);
  }

  bool get _hasAnyPrediction =>
      _matchWinner != null ||
      _correctScore.isNotEmpty ||
      _firstScorerId != null ||
      _manOfMatchId != null ||
      _bothTeamsScore;

  bool get _allPredictionsFilled {
    final match = findMatchById(widget.matchId);
    if (match == null) return false;
    final config = getPredictionConfig(match.id);
    if (config == null) return false;
    final requiredTypes = config.xpRewards.keys.toList();
    int filled = 0;
    if (_matchWinner != null) filled++;
    if (_correctScore.isNotEmpty) filled++;
    if (_firstScorerId != null) filled++;
    if (_manOfMatchId != null) filled++;
    if (_bothTeamsScore) filled++;
    return filled >= requiredTypes.length;
  }

  Future<void> _lockPredictions() async {
    if (!_hasAnyPrediction) return;

    setState(() => _isLocking = true);

    final state = context.appStateRead;
    final match = findMatchById(widget.matchId);
    if (match == null) return;

    final config = getPredictionConfig(match.id);
    if (config == null) return;

    // Save all predictions
    if (_matchWinner != null) {
      state.setPrediction(match.id, PredictionType.matchWinner, _matchWinner);
    }
    if (_correctScore.isNotEmpty) {
      state.setPrediction(match.id, PredictionType.correctScore, _correctScore);
    }
    if (_firstScorerId != null) {
      state.setPrediction(match.id, PredictionType.firstScorer, _firstScorerId);
    }
    if (_manOfMatchId != null) {
      state.setPrediction(match.id, PredictionType.manOfMatch, _manOfMatchId);
    }
    // Note: bothTeamsScore is a bool, so we always save it
    state.setPrediction(
      match.id,
      PredictionType.bothTeamsScore,
      _bothTeamsScore,
    );

    // Lock them
    state.lockPredictions(match.id);

    // Simulate server delay
    await Future.delayed(const Duration(milliseconds: 800));

    if (mounted) {
      setState(() => _isLocking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Predictions locked! +$_totalPotentialXp potential XP'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
        ),
      );
      context.go(AppRoutes.matchResult(match.id));
    }
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

    final config = getPredictionConfig(match.id);

    return Scaffold(
      backgroundColor: AppColors.bgCanvas,
      appBar: AppBar(
        title: Text('Predictions', style: AppTextStyles.headlineSmall()),
        leading: IconButton(
          icon: Icon(Icons.close, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (config != null)
            Container(
              margin: const EdgeInsets.only(right: AppSpacing.md),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.xpGold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star, size: 16, color: AppColors.xpGold),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '$_totalPotentialXp XP',
                    style: AppTextStyles.xpLabel(size: 13),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _animationController,
        builder: (context, _) {
          return FadeTransition(
            opacity: _animationController,
            child: SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 0.1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: _animationController,
                      curve: Curves.easeOut,
                    ),
                  ),
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.screenPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Match header
                          _buildMatchHeader(match),
                          const SizedBox(height: AppSpacing.xl),

                          // Prediction types
                          if (config != null) ...[
                            _buildPredictionType(
                              type: PredictionType.matchWinner,
                              title: 'Match Winner',
                              icon: Icons.flag_outlined,
                              xpReward:
                                  config.xpRewards[PredictionType
                                      .matchWinner] ??
                                  0,
                              child: _buildMatchWinnerSelector(match),
                            ),
                            _buildPredictionType(
                              type: PredictionType.correctScore,
                              title: 'Correct Score',
                              icon: Icons.score_outlined,
                              xpReward:
                                  config.xpRewards[PredictionType
                                      .correctScore] ??
                                  0,
                              child: _buildScoreSelector(),
                            ),
                            _buildPredictionType(
                              type: PredictionType.firstScorer,
                              title: 'First Scorer',
                              icon: Icons.sports_soccer_outlined,
                              xpReward:
                                  config.xpRewards[PredictionType
                                      .firstScorer] ??
                                  0,
                              child: _buildPlayerSelector(
                                match,
                                'First Scorer',
                              ),
                            ),
                            _buildPredictionType(
                              type: PredictionType.manOfMatch,
                              title: 'Man of the Match',
                              icon: Icons.star_outline,
                              xpReward:
                                  config.xpRewards[PredictionType.manOfMatch] ??
                                  0,
                              child: _buildPlayerSelector(
                                match,
                                'Man of the Match',
                              ),
                            ),
                            _buildPredictionType(
                              type: PredictionType.bothTeamsScore,
                              title: 'Both Teams to Score',
                              icon: Icons.compare_arrows_outlined,
                              xpReward:
                                  config.xpRewards[PredictionType
                                      .bothTeamsScore] ??
                                  0,
                              child: _buildBttsSelector(),
                            ),
                          ],

                          const SizedBox(height: AppSpacing.xl),

                          // Lock button
                          PrimaryButton(
                            label: _isLocking
                                ? 'LOCKING...'
                                : 'LOCK PREDICTIONS',
                            onPressed: _hasAnyPrediction && !_isLocking
                                ? _lockPredictions
                                : null,
                            fullWidth: true,
                            height: 56,
                            leadingIcon: Icons.lock_outlined,
                            loading: _isLocking,
                          ),

                          const SizedBox(height: AppSpacing.md),

                          Text(
                            'Predictions lock 30 minutes before kickoff (${DateFormat('HH:mm').format(match.predictionDeadline)})',
                            style: AppTextStyles.bodySmall(),
                            textAlign: TextAlign.center,
                          ),

                          const SizedBox(height: AppSpacing.xl),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMatchHeader(Match match) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        gradient: match.isElClasico
            ? (match.homeTeam == Team.barcelona
                  ? AppColors.gradientBarca
                  : AppColors.gradientMadrid)
            : AppColors.gradientSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TeamCrest(
                      isBarcelona: match.homeTeam == Team.barcelona,
                      size: 36,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      match.homeTeamName,
                      style: AppTextStyles.headlineSmall(color: Colors.white),
                    ),
                  ],
                ),
                if (match.homeScore != null)
                  Text(
                    '${match.homeScore}',
                    style: AppTextStyles.numberDisplay(
                      size: 32,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            'vs',
            style: AppTextStyles.labelMedium(
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      match.awayTeamName,
                      style: AppTextStyles.headlineSmall(color: Colors.white),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    TeamCrest(
                      isBarcelona: match.awayTeam == Team.barcelona,
                      size: 36,
                    ),
                  ],
                ),
                if (match.awayScore != null)
                  Text(
                    '${match.awayScore}',
                    style: AppTextStyles.numberDisplay(
                      size: 32,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.end,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPredictionType({
    required PredictionType type,
    required String title,
    required IconData icon,
    required int xpReward,
    required Widget child,
  }) {
    final isSelected = _isPredictionFilled(type);
    final config = getPredictionConfig(widget.matchId);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.accentPrimary.withValues(alpha: 0.15)
                        : AppColors.bgSurfaceElevated,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    border: isSelected
                        ? Border.all(color: AppColors.accentPrimary)
                        : null,
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: isSelected
                        ? AppColors.accentPrimary
                        : AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTextStyles.titleMedium()),
                      if (xpReward > 0)
                        Text(
                          '+$xpReward XP',
                          style: AppTextStyles.xpLabel(color: AppColors.xpGold),
                        ),
                    ],
                  ),
                ),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusFull,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 16,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          'SET',
                          style: AppTextStyles.labelSmall(
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }

  bool _isPredictionFilled(PredictionType type) {
    switch (type) {
      case PredictionType.matchWinner:
        return _matchWinner != null;
      case PredictionType.correctScore:
        return _correctScore.isNotEmpty;
      case PredictionType.firstScorer:
        return _firstScorerId != null;
      case PredictionType.manOfMatch:
        return _manOfMatchId != null;
      case PredictionType.bothTeamsScore:
        return _bothTeamsScore;
    }
  }

  Widget _buildMatchWinnerSelector(Match match) {
    return Row(
      children: [
        // Home win
        Expanded(
          child: _PredictionOption(
            label: match.homeTeamName,
            icon: TeamCrest(
              isBarcelona: match.homeTeam == Team.barcelona,
              size: 28,
            ),
            selected: _matchWinner == match.homeTeam,
            onTap: () => setState(() {
              _matchWinner = match.homeTeam;
              _updatePotentialXp();
            }),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        // Draw
        Expanded(
          child: _PredictionOption(
            label: 'Draw',
            icon: Icon(Icons.remove, size: 28, color: AppColors.textMuted),
            selected:
                _matchWinner == null &&
                _matchWinner != match.homeTeam &&
                _matchWinner != match.awayTeam &&
                false,
            onTap: () => setState(() {
              _matchWinner = null; // Represent draw as null
              _updatePotentialXp();
            }),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        // Away win
        Expanded(
          child: _PredictionOption(
            label: match.awayTeamName,
            icon: TeamCrest(
              isBarcelona: match.awayTeam == Team.barcelona,
              size: 28,
            ),
            selected: _matchWinner == match.awayTeam,
            onTap: () => setState(() {
              _matchWinner = match.awayTeam;
              _updatePotentialXp();
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildScoreSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Enter exact score (e.g., 2-1)', style: AppTextStyles.bodySmall()),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _scoreController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: '2-1',
                  prefixIcon: Icon(
                    Icons.sports_soccer,
                    color: AppColors.textMuted,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    borderSide: BorderSide(color: AppColors.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    borderSide: BorderSide(
                      color: AppColors.accentPrimary,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: AppColors.bgSurfaceElevated,
                ),
                onChanged: (v) {
                  _correctScore = v;
                  _updatePotentialXp();
                },
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            // Quick pick buttons
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final score in [
                  '1-0',
                  '2-1',
                  '2-0',
                  '1-1',
                  '3-1',
                  '0-0',
                  '3-2',
                  '2-2',
                ])
                  InkWell(
                    onTap: () {
                      _scoreController.text = score;
                      _correctScore = score;
                      _updatePotentialXp();
                    },
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _correctScore == score
                            ? AppColors.accentPrimary.withValues(alpha: 0.15)
                            : AppColors.bgSurfaceElevated,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusSm,
                        ),
                        border: Border.all(
                          color: _correctScore == score
                              ? AppColors.accentPrimary
                              : AppColors.divider,
                        ),
                      ),
                      child: Text(
                        score,
                        style: AppTextStyles.labelSmall(
                          color: _correctScore == score
                              ? AppColors.accentPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPlayerSelector(Match match, String title) {
    final homePlayers = Player.forTeam(match.homeTeam);
    final awayPlayers = Player.forTeam(match.awayTeam);
    final allPlayers = [...homePlayers, ...awayPlayers];

    final selectedPlayer = _firstScorerId != null
        ? allPlayers.firstWhere(
            (p) => p.id == _firstScorerId,
            orElse: () => allPlayers.first,
          )
        : (_manOfMatchId != null
              ? allPlayers.firstWhere(
                  (p) => p.id == _manOfMatchId,
                  orElse: () => allPlayers.first,
                )
              : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select a player', style: AppTextStyles.bodySmall()),
        const SizedBox(height: AppSpacing.sm),
        if (selectedPlayer != null)
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.accentPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: AppColors.accentPrimary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                TeamTag(
                  isBarcelona: selectedPlayer.team == Team.barcelona,
                  fontSize: 10,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '${selectedPlayer.name} (#${selectedPlayer.number})',
                    style: AppTextStyles.bodyMedium(
                      color: AppColors.accentPrimary,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: AppColors.accentPrimary,
                  ),
                  onPressed: () => setState(() {
                    if (title == 'First Scorer') {
                      _firstScorerId = null;
                    } else {
                      _manOfMatchId = null;
                    }
                    _updatePotentialXp();
                  }),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Text('Or choose from list:', style: AppTextStyles.bodySmall()),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: allPlayers.map((player) {
            final isSelected = title == 'First Scorer'
                ? _firstScorerId == player.id
                : _manOfMatchId == player.id;

            return InkWell(
              onTap: () => setState(() {
                if (title == 'First Scorer') {
                  _firstScorerId = player.id;
                } else {
                  _manOfMatchId = player.id;
                }
                _updatePotentialXp();
              }),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.accentPrimary.withValues(alpha: 0.15)
                      : AppColors.bgSurfaceElevated,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.accentPrimary
                        : AppColors.divider,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TeamTag(
                      isBarcelona: player.team == Team.barcelona,
                      fontSize: 9,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      '${player.name} #${player.number}',
                      style: AppTextStyles.labelSmall(
                        color: isSelected
                            ? AppColors.accentPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildBttsSelector() {
    return Row(
      children: [
        Expanded(
          child: _PredictionOption(
            label: 'Yes',
            icon: Icon(Icons.check_circle, size: 28, color: AppColors.success),
            selected: _bothTeamsScore == true,
            onTap: () => setState(() {
              _bothTeamsScore = true;
              _updatePotentialXp();
            }),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _PredictionOption(
            label: 'No',
            icon: Icon(Icons.cancel, size: 28, color: AppColors.error),
            selected: _bothTeamsScore == false && _bothTeamsScore != true,
            onTap: () => setState(() {
              _bothTeamsScore = false;
              _updatePotentialXp();
            }),
          ),
        ),
      ],
    );
  }
}

class _PredictionOption extends StatelessWidget {
  final String label;
  final Widget icon;
  final bool selected;
  final VoidCallback onTap;

  const _PredictionOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accentPrimary.withValues(alpha: 0.15)
                : AppColors.bgSurfaceElevated,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(
              color: selected ? AppColors.accentPrimary : AppColors.divider,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              icon,
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                style: AppTextStyles.labelMedium(
                  color: selected
                      ? AppColors.accentPrimary
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
