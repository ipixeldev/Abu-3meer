// Mock challenges, achievements, rewards, notifications, and activity.

import 'package:flutter/material.dart';

import '../models/challenge.dart';
import '../models/user.dart';
import '../models/match.dart';
import 'mock_users.dart';
import 'mock_matches.dart';

final List<Challenge> mockChallenges = [
  // ─── Active: Secret Phrase (today's video) ───────────────────
  Challenge(
    id: 'chl_secret_phrase_2024_08_13',
    title: 'Secret Phrase Challenge',
    description: 'Watch today\'s reaction video and enter the secret phrase mentioned by the creator.',
    type: ChallengeType.secretPhrase,
    category: ChallengeCategory.video,
    status: ChallengeStatus.live,
    videoUrl: 'https://youtube.com/watch?v=demo_reaction_2024_08_13',
    correctAnswer: 'visca barca',
    xpReward: 50,
    loyaltyReward: 100,
    memberOnly: false,
    startAt: DateTime(2024, 8, 13, 12, 0),
    endAt: DateTime(2024, 8, 14, 12, 0),
    createdAt: DateTime(2024, 8, 12),
    createdBy: 'admin_creator',
    maxAttempts: 3,
  ),

  // ─── Active: Multiple Choice (video quiz) ────────────────────
  Challenge(
    id: 'chl_video_quiz_2024_08_13',
    title: 'Player of the Match Quiz',
    description:
        'Who did the creator name as Player of the Match in today\'s video?',
    type: ChallengeType.multipleChoice,
    category: ChallengeCategory.video,
    status: ChallengeStatus.live,
    videoUrl: 'https://youtube.com/watch?v=demo_reaction_2024_08_13',
    correctAnswer: 'Lamine Yamal',
    options: ['Lamine Yamal', 'Raphinha', 'Lewandowski', 'Pedri', 'Koundé'],
    xpReward: 30,
    loyaltyReward: 50,
    memberOnly: false,
    startAt: DateTime(2024, 8, 13, 12, 0),
    endAt: DateTime(2024, 8, 14, 12, 0),
    createdAt: DateTime(2024, 8, 12),
    createdBy: 'admin_creator',
    maxAttempts: 2,
  ),

  // ─── Active: Match Challenge (first scorer) ──────────────────
  Challenge(
    id: 'chl_match_first_scorer_2024_08_24',
    title: 'First Scorer Prediction',
    description: 'Who scores the first goal in tonight\'s El Clásico?',
    type: ChallengeType.matchChallenge,
    category: ChallengeCategory.match,
    status: ChallengeStatus.scheduled,
    correctAnswer: '', // Will be set after match
    xpReward: 75,
    loyaltyReward: 150,
    memberOnly: false,
    startAt: DateTime(2024, 8, 24, 18, 0),
    endAt: DateTime(2024, 8, 24, 20, 0), // Ends at kickoff
    createdAt: DateTime(2024, 8, 13),
    createdBy: 'admin_creator',
    maxAttempts: 1,
    matchId: 1, // Link to El Clásico
  ),

  // ─── Active: Knowledge (football trivia) ─────────────────────
  Challenge(
    id: 'chl_knowledge_weekly_2024_w33',
    title: 'Weekly Football Knowledge',
    description:
        'Which player has scored the most El Clásico goals in history?',
    type: ChallengeType.knowledge,
    category: ChallengeCategory.general,
    status: ChallengeStatus.live,
    correctAnswer: 'Lionel Messi',
    options: [
      'Lionel Messi',
      'Cristiano Ronaldo',
      'Alfredo Di Stéfano',
      'Raúl',
      'Karim Benzema',
    ],
    xpReward: 40,
    loyaltyReward: 75,
    memberOnly: false,
    startAt: DateTime(2024, 8, 12, 0, 0),
    endAt: DateTime(2024, 8, 18, 23, 59),
    createdAt: DateTime(2024, 8, 11),
    createdBy: 'admin_creator',
    maxAttempts: 2,
  ),

  // ─── Member-only: Exclusive Challenge ────────────────────────
  Challenge(
    id: 'chl_member_exclusive_2024_08',
    title: 'Member Exclusive: Tactical Analysis',
    description: 'Answer 3 tactical questions from the creator\'s member-only breakdown video.',
    type: ChallengeType.videoQuiz,
    category: ChallengeCategory.special,
    status: ChallengeStatus.live,
    videoUrl: 'https://youtube.com/watch?v=demo_member_tactical_2024_08',
    correctAnswer: 'high press, inverted fullback, third man run',
    xpReward: 100,
    loyaltyReward: 300,
    memberOnly: true,
    startAt: DateTime(2024, 8, 10, 0, 0),
    endAt: DateTime(2024, 8, 17, 23, 59),
    createdAt: DateTime(2024, 8, 9),
    createdBy: 'admin_creator',
    maxAttempts: 3,
  ),

  // ─── Ended: Secret Phrase (yesterday) ────────────────────────
  Challenge(
    id: 'chl_secret_phrase_2024_08_12',
    title: 'Secret Phrase Challenge',
    description:
        'Watch yesterday\'s reaction video and enter the secret phrase.',
    type: ChallengeType.secretPhrase,
    category: ChallengeCategory.video,
    status: ChallengeStatus.ended,
    videoUrl: 'https://youtube.com/watch?v=demo_reaction_2024_08_12',
    correctAnswer: 'mes que un club',
    xpReward: 50,
    loyaltyReward: 100,
    memberOnly: false,
    startAt: DateTime(2024, 8, 12, 12, 0),
    endAt: DateTime(2024, 8, 13, 12, 0),
    createdAt: DateTime(2024, 8, 11),
    createdBy: 'admin_creator',
    maxAttempts: 3,
  ),

  // ─── Ended: Match Challenge (Apr 21 Clásico) ─────────────────
  Challenge(
    id: 'chl_match_result_2024_04_21',
    title: 'El Clásico Final Score',
    description: 'Predict the exact final score of the El Clásico.',
    type: ChallengeType.matchChallenge,
    category: ChallengeCategory.match,
    status: ChallengeStatus.ended,
    correctAnswer: '2-3',
    xpReward: 100,
    loyaltyReward: 200,
    memberOnly: false,
    startAt: DateTime(2024, 4, 21, 18, 0),
    endAt: DateTime(2024, 4, 21, 21, 0),
    createdAt: DateTime(2024, 4, 20),
    createdBy: 'admin_creator',
    maxAttempts: 1,
    matchId: 2,
  ),

  // ─── Ended: Streak Challenge ─────────────────────────────────
  Challenge(
    id: 'chl_streak_7_2024_08',
    title: '7-Day Streak Challenge',
    description:
        'Make at least one prediction every day for 7 consecutive days.',
    type: ChallengeType.streak,
    category: ChallengeCategory.general,
    status: ChallengeStatus.ended,
    correctAnswer: 'completed',
    xpReward: 200,
    loyaltyReward: 500,
    memberOnly: false,
    startAt: DateTime(2024, 8, 1, 0, 0),
    endAt: DateTime(2024, 8, 7, 23, 59),
    createdAt: DateTime(2024, 7, 28),
    createdBy: 'admin_creator',
    maxAttempts: 1,
  ),

  // ─── Draft: Upcoming Special ─────────────────────────────────
  Challenge(
    id: 'chl_special_supercup_2025',
    title: 'Super Cup Special: Predict the Winner',
    description: 'Early prediction for the Spanish Super Cup final.',
    type: ChallengeType.prediction,
    category: ChallengeCategory.special,
    status: ChallengeStatus.draft,
    correctAnswer: '',
    xpReward: 150,
    loyaltyReward: 400,
    memberOnly: false,
    startAt: DateTime(2025, 1, 5, 0, 0),
    endAt: DateTime(2025, 1, 12, 19, 30),
    createdAt: DateTime(2024, 12, 1),
    createdBy: 'admin_creator',
    maxAttempts: 1,
  ),

  // ─── Scheduled: Pre-match hype ───────────────────────────────
  Challenge(
    id: 'chl_hype_clasico_2024_08_24',
    title: 'El Clásico Hype: Your Prediction',
    description: 'Share your bold prediction for the match in the comments.',
    type: ChallengeType.multipleChoice,
    category: ChallengeCategory.match,
    status: ChallengeStatus.scheduled,
    correctAnswer: 'Barcelona 3-1',
    options: [
      'Barcelona 3-1',
      'Barcelona 2-1',
      'Draw 2-2',
      'Real Madrid 2-1',
      'Real Madrid 3-1',
    ],
    xpReward: 25,
    loyaltyReward: 50,
    memberOnly: false,
    startAt: DateTime(2024, 8, 20, 0, 0),
    endAt: DateTime(2024, 8, 24, 19, 30),
    createdAt: DateTime(2024, 8, 15),
    createdBy: 'admin_creator',
    maxAttempts: 1,
  ),
];

/// Demo user's challenge progress.
final Map<String, UserChallengeProgress> demoUserChallengeProgress = {
  'chl_secret_phrase_2024_08_13': UserChallengeProgress(
    challengeId: 'chl_secret_phrase_2024_08_13',
    userId: 'usr_ahmed10',
    attemptsUsed: 0,
    completed: false,
    rewarded: false,
    attempts: [],
  ),
  'chl_video_quiz_2024_08_13': UserChallengeProgress(
    challengeId: 'chl_video_quiz_2024_08_13',
    userId: 'usr_ahmed10',
    attemptsUsed: 0,
    completed: false,
    rewarded: false,
    attempts: [],
  ),
  'chl_knowledge_weekly_2024_w33': UserChallengeProgress(
    challengeId: 'chl_knowledge_weekly_2024_w33',
    userId: 'usr_ahmed10',
    attemptsUsed: 1,
    completed: true,
    rewarded: true,
    completedAt: DateTime(2024, 8, 12, 18, 30),
    attempts: [
      ChallengeAttempt(
        id: 'att_1',
        challengeId: 'chl_knowledge_weekly_2024_w33',
        userId: 'usr_ahmed10',
        answer: 'Lionel Messi',
        isCorrect: true,
        xpAwarded: 40,
        loyaltyAwarded:
            60, // 75 * 0.8 (member bonus would apply but user is ultra)
        attemptedAt: DateTime(2024, 8, 12, 18, 30),
        attemptNumber: 1,
      ),
    ],
  ),
  'chl_secret_phrase_2024_08_12': UserChallengeProgress(
    challengeId: 'chl_secret_phrase_2024_08_12',
    userId: 'usr_ahmed10',
    attemptsUsed: 1,
    completed: true,
    rewarded: true,
    completedAt: DateTime(2024, 8, 12, 19, 15),
    attempts: [
      ChallengeAttempt(
        id: 'att_2',
        challengeId: 'chl_secret_phrase_2024_08_12',
        userId: 'usr_ahmed10',
        answer: 'mes que un club',
        isCorrect: true,
        xpAwarded: 50,
        loyaltyAwarded: 150, // 100 * 1.5 (ultra member)
        attemptedAt: DateTime(2024, 8, 12, 19, 15),
        attemptNumber: 1,
      ),
    ],
  ),
  'chl_match_result_2024_04_21': UserChallengeProgress(
    challengeId: 'chl_match_result_2024_04_21',
    userId: 'usr_ahmed10',
    attemptsUsed: 1,
    completed: true,
    rewarded: true,
    completedAt: DateTime(2024, 4, 22, 0, 30),
    attempts: [
      ChallengeAttempt(
        id: 'att_3',
        challengeId: 'chl_match_result_2024_04_21',
        userId: 'usr_ahmed10',
        answer: '2-3',
        isCorrect: true,
        xpAwarded: 100,
        loyaltyAwarded: 300, // 200 * 1.5
        attemptedAt: DateTime(2024, 4, 22, 0, 30),
        attemptNumber: 1,
      ),
    ],
  ),
  'chl_streak_7_2024_08': UserChallengeProgress(
    challengeId: 'chl_streak_7_2024_08',
    userId: 'usr_ahmed10',
    attemptsUsed: 1,
    completed: true,
    rewarded: true,
    completedAt: DateTime(2024, 8, 7, 22, 0),
    attempts: [
      ChallengeAttempt(
        id: 'att_4',
        challengeId: 'chl_streak_7_2024_08',
        userId: 'usr_ahmed10',
        answer: 'completed',
        isCorrect: true,
        xpAwarded: 200,
        loyaltyAwarded: 750, // 500 * 1.5
        attemptedAt: DateTime(2024, 8, 7, 22, 0),
        attemptNumber: 1,
      ),
    ],
  ),
};

/// Get active challenges for user (respecting member-only).
List<Challenge> getActiveChallengesForUser(User user) {
  final now = DateTime.now();
  return mockChallenges.where((c) {
    if (c.memberOnly && user.membershipTier == MembershipTier.none)
      return false;
    return c.isLiveNow;
  }).toList();
}

/// Get completed challenges for user.
List<Challenge> getCompletedChallengesForUser(User user) {
  return mockChallenges.where((c) {
    final progress =
        demoUserChallengeProgress['${c.id}_${user.id}'] ??
        demoUserChallengeProgress[c.id];
    return progress?.completed == true;
  }).toList();
}

/// Get challenge progress for user.
UserChallengeProgress? getUserChallengeProgress(
  String challengeId,
  String userId,
) {
  return demoUserChallengeProgress['${challengeId}_$userId'] ??
      demoUserChallengeProgress[challengeId];
}
