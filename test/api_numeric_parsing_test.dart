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
        'totalPoints': '120',
        'monthlyPoints': 30,
        'seasonPoints': '75',
        'loyaltyPoints': '40',
        'accountStatus': 'active',
        'onboardingCompleted': true,
      });

      expect(profile.uid, 'firebase-id');
      expect(profile.role, 'superAdmin');
      expect(profile.isYouTubeMember, isTrue);
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
      expect(adjustment.delta, -25);
      expect(adjustment.totalAfter, 100);
    });
  });
}
