enum PointSource {
  exactPrediction,
  firstScorer,
  winnerOutcome,
  videoQuestion,
  playerCard,
  dailyStreak,
  signUpBonus,
  adminAdjustment,
}

abstract final class PointRuleDefaults {
  static const exactPrediction = 30;
  static const firstScorer = 20;
  static const winnerOutcome = 10;
  static const videoQuestion = 10;
  static const playerCard = 10;
  static const dailyStreak = 5;
  static const signUpBonus = 50;
  static const normalMultiplier = 1.0;
  static const memberMultiplier = 2.0;

  static int baseFor(PointSource source) => switch (source) {
    PointSource.exactPrediction => exactPrediction,
    PointSource.firstScorer => firstScorer,
    PointSource.winnerOutcome => winnerOutcome,
    PointSource.videoQuestion => videoQuestion,
    PointSource.playerCard => playerCard,
    PointSource.dailyStreak => dailyStreak,
    PointSource.signUpBonus => signUpBonus,
    PointSource.adminAdjustment => 0,
  };
}

bool isMemberMultiplierEligible(PointSource source) => switch (source) {
  PointSource.exactPrediction ||
  PointSource.firstScorer ||
  PointSource.winnerOutcome ||
  PointSource.videoQuestion => true,
  PointSource.playerCard ||
  PointSource.dailyStreak ||
  PointSource.signUpBonus ||
  PointSource.adminAdjustment => false,
};

num memberMultiplierForSource({
  required PointSource source,
  required bool isMember,
  num configuredMultiplier = PointRuleDefaults.memberMultiplier,
}) => isMember && isMemberMultiplierEligible(source) ? configuredMultiplier : 1;

int calculatePoints({required int basePoints, required num multiplier}) {
  if (basePoints < 0 || multiplier < 0) {
    throw ArgumentError('Points and multiplier must be non-negative.');
  }
  return (basePoints * multiplier).round();
}

String rewardLedgerId({
  required PointSource source,
  required String sourceId,
  required String userId,
}) => '${source.name}_${sourceId}_$userId';

bool predictionIsOpen({
  required DateTime serverNow,
  required DateTime opensAt,
  required DateTime closesAt,
}) => !serverNow.isBefore(opensAt) && serverNow.isBefore(closesAt);
