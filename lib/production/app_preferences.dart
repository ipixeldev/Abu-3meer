import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AbuLanguage { english, arabic }

class AbuAppPreferences extends ChangeNotifier {
  AbuAppPreferences._();

  static final AbuAppPreferences instance = AbuAppPreferences._();

  static const _themeKey = 'abu_theme_mode';
  static const _languageKey = 'abu_language';

  ThemeMode themeMode = ThemeMode.dark;
  AbuLanguage language = AbuLanguage.english;
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
}

String abuText(BuildContext context, String english, String arabic) =>
    Localizations.localeOf(context).languageCode == 'ar' ? arabic : english;
