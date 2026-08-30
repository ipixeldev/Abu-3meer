import 'package:abu_3meer/production/app_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'dark-only theme, language, and notification preferences persist locally',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = AbuAppPreferences.instance;

      await preferences.setThemeMode(ThemeMode.light);
      await preferences.setLanguage(AbuLanguage.arabic);
      await preferences.setMatchNotifications(false);
      await preferences.setChallengeNotifications(false);
      await preferences.setRewardNotifications(true);
      await preferences.setNewsNotifications(true);

      final stored = await SharedPreferences.getInstance();
      expect(stored.getString('abu_theme_mode'), 'dark');
      expect(preferences.themeMode, ThemeMode.dark);
      expect(stored.getString('abu_language'), 'ar');
      expect(stored.getBool('abu_notifications_matches'), isFalse);
      expect(stored.getBool('abu_notifications_challenges'), isFalse);
      expect(stored.getBool('abu_notifications_rewards'), isTrue);
      expect(stored.getBool('abu_notifications_news'), isTrue);
      expect(preferences.locale, const Locale('ar'));
    },
  );

  group('point transaction localization', () {
    test('canonicalizes legacy mixed-language signup bonuses', () {
      const legacyReason =
          'Welcome to Abu 3meer · Sign-up bonus (مكافأة التسجيل)';

      expect(
        localizedPointTransactionReason(
          sourceType: 'signup_bonus',
          storedReason: legacyReason,
          language: AbuLanguage.english,
        ),
        'Signup bonus',
      );
      expect(
        localizedPointTransactionReason(
          sourceType: 'signup_bonus',
          storedReason: legacyReason,
          language: AbuLanguage.arabic,
        ),
        'مكافأة التسجيل',
      );
    });

    test('recognizes a legacy signup reason even without a source type', () {
      expect(
        localizedPointTransactionReason(
          sourceType: '',
          storedReason: 'Welcome to Abu 3meer · Sign-up bonus (مكافأة التسجيل)',
          language: AbuLanguage.english,
        ),
        'Signup bonus',
      );
    });

    test('translates API and legacy point-source aliases', () {
      expect(
        localizedPointTransactionReason(
          sourceType: 'daily_streak',
          storedReason: 'Daily streak check-in (Day 2)',
          language: AbuLanguage.arabic,
        ),
        'مكافأة الدخول اليومي',
      );
      expect(
        localizedPointTransactionReason(
          sourceType: 'exactPrediction',
          storedReason: 'Exact score: Real Madrid vs Malaga',
          language: AbuLanguage.english,
        ),
        'Correct score prediction',
      );
      expect(
        localizedPointSourceLabel(
          sourceType: 'prediction_scorer',
          language: AbuLanguage.arabic,
        ),
        'أول مسجل',
      );
    });

    test('does not leak Arabic fragments into an English fallback', () {
      final label = localizedPointTransactionReason(
        sourceType: 'custom_event',
        storedReason: 'Special award (مكافأة خاصة)',
        language: AbuLanguage.english,
      );

      expect(label, 'Special award');
      expect(label, isNot(contains(RegExp(r'[\u0600-\u06ff]'))));
    });
  });
}
