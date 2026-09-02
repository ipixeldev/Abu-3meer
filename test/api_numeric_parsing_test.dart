import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:abu_3meer/production/api_production_repository.dart';

void main() {
  group('API numeric parsing', () {
    test('accepts PostgreSQL NUMERIC strings used by the points ledger', () {
      expect(parseApiDouble('1.00', 1), 1.0);
      expect(parseApiDouble('2.50', 1), 2.5);
    });

    test('accepts JSON numbers and safe fallbacks', () {
      expect(parseApiInt(50), 50);
      expect(parseApiInt('5'), 5);
      expect(parseApiInt(null, 7), 7);
      expect(parseApiDouble(null, 1), 1.0);
    });

    test(
      'parses current-month and season rank from the shared rank response',
      () {
        final ranks = parseApiUserLeaderboardRanks(<String, dynamic>{
          'monthlyRank': '24',
          'seasonRank': 11,
        });

        expect(ranks.currentMonth, 24);
        expect(ranks.season, 11);
        expect(
          parseApiUserLeaderboardRanks(const <String, dynamic>{}).currentMonth,
          0,
        );
      },
    );

    test(
      'authenticated leaderboard uses the server single-snapshot user row',
      () {
        final source = File('lib/production/api_production_repository.dart')
            .readAsStringSync();
        final methodStart = source.indexOf(
          'Future<LeaderboardSnapshot> fetchLeaderboardSnapshot',
        );
        final methodEnd = source.indexOf(
          'Future<List<LeaderboardEntry>> fetchTopLeaderboard',
          methodStart,
        );
        final method = source.substring(methodStart, methodEnd);

        expect(method, contains('requireAuth: authenticated'));
        expect(method, contains('bypassCache: authenticated'));
        expect(method, contains("response['currentUser'] is Map"));
        expect(method, contains("!response.containsKey('currentUser')"));
      },
    );

    test('parses shared football matches and preserves provider team ids', () {
      final match = parseApiMatchEvent(<String, dynamic>{
        'id': 'external_1234',
        'competition_name': 'La Liga',
        'home_team_id': '133738',
        'away_team_id': '133739',
        'home_team': 'Real Madrid',
        'away_team': 'Barcelona',
        'kickoff_at': '2026-08-30T17:00:00.000Z',
        'predictions_open_at': '2026-08-29T17:00:00.000Z',
        'predictions_close_at': '2026-08-30T17:00:00.000Z',
        'home_score': '2',
        'away_score': 1,
        'status': 'completed',
      });

      expect(match.homeTeamId, '133738');
      expect(match.awayTeamId, '133739');
      expect(match.homeScore, 2);
      expect(match.awayScore, 1);
      expect(match.providerMatchId, 'external_1234');
      expect(match.kickoffAt.toUtc(), DateTime.utc(2026, 8, 30, 17));
    });

    test('maps every managed database status into an Admin Studio state', () {
      Map<String, dynamic> matchWithStatus(String status) => <String, dynamic>{
        'id': 'admin_status',
        'home_team': 'Real Madrid',
        'away_team': 'Malaga',
        'kickoff_at': '2026-08-30T17:00:00.000Z',
        'predictions_open_at': '2026-08-29T17:00:00.000Z',
        'predictions_close_at': '2026-08-30T16:55:00.000Z',
        'status': status,
      };

      expect(parseApiMatchEvent(matchWithStatus('closed')).status, 'locked');
      expect(
        parseApiMatchEvent(matchWithStatus('cancelled')).status,
        'disabled',
      );
      expect(
        parseApiMatchEvent(matchWithStatus('postponed')).status,
        'disabled',
      );
      expect(
        parseApiMatchEvent(matchWithStatus('finished')).status,
        'completed',
      );
    });

    test('embeds PostgreSQL final results in prediction history', () {
      final prediction = parseApiSavedPrediction(<String, dynamic>{
        'id': 'prediction-1',
        'user_id': 'user-1',
        'match_id': 'external_1234',
        'home_score': 2,
        'away_score': 1,
        'first_scorer': 'Kylian Mbappe',
        'points_awarded': 60,
        'rewarded': true,
        'seen_result': false,
        'is_exact_match': true,
        'is_first_scorer_match': true,
        'is_winner_match': true,
        'submitted_at': '2026-08-29T17:00:00.000Z',
        'updated_at': '2026-08-30T19:00:00.000Z',
        'home_team': 'Real Madrid',
        'away_team': 'Malaga',
        'kickoff_at': '2026-08-30T17:00:00.000Z',
        'match_status': 'finished',
        'actual_home_score': 2,
        'actual_away_score': 1,
        'actual_first_scorer': 'Kylian Mbappe',
      });

      expect(prediction.rewarded, isTrue);
      expect(prediction.pointsAwarded, 60);
      expect(prediction.match, isNotNull);
      expect(prediction.match!.status, 'completed');
      expect(prediction.match!.homeScore, 2);
      expect(prediction.match!.awayScore, 1);
      expect(prediction.match!.firstScorer, 'Kylian Mbappe');
      expect(prediction.isPending, isFalse);
      expect(prediction.exactScoreCorrect, isTrue);
      expect(prediction.firstScorerCorrect, isTrue);
      expect(prediction.winnerCorrect, isTrue);
    });

    test('parses server-normalized football team search results', () {
      final team = parseApiFootballTeam(<String, dynamic>{
        'teamId': '133739',
        'name': 'Barcelona',
        'badgeUrl': 'https://example.com/barcelona.png',
        'league': 'Spanish La Liga',
        'country': 'Spain',
      });

      expect(team.teamId, '133739');
      expect(team.name, 'Barcelona');
      expect(team.hasBadge, isTrue);
    });
  });

  group('admin user parsing', () {
    test('maps PostgreSQL admin users into searchable app profiles', () {
      final profile = parseAdminUserProfile(<String, dynamic>{
        'id': 'database-id',
        'firebaseUid': 'firebase-id',
        'email': 'admin@example.com',
        'username': 'admin_user',
        'displayName': 'Admin User',
        'country': 'Sweden',
        'countryCode': 'SE',
        'supportedTeam': 'Real Madrid',
        'avatarUrl': 'https://example.com/avatar.png',
        'role': 'super_admin',
        'isYouTubeMember': true,
        'youtubeChannelLinked': true,
        'youtubeMembershipLevelId': 'gold-level',
        'youtubeMembershipVerifiedAt': '2026-09-01T08:30:00.000Z',
        'youtubeMemberSince': '2026-01-15T12:00:00.000Z',
        'totalPoints': '120',
        'monthlyPoints': 30,
        'seasonPoints': '75',
        'loyaltyPoints': '40',
        'accountStatus': 'active',
        'onboardingCompleted': true,
      });

      expect(profile.uid, 'firebase-id');
      expect(profile.email, 'admin@example.com');
      expect(profile.role, 'superAdmin');
      expect(profile.isYouTubeMember, isTrue);
      expect(profile.youtubeChannelLinked, isTrue);
      expect(profile.youtubeMembershipLevelId, 'gold-level');
      expect(
        profile.youtubeMembershipVerifiedAt?.toUtc(),
        DateTime.utc(2026, 9, 1, 8, 30),
      );
      expect(
        profile.youtubeMemberSince?.toUtc(),
        DateTime.utc(2026, 1, 15, 12),
      );
      expect(profile.totalPoints, 120);
      expect(profile.seasonPoints, 75);
      expect(profile.onboardingComplete, isTrue);
    });

    test('maps account suspension and audit history values', () {
      final profile = parseAdminUserProfile(<String, dynamic>{
        'id': 'database-only-id',
        'accountStatus': 'suspended',
      });
      final adjustment = parseAdminPointAdjustment(<String, dynamic>{
        'id': 'adjustment-id',
        'targetUserId': 'firebase-id',
        'delta': '-25',
        'totalAfter': '100',
        'createdAt': '2026-08-29T12:00:00.000Z',
      });

      expect(profile.uid, 'database-only-id');
      expect(profile.suspended, isTrue);
      expect(profile.youtubeChannelLinked, isFalse);
      expect(adjustment.delta, -25);
      expect(adjustment.totalAfter, 100);
    });
  });
}
