enum PointSource { exactPrediction, videoQuestion, playerCard, adminAdjustment }

abstract final class PointRuleDefaults {
  static const exactPrediction = 100;
  static const videoQuestion = 40;
  static const playerCard = 20;
  static const normalMultiplier = 1.0;
  static const memberMultiplier = 2.0;

  static int baseFor(PointSource source) => switch (source) {
    PointSource.exactPrediction => exactPrediction,
    PointSource.videoQuestion => videoQuestion,
    PointSource.playerCard => playerCard,
    PointSource.adminAdjustment => 0,
  };
}

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
