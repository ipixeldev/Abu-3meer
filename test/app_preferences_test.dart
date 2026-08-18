import 'package:abu_3meer/production/app_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'theme, language, and notification preferences persist locally',
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
      expect(stored.getString('abu_theme_mode'), 'light');
      expect(stored.getString('abu_language'), 'ar');
      expect(stored.getBool('abu_notifications_matches'), isFalse);
      expect(stored.getBool('abu_notifications_challenges'), isFalse);
      expect(stored.getBool('abu_notifications_rewards'), isTrue);
      expect(stored.getBool('abu_notifications_news'), isTrue);
      expect(preferences.locale, const Locale('ar'));
    },
  );
}
