import 'package:abu_3meer/production/models.dart';
import 'package:abu_3meer/production/production_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('externalHttpUri', () {
    test('adds https to an administrator-entered bare domain', () {
      expect(
        externalHttpUri(' iamr.dev/news?id=7 '),
        Uri.parse('https://iamr.dev/news?id=7'),
      );
    });

    test('preserves complete http and https URLs', () {
      expect(
        externalHttpUri('https://cdn.example.com/banner.png'),
        Uri.parse('https://cdn.example.com/banner.png'),
      );
      expect(
        externalHttpUri('http://example.com/legacy'),
        Uri.parse('http://example.com/legacy'),
      );
    });

    test('rejects relative, unsafe, empty, and hostless URLs', () {
      expect(externalHttpUri('/internal/path'), isNull);
      expect(externalHttpUri('javascript:alert(1)'), isNull);
      expect(externalHttpUri('mailto:owner@example.com'), isNull);
      expect(externalHttpUri('https:///missing-host'), isNull);
      expect(externalHttpUri('   '), isNull);
    });
  });

  group('admin image validation', () {
    test('accepts supported browser and mobile image formats', () {
      expect(
        supportedAdminImageContentType(fileName: 'banner.JPG'),
        'image/jpeg',
      );
      expect(
        supportedAdminImageContentType(
          fileName: 'upload.bin',
          mimeType: 'image/webp',
        ),
        'image/webp',
      );
      expect(
        supportedAdminImageContentType(fileName: 'animation.gif'),
        'image/gif',
      );
    });

    test('rejects files that are not supported images', () {
      expect(
        supportedAdminImageContentType(
          fileName: 'payload.svg',
          mimeType: 'image/svg+xml',
        ),
        isNull,
      );
      expect(
        supportedAdminImageContentType(
          fileName: 'notes.txt',
          mimeType: 'text/plain',
        ),
        isNull,
      );
    });
  });

  group('AbuUserProfile streak data', () {
    test('constructor safely defaults streak fields for legacy callers', () {
      const profile = AbuUserProfile(
        uid: 'legacy-user',
        email: 'fan@example.com',
        username: 'fan_7',
        displayName: 'Fan Seven',
        country: 'Sweden',
        supportedTeam: 'Real Madrid',
        avatarUrl: '',
        role: 'user',
        membershipMultiplier: 1,
        totalPoints: 400,
        monthlyPoints: 120,
        seasonPoints: 300,
        suspended: false,
      );

      expect(profile.currentStreak, 0);
      expect(profile.longestStreak, 0);
      expect(profile.lastActivityAt, isNull);
    });

    test('copyWith updates streak state without losing profile data', () {
      final initialActivity = DateTime.utc(2026, 8, 17);
      final nextActivity = DateTime.utc(2026, 8, 18);
      final original = _profile(
        currentStreak: 3,
        longestStreak: 9,
        lastActivityAt: initialActivity,
      );

      final updated = original.copyWith(
        currentStreak: 4,
        longestStreak: 9,
        lastActivityAt: nextActivity,
      );

      expect(updated.currentStreak, 4);
      expect(updated.longestStreak, 9);
      expect(updated.lastActivityAt, nextActivity);
      expect(updated.uid, original.uid);
      expect(updated.username, original.username);
      expect(updated.totalPoints, original.totalPoints);
      expect(updated.supportedTeam, original.supportedTeam);
    });

    test(
      'copyWith preserves streak state when no streak value is supplied',
      () {
        final activity = DateTime.utc(2026, 8, 18);
        final original = _profile(
          currentStreak: 5,
          longestStreak: 11,
          lastActivityAt: activity,
        );

        final updated = original.copyWith(totalPoints: 450);

        expect(updated.totalPoints, 450);
        expect(updated.currentStreak, 5);
        expect(updated.longestStreak, 11);
        expect(updated.lastActivityAt, activity);
      },
    );
  });

  group('AbuUserProfile location data', () {
    test(
      'keeps the ISO country code through copyWith and uses it for flags',
      () {
        const profile = AbuUserProfile(
          uid: 'location-user',
          email: 'location@example.com',
          username: 'location_user',
          displayName: 'Location User',
          country: 'Sverige',
          countryCode: 'SE',
          supportedTeam: 'Real Madrid',
          avatarUrl: '',
          role: 'user',
          membershipMultiplier: 1,
          totalPoints: 50,
          monthlyPoints: 50,
          seasonPoints: 50,
          suspended: false,
        );

        expect(profile.countryFlag, '🇸🇪');
        expect(profile.copyWith(displayName: 'Saved').countryCode, 'SE');
      },
    );
  });
}

AbuUserProfile _profile({
  required int currentStreak,
  required int longestStreak,
  required DateTime lastActivityAt,
}) => AbuUserProfile(
  uid: 'user-7',
  email: 'fan@example.com',
  username: 'fan_7',
  displayName: 'Fan Seven',
  country: 'Sweden',
  supportedTeam: 'Real Madrid',
  avatarUrl: '',
  role: 'user',
  membershipMultiplier: 1,
  totalPoints: 400,
  monthlyPoints: 120,
  seasonPoints: 300,
  suspended: false,
  currentStreak: currentStreak,
  longestStreak: longestStreak,
  lastActivityAt: lastActivityAt,
);
