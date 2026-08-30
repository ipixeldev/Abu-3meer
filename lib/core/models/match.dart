// Match, prediction, and result models.

import 'package:flutter/material.dart';

import 'user.dart';

enum MatchStatus {
  scheduled,
  predictionsOpen,
  predictionsLocked,
  live,
  finished,
  cancelled,
}

enum Competition { laLiga, championsLeague, copaDelRey, superCup, friendly }

/// Football match model.
class Match {
  final String id;
  final String homeTeamName;
  final String awayTeamName;
  final Team homeTeam; // For crest/colors
  final Team awayTeam;
  final Competition competition;
  final DateTime kickoff;
  final DateTime predictionDeadline;
  final String stadium;
  final String? venueCity;
  final MatchStatus status;
  final int? homeScore;
  final int? awayScore;
  final String? firstScorerId;
  final String? manOfMatchId;
  final int participatingFans;
  final int totalXpPool;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const Match({
    required this.id,
    required this.homeTeamName,
    required this.awayTeamName,
    required this.homeTeam,
    required this.awayTeam,
    required this.competition,
    required this.kickoff,
    required this.predictionDeadline,
    required this.stadium,
    this.venueCity,
    this.status = MatchStatus.scheduled,
    this.homeScore,
    this.awayScore,
    this.firstScorerId,
    this.manOfMatchId,
    this.participatingFans = 0,
    this.totalXpPool = 0,
    required this.createdAt,
    this.updatedAt,
  });

  Match copyWith({
    String? id,
    String? homeTeamName,
    String? awayTeamName,
    Team? homeTeam,
    Team? awayTeam,
    Competition? competition,
    DateTime? kickoff,
    DateTime? predictionDeadline,
    String? stadium,
    String? venueCity,
    MatchStatus? status,
    int? homeScore,
    int? awayScore,
    String? firstScorerId,
    String? manOfMatchId,
    int? participatingFans,
    int? totalXpPool,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Match(
    id: id ?? this.id,
    homeTeamName: homeTeamName ?? this.homeTeamName,
    awayTeamName: awayTeamName ?? this.awayTeamName,
    homeTeam: homeTeam ?? this.homeTeam,
    awayTeam: awayTeam ?? this.awayTeam,
    competition: competition ?? this.competition,
    kickoff: kickoff ?? this.kickoff,
    predictionDeadline: predictionDeadline ?? this.predictionDeadline,
    stadium: stadium ?? this.stadium,
    venueCity: venueCity ?? this.venueCity,
    status: status ?? this.status,
    homeScore: homeScore ?? this.homeScore,
    awayScore: awayScore ?? this.awayScore,
    firstScorerId: firstScorerId ?? this.firstScorerId,
    manOfMatchId: manOfMatchId ?? this.manOfMatchId,
    participatingFans: participatingFans ?? this.participatingFans,
    totalXpPool: totalXpPool ?? this.totalXpPool,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  bool get isElClasico =>
      (homeTeam == Team.barcelona && awayTeam == Team.realMadrid) ||
      (homeTeam == Team.realMadrid && awayTeam == Team.barcelona);

  bool get predictionsOpen =>
      status == MatchStatus.predictionsOpen &&
      DateTime.now().isBefore(predictionDeadline);

  bool get isFinished => status == MatchStatus.finished;
  bool get isLive => status == MatchStatus.live;

  String get competitionLabel {
    switch (competition) {
      case Competition.laLiga:
        return 'La Liga';
      case Competition.championsLeague:
        return 'Champions League';
      case Competition.copaDelRey:
        return 'Copa del Rey';
      case Competition.superCup:
        return 'Super Cup';
      case Competition.friendly:
        return 'Friendly';
    }
  }

  String get scoreText {
    if (homeScore != null && awayScore != null) {
      return '$homeScore – $awayScore';
    }
    return 'vs';
  }

  /// Winner team for match winner prediction.
  Team? get winner {
    if (homeScore == null || awayScore == null) return null;
    if (homeScore! > awayScore!) return homeTeam;
    if (awayScore! > homeScore!) return awayTeam;
    return null; // Draw
  }

  /// Formatted kickoff time.
  String get kickoffTime {
    final hour = kickoff.hour.toString().padLeft(2, '0');
    final min = kickoff.minute.toString().padLeft(2, '0');
    return '$hour:$min';
  }
}

/// Prediction types available.
enum PredictionType { matchWinner, correctScore, firstScorer, manOfMatch }

/// A single prediction entry.
class Prediction {
  final String id;
  final String userId;
  final String matchId;
  final PredictionType type;
  final dynamic value; // Team for winner, "2-1" for score, playerId for scorers
  final int xpReward;
  final bool isCorrect;
  final bool isLocked;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  const Prediction({
    required this.id,
    required this.userId,
    required this.matchId,
    required this.type,
    required this.value,
    required this.xpReward,
    this.isCorrect = false,
    this.isLocked = false,
    required this.createdAt,
    this.resolvedAt,
  });

  Prediction copyWith({
    String? id,
    String? userId,
    String? matchId,
    PredictionType? type,
    dynamic value,
    int? xpReward,
    bool? isCorrect,
    bool? isLocked,
    DateTime? createdAt,
    DateTime? resolvedAt,
  }) => Prediction(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    matchId: matchId ?? this.matchId,
    type: type ?? this.type,
    value: value ?? this.value,
    xpReward: xpReward ?? this.xpReward,
    isCorrect: isCorrect ?? this.isCorrect,
    isLocked: isLocked ?? this.isLocked,
    createdAt: createdAt ?? this.createdAt,
    resolvedAt: resolvedAt ?? this.resolvedAt,
  );

  String get displayValue {
    switch (type) {
      case PredictionType.matchWinner:
        if (value == 'draw') return 'Draw';
        return value is Team
            ? (value == Team.barcelona ? 'Barcelona' : 'Real Madrid')
            : value.toString();
      case PredictionType.correctScore:
        return value.toString();
      case PredictionType.firstScorer:
      case PredictionType.manOfMatch:
        return value.toString(); // Player name
    }
  }

  String get typeLabel {
    switch (type) {
      case PredictionType.matchWinner:
        return 'Match Winner';
      case PredictionType.correctScore:
        return 'Correct Score';
      case PredictionType.firstScorer:
        return 'First Scorer';
      case PredictionType.manOfMatch:
        return 'Man of the Match';
    }
  }
}

/// All predictions for a user on a specific match.
class UserMatchPredictions {
  final String userId;
  final String matchId;
  final List<Prediction> predictions;
  final bool isLocked;
  final DateTime? lockedAt;
  final int totalPotentialXp;
  final int earnedXp;

  const UserMatchPredictions({
    required this.userId,
    required this.matchId,
    required this.predictions,
    this.isLocked = false,
    this.lockedAt,
    this.totalPotentialXp = 0,
    this.earnedXp = 0,
  });

  Prediction? getPrediction(PredictionType type) {
    try {
      return predictions.firstWhere((p) => p.type == type);
    } catch (_) {
      return null;
    }
  }

  bool get hasAllPredictions =>
      predictions.length >= PredictionType.values.length;
}

/// Match result with XP breakdown for a user.
class MatchResult {
  final String matchId;
  final String userId;
  final int homeScore;
  final int awayScore;
  final String? firstScorer;
  final String? manOfMatch;
  final List<PredictionResult> predictionResults;
  final int totalXpEarned;
  final int rankChange;
  final int previousRank;
  final int newRank;
  final List<String> unlockedAchievementIds;

  const MatchResult({
    required this.matchId,
    required this.userId,
    required this.homeScore,
    required this.awayScore,
    this.firstScorer,
    this.manOfMatch,
    required this.predictionResults,
    required this.totalXpEarned,
    required this.rankChange,
    required this.previousRank,
    required this.newRank,
    required this.unlockedAchievementIds,
  });

  bool get isImprovement => rankChange > 0;
  String get rankChangeText => rankChange > 0
      ? '↑ $rankChange'
      : (rankChange < 0 ? '↓ ${rankChange.abs()}' : '');
}

/// Individual prediction result.
class PredictionResult {
  final PredictionType type;
  final String userValue;
  final String correctValue;
  final bool isCorrect;
  final int xpEarned;
  final int xpPotential;

  const PredictionResult({
    required this.type,
    required this.userValue,
    required this.correctValue,
    required this.isCorrect,
    required this.xpEarned,
    required this.xpPotential,
  });
}

/// Mock player for scorer/MOTM predictions.
class Player {
  final String id;
  final String name;
  final Team team;
  final int number;
  final String position; // GK, DEF, MID, FWD

  const Player({
    required this.id,
    required this.name,
    required this.team,
    required this.number,
    required this.position,
  });

  static const List<Player> barcelonaPlayers = [
    Player(
      id: 'b_1',
      name: 'Ter Stegen',
      team: Team.barcelona,
      number: 1,
      position: 'GK',
    ),
    Player(
      id: 'b_2',
      name: 'Koundé',
      team: Team.barcelona,
      number: 23,
      position: 'DEF',
    ),
    Player(
      id: 'b_3',
      name: 'Araújo',
      team: Team.barcelona,
      number: 4,
      position: 'DEF',
    ),
    Player(
      id: 'b_4',
      name: 'Cubarsí',
      team: Team.barcelona,
      number: 2,
      position: 'DEF',
    ),
    Player(
      id: 'b_5',
      name: 'Balde',
      team: Team.barcelona,
      number: 3,
      position: 'DEF',
    ),
    Player(
      id: 'b_6',
      name: 'Pedri',
      team: Team.barcelona,
      number: 8,
      position: 'MID',
    ),
    Player(
      id: 'b_7',
      name: 'Gavi',
      team: Team.barcelona,
      number: 6,
      position: 'MID',
    ),
    Player(
      id: 'b_8',
      name: 'De Jong',
      team: Team.barcelona,
      number: 21,
      position: 'MID',
    ),
    Player(
      id: 'b_9',
      name: 'Lamine Yamal',
      team: Team.barcelona,
      number: 19,
      position: 'FWD',
    ),
    Player(
      id: 'b_10',
      name: 'Raphinha',
      team: Team.barcelona,
      number: 11,
      position: 'FWD',
    ),
    Player(
      id: 'b_11',
      name: 'Lewandowski',
      team: Team.barcelona,
      number: 9,
      position: 'FWD',
    ),
    Player(
      id: 'b_12',
      name: 'Ferran Torres',
      team: Team.barcelona,
      number: 7,
      position: 'FWD',
    ),
    Player(
      id: 'b_13',
      name: 'Olmo',
      team: Team.barcelona,
      number: 20,
      position: 'MID',
    ),
    Player(
      id: 'b_14',
      name: 'Casadó',
      team: Team.barcelona,
      number: 17,
      position: 'MID',
    ),
    Player(
      id: 'b_15',
      name: 'Iñaki Peña',
      team: Team.barcelona,
      number: 13,
      position: 'GK',
    ),
  ];

  static const List<Player> madridPlayers = [
    Player(
      id: 'm_1',
      name: 'Courtois',
      team: Team.realMadrid,
      number: 1,
      position: 'GK',
    ),
    Player(
      id: 'm_2',
      name: 'Carvajal',
      team: Team.realMadrid,
      number: 2,
      position: 'DEF',
    ),
    Player(
      id: 'm_3',
      name: 'Militão',
      team: Team.realMadrid,
      number: 3,
      position: 'DEF',
    ),
    Player(
      id: 'm_4',
      name: 'Rüdiger',
      team: Team.realMadrid,
      number: 22,
      position: 'DEF',
    ),
    Player(
      id: 'm_5',
      name: 'Mendy',
      team: Team.realMadrid,
      number: 23,
      position: 'DEF',
    ),
    Player(
      id: 'm_6',
      name: 'Valverde',
      team: Team.realMadrid,
      number: 8,
      position: 'MID',
    ),
    Player(
      id: 'm_7',
      name: 'Camavinga',
      team: Team.realMadrid,
      number: 6,
      position: 'MID',
    ),
    Player(
      id: 'm_8',
      name: 'Bellingham',
      team: Team.realMadrid,
      number: 5,
      position: 'MID',
    ),
    Player(
      id: 'm_9',
      name: 'Mbappé',
      team: Team.realMadrid,
      number: 9,
      position: 'FWD',
    ),
    Player(
      id: 'm_10',
      name: 'Vinícius Jr.',
      team: Team.realMadrid,
      number: 7,
      position: 'FWD',
    ),
    Player(
      id: 'm_11',
      name: 'Rodrygo',
      team: Team.realMadrid,
      number: 11,
      position: 'FWD',
    ),
    Player(
      id: 'm_12',
      name: 'Endrick',
      team: Team.realMadrid,
      number: 16,
      position: 'FWD',
    ),
    Player(
      id: 'm_13',
      name: 'Modrić',
      team: Team.realMadrid,
      number: 10,
      position: 'MID',
    ),
    Player(
      id: 'm_14',
      name: 'Tchouaméni',
      team: Team.realMadrid,
      number: 14,
      position: 'MID',
    ),
    Player(
      id: 'm_15',
      name: 'Lunin',
      team: Team.realMadrid,
      number: 13,
      position: 'GK',
    ),
  ];

  static List<Player> forTeam(Team team) =>
      team == Team.barcelona ? barcelonaPlayers : madridPlayers;

  static List<Player> allPlayers() => [...barcelonaPlayers, ...madridPlayers];

  static Player? findById(String id) {
    try {
      return allPlayers().firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }
}
