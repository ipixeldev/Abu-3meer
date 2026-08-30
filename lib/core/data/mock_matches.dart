// Mock matches — 6 matches including El Clásico.

import 'package:flutter/material.dart';

import '../models/match.dart';
import '../models/user.dart';

final List<Match> mockMatches = [
  // ─── Upcoming El Clásico (predictions open) ──────────────────
  Match(
    id: 'mtc_clasico_2024_08_24',
    homeTeamName: 'Barcelona',
    awayTeamName: 'Real Madrid',
    homeTeam: Team.barcelona,
    awayTeam: Team.realMadrid,
    competition: Competition.laLiga,
    kickoff: DateTime(2024, 8, 24, 20, 0), // Aug 24, 20:00
    predictionDeadline: DateTime(2024, 8, 24, 19, 30), // 30 min before
    stadium: 'Estadi Olímpic Lluís Companys',
    venueCity: 'Barcelona',
    status: MatchStatus.predictionsOpen,
    participatingFans: 12847,
    totalXpPool: 2150000,
    createdAt: DateTime(2024, 8, 1),
    updatedAt: DateTime(2024, 8, 13),
  ),

  // ─── Recent finished El Clásico ──────────────────────────────
  Match(
    id: 'mtc_clasico_2024_04_21',
    homeTeamName: 'Real Madrid',
    awayTeamName: 'Barcelona',
    homeTeam: Team.realMadrid,
    awayTeam: Team.barcelona,
    competition: Competition.laLiga,
    kickoff: DateTime(2024, 4, 21, 21, 0),
    predictionDeadline: DateTime(2024, 4, 21, 20, 30),
    stadium: 'Santiago Bernabéu',
    venueCity: 'Madrid',
    status: MatchStatus.finished,
    homeScore: 2,
    awayScore: 3,
    firstScorerId: 'b_9', // Lamine Yamal
    manOfMatchId: 'b_6', // Pedri
    participatingFans: 18420,
    totalXpPool: 3200000,
    createdAt: DateTime(2024, 3, 15),
    updatedAt: DateTime(2024, 4, 22),
  ),

  // ─── Upcoming Champions League ───────────────────────────────
  Match(
    id: 'mtc_ucl_2024_09_17',
    homeTeamName: 'Barcelona',
    awayTeamName: 'Bayern Munich',
    homeTeam: Team.barcelona,
    awayTeam: Team.barcelona, // Opponent not in our teams
    competition: Competition.championsLeague,
    kickoff: DateTime(2024, 9, 17, 21, 0),
    predictionDeadline: DateTime(2024, 9, 17, 20, 30),
    stadium: 'Estadi Olímpic Lluís Companys',
    venueCity: 'Barcelona',
    status: MatchStatus.scheduled,
    participatingFans: 0,
    totalXpPool: 0,
    createdAt: DateTime(2024, 8, 10),
  ),

  // ─── Finished La Liga vs Atlético ────────────────────────────
  Match(
    id: 'mtc_laliga_atm_2024_05_12',
    homeTeamName: 'Atlético Madrid',
    awayTeamName: 'Real Madrid',
    homeTeam: Team.realMadrid, // Using Madrid for away team color
    awayTeam: Team.realMadrid,
    competition: Competition.laLiga,
    kickoff: DateTime(2024, 5, 12, 18, 30),
    predictionDeadline: DateTime(2024, 5, 12, 18, 0),
    stadium: 'Cívitas Metropolitano',
    venueCity: 'Madrid',
    status: MatchStatus.finished,
    homeScore: 1,
    awayScore: 2,
    firstScorerId: 'm_9', // Mbappé
    manOfMatchId: 'm_8', // Bellingham
    participatingFans: 14200,
    totalXpPool: 2450000,
    createdAt: DateTime(2024, 4, 20),
    updatedAt: DateTime(2024, 5, 13),
  ),

  // ─── Finished Copa del Rey ───────────────────────────────────
  Match(
    id: 'mtc_cdr_2024_04_06',
    homeTeamName: 'Barcelona',
    awayTeamName: 'Athletic Club',
    homeTeam: Team.barcelona,
    awayTeam: Team.barcelona,
    competition: Competition.copaDelRey,
    kickoff: DateTime(2024, 4, 6, 22, 0),
    predictionDeadline: DateTime(2024, 4, 6, 21, 30),
    stadium: 'Estadi Olímpic Lluís Companys',
    venueCity: 'Barcelona',
    status: MatchStatus.finished,
    homeScore: 4,
    awayScore: 1,
    firstScorerId: 'b_11', // Lewandowski
    manOfMatchId: 'b_11', // Lewandowski
    participatingFans: 11800,
    totalXpPool: 1980000,
    createdAt: DateTime(2024, 3, 10),
    updatedAt: DateTime(2024, 4, 7),
  ),

  // ─── Upcoming Super Cup ──────────────────────────────────────
  Match(
    id: 'mtc_supercup_2025_01_12',
    homeTeamName: 'Real Madrid',
    awayTeamName: 'Barcelona',
    homeTeam: Team.realMadrid,
    awayTeam: Team.barcelona,
    competition: Competition.superCup,
    kickoff: DateTime(2025, 1, 12, 20, 0),
    predictionDeadline: DateTime(2025, 1, 12, 19, 30),
    stadium: 'King Fahd International Stadium',
    venueCity: 'Riyadh',
    status: MatchStatus.scheduled,
    participatingFans: 0,
    totalXpPool: 0,
    createdAt: DateTime(2024, 11, 1),
  ),
];

/// Get the "next" match (upcoming with predictions open or scheduled).
Match? getNextMatch() {
  final now = DateTime.now();
  final upcoming = mockMatches.where((m) => m.kickoff.isAfter(now)).toList()
    ..sort((a, b) => a.kickoff.compareTo(b.kickoff));
  return upcoming.isNotEmpty ? upcoming.first : null;
}

/// Get the current El Clásico (predictions open).
Match? getCurrentClasico() {
  final now = DateTime.now();
  try {
    return mockMatches.firstWhere(
      (m) =>
          m.isElClasico &&
          m.predictionsOpen &&
          m.predictionDeadline.isAfter(now),
    );
  } catch (_) {
    return null;
  }
}

/// Get finished matches for results/history.
List<Match> getFinishedMatches() =>
    mockMatches.where((m) => m.isFinished).toList()
      ..sort((a, b) => b.kickoff.compareTo(a.kickoff));

/// Get upcoming matches.
List<Match> getUpcomingMatches() {
  final now = DateTime.now();
  return mockMatches.where((m) => m.kickoff.isAfter(now)).toList()
    ..sort((a, b) => a.kickoff.compareTo(b.kickoff));
}

/// Find match by ID.
Match? findMatchById(String id) {
  try {
    return mockMatches.firstWhere((m) => m.id == id);
  } catch (_) {
    return null;
  }
}

/// Prediction config for a match (admin configurable).
class MatchPredictionConfig {
  final String matchId;
  final Map<PredictionType, int> xpRewards;
  final bool enabled;

  const MatchPredictionConfig({
    required this.matchId,
    required this.xpRewards,
    this.enabled = true,
  });

  int get totalPotentialXp => xpRewards.values.fold(0, (a, b) => a + b);
}

/// Default prediction configs per match.
final Map<String, MatchPredictionConfig> mockPredictionConfigs = {
  'mtc_clasico_2024_08_24': MatchPredictionConfig(
    matchId: 'mtc_clasico_2024_08_24',
    xpRewards: {
      PredictionType.matchWinner: 20,
      PredictionType.correctScore: 50,
      PredictionType.firstScorer: 30,
      PredictionType.manOfMatch: 25,
    },
  ),
  'mtc_clasico_2024_04_21': MatchPredictionConfig(
    matchId: 'mtc_clasico_2024_04_21',
    xpRewards: {
      PredictionType.matchWinner: 20,
      PredictionType.correctScore: 50,
      PredictionType.firstScorer: 30,
      PredictionType.manOfMatch: 25,
    },
  ),
  'mtc_ucl_2024_09_17': MatchPredictionConfig(
    matchId: 'mtc_ucl_2024_09_17',
    xpRewards: {
      PredictionType.matchWinner: 25,
      PredictionType.correctScore: 60,
      PredictionType.firstScorer: 35,
      PredictionType.manOfMatch: 30,
    },
  ),
  'mtc_laliga_atm_2024_05_12': MatchPredictionConfig(
    matchId: 'mtc_laliga_atm_2024_05_12',
    xpRewards: {
      PredictionType.matchWinner: 20,
      PredictionType.correctScore: 50,
      PredictionType.firstScorer: 30,
      PredictionType.manOfMatch: 25,
    },
  ),
  'mtc_cdr_2024_04_06': MatchPredictionConfig(
    matchId: 'mtc_cdr_2024_04_06',
    xpRewards: {
      PredictionType.matchWinner: 15,
      PredictionType.correctScore: 40,
      PredictionType.firstScorer: 25,
      PredictionType.manOfMatch: 20,
    },
  ),
  'mtc_supercup_2025_01_12': MatchPredictionConfig(
    matchId: 'mtc_supercup_2025_01_12',
    xpRewards: {
      PredictionType.matchWinner: 30,
      PredictionType.correctScore: 75,
      PredictionType.firstScorer: 40,
      PredictionType.manOfMatch: 35,
    },
  ),
};

/// Get config for a match.
MatchPredictionConfig? getPredictionConfig(String matchId) =>
    mockPredictionConfigs[matchId];

/// Demo user's predictions for the current Clásico.
/// This simulates what the user has already predicted (or not).
Map<PredictionType, dynamic> demoUserPredictions = {
  // Empty initially - user hasn't predicted yet for the upcoming match
};

/// Demo user's locked predictions for the finished Clásico (Apr 21).
Map<PredictionType, dynamic> demoUserLockedPredictionsApr21 = {
  PredictionType.matchWinner: Team.barcelona,
  PredictionType.correctScore: '2-3',
  PredictionType.firstScorer: 'b_9', // Lamine Yamal
  PredictionType.manOfMatch: 'b_6', // Pedri
};

/// Demo user's predictions for the Atlético match (May 12).
Map<PredictionType, dynamic> demoUserLockedPredictionsMay12 = {
  PredictionType.matchWinner: Team.realMadrid,
  PredictionType.correctScore: '1-2',
  PredictionType.firstScorer: 'm_9', // Mbappé
  PredictionType.manOfMatch: 'm_8', // Bellingham
};
