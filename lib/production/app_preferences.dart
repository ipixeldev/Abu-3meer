import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AbuLanguage { english, arabic }

class AbuAppPreferences extends ChangeNotifier {
  AbuAppPreferences._();

  static final AbuAppPreferences instance = AbuAppPreferences._();

  static const _themeKey = 'abu_theme_mode';
  static const _languageKey = 'abu_language';
  static const _matchNotificationsKey = 'abu_notifications_matches';
  static const _challengeNotificationsKey = 'abu_notifications_challenges';
  static const _rewardNotificationsKey = 'abu_notifications_rewards';
  static const _newsNotificationsKey = 'abu_notifications_news';

  ThemeMode themeMode = ThemeMode.dark;
  AbuLanguage language = AbuLanguage.english;
  bool matchNotifications = true;
  bool challengeNotifications = true;
  bool rewardNotifications = true;
  bool newsNotifications = false;
  bool _loaded = false;

  Locale get locale => Locale(language == AbuLanguage.arabic ? 'ar' : 'en');
  bool get isArabic => language == AbuLanguage.arabic;

  Future<void> load() async {
    if (_loaded) return;
    final preferences = await SharedPreferences.getInstance();
    themeMode = preferences.getString(_themeKey) == 'light'
        ? ThemeMode.light
        : ThemeMode.dark;
    language = preferences.getString(_languageKey) == 'ar'
        ? AbuLanguage.arabic
        : AbuLanguage.english;
    matchNotifications = preferences.getBool(_matchNotificationsKey) ?? true;
    challengeNotifications =
        preferences.getBool(_challengeNotificationsKey) ?? true;
    rewardNotifications = preferences.getBool(_rewardNotificationsKey) ?? true;
    newsNotifications = preferences.getBool(_newsNotificationsKey) ?? false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode value) async {
    if (themeMode == value) return;
    themeMode = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _themeKey,
      value == ThemeMode.light ? 'light' : 'dark',
    );
  }

  Future<void> setLanguage(AbuLanguage value) async {
    if (language == value) return;
    language = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _languageKey,
      value == AbuLanguage.arabic ? 'ar' : 'en',
    );
  }

  Future<void> setMatchNotifications(bool value) => _setNotificationPreference(
    key: _matchNotificationsKey,
    value: value,
    apply: () => matchNotifications = value,
  );

  Future<void> setChallengeNotifications(bool value) =>
      _setNotificationPreference(
        key: _challengeNotificationsKey,
        value: value,
        apply: () => challengeNotifications = value,
      );

  Future<void> setRewardNotifications(bool value) => _setNotificationPreference(
    key: _rewardNotificationsKey,
    value: value,
    apply: () => rewardNotifications = value,
  );

  Future<void> setNewsNotifications(bool value) => _setNotificationPreference(
    key: _newsNotificationsKey,
    value: value,
    apply: () => newsNotifications = value,
  );

  Future<void> _setNotificationPreference({
    required String key,
    required bool value,
    required VoidCallback apply,
  }) async {
    apply();
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(key, value);
  }
}

String abuText(BuildContext context, String english, String arabic) =>
    Localizations.localeOf(context).languageCode == 'ar' ? arabic : english;
