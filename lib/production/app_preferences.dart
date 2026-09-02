import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AbuLanguage { english, arabic }

/// Bundled typography choices. Each language keeps an independent selection,
/// so switching languages also restores the user's font for that script.
enum AbuFontPreset {
  classicEnglish(
    id: 'classic_english',
    language: AbuLanguage.english,
    englishLabel: 'Classic · Inter + Barlow',
    arabicLabel: 'كلاسيكي · إنتر + بارلو',
    bodyFontFamily: 'Inter',
    displayFontFamily: 'Barlow Condensed',
    fallbackFontFamilies: ['Noto Sans Arabic'],
  ),
  montserrat(
    id: 'montserrat',
    language: AbuLanguage.english,
    englishLabel: 'Montserrat',
    arabicLabel: 'مونتسيرات',
    bodyFontFamily: 'Montserrat',
    displayFontFamily: 'Montserrat',
    fallbackFontFamilies: ['Noto Sans Arabic'],
  ),
  nunitoSans(
    id: 'nunito_sans',
    language: AbuLanguage.english,
    englishLabel: 'Nunito Sans',
    arabicLabel: 'نونيتو سانس',
    bodyFontFamily: 'Nunito Sans',
    displayFontFamily: 'Nunito Sans',
    fallbackFontFamilies: ['Noto Sans Arabic'],
  ),
  cairo(
    id: 'cairo',
    language: AbuLanguage.arabic,
    englishLabel: 'Cairo',
    arabicLabel: 'كايرو',
    bodyFontFamily: 'Cairo',
    displayFontFamily: 'Cairo',
    fallbackFontFamilies: ['Inter'],
  ),
  tajawal(
    id: 'tajawal',
    language: AbuLanguage.arabic,
    englishLabel: 'Tajawal',
    arabicLabel: 'تجوال',
    bodyFontFamily: 'Tajawal',
    displayFontFamily: 'Tajawal',
    fallbackFontFamilies: ['Inter'],
  ),
  notoSansArabic(
    id: 'noto_sans_arabic',
    language: AbuLanguage.arabic,
    englishLabel: 'Noto Sans Arabic',
    arabicLabel: 'نوتو سانس عربي',
    bodyFontFamily: 'Noto Sans Arabic',
    displayFontFamily: 'Noto Sans Arabic',
    fallbackFontFamilies: ['Inter'],
  );

  const AbuFontPreset({
    required this.id,
    required this.language,
    required this.englishLabel,
    required this.arabicLabel,
    required this.bodyFontFamily,
    required this.displayFontFamily,
    required this.fallbackFontFamilies,
  });

  final String id;
  final AbuLanguage language;
  final String englishLabel;
  final String arabicLabel;
  final String bodyFontFamily;
  final String displayFontFamily;
  final List<String> fallbackFontFamilies;

  String labelFor(AbuLanguage interfaceLanguage) =>
      interfaceLanguage == AbuLanguage.arabic ? arabicLabel : englishLabel;

  static List<AbuFontPreset> optionsFor(AbuLanguage language) => values
      .where((preset) => preset.language == language)
      .toList(growable: false);

  static AbuFontPreset fromStoredId(
    String? id, {
    required AbuLanguage language,
  }) => values.firstWhere(
    (preset) => preset.id == id && preset.language == language,
    orElse: () => language == AbuLanguage.arabic
        ? AbuFontPreset.cairo
        : AbuFontPreset.classicEnglish,
  );
}

class AbuAppPreferences extends ChangeNotifier {
  AbuAppPreferences._();

  static final AbuAppPreferences instance = AbuAppPreferences._();

  static const _themeKey = 'abu_theme_mode';
  static const _languageKey = 'abu_language';
  static const _englishFontKey = 'abu_font_english';
  static const _arabicFontKey = 'abu_font_arabic';
  static const _matchNotificationsKey = 'abu_notifications_matches';
  static const _challengeNotificationsKey = 'abu_notifications_challenges';
  static const _newsNotificationsKey = 'abu_notifications_news';

  ThemeMode themeMode = ThemeMode.dark;
  AbuLanguage language = AbuLanguage.english;
  AbuFontPreset englishFontPreset = AbuFontPreset.classicEnglish;
  AbuFontPreset arabicFontPreset = AbuFontPreset.cairo;
  bool matchNotifications = true;
  bool challengeNotifications = true;
  bool newsNotifications = false;
  bool _loaded = false;

  Locale get locale => Locale(language == AbuLanguage.arabic ? 'ar' : 'en');
  bool get isArabic => language == AbuLanguage.arabic;
  AbuFontPreset get activeFontPreset =>
      isArabic ? arabicFontPreset : englishFontPreset;
  List<AbuFontPreset> get availableFontPresets =>
      AbuFontPreset.optionsFor(language);

  Future<void> load() async {
    if (_loaded) return;
    final preferences = await SharedPreferences.getInstance();
    // Abu 3meer is intentionally dark-only. Normalize legacy preferences so
    // an old light-mode value can never reappear after an upgrade.
    themeMode = ThemeMode.dark;
    await preferences.setString(_themeKey, 'dark');
    language = preferences.getString(_languageKey) == 'ar'
        ? AbuLanguage.arabic
        : AbuLanguage.english;
    englishFontPreset = AbuFontPreset.fromStoredId(
      preferences.getString(_englishFontKey),
      language: AbuLanguage.english,
    );
    arabicFontPreset = AbuFontPreset.fromStoredId(
      preferences.getString(_arabicFontKey),
      language: AbuLanguage.arabic,
    );
    matchNotifications = preferences.getBool(_matchNotificationsKey) ?? true;
    challengeNotifications =
        preferences.getBool(_challengeNotificationsKey) ?? true;
    newsNotifications = preferences.getBool(_newsNotificationsKey) ?? false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode value) async {
    if (themeMode != ThemeMode.dark) {
      themeMode = ThemeMode.dark;
      notifyListeners();
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_themeKey, 'dark');
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

  Future<void> setFontPreset(AbuFontPreset value) async {
    if (value.language != language) {
      throw ArgumentError.value(
        value,
        'value',
        'Font preset must match the currently selected language.',
      );
    }
    if (activeFontPreset == value) return;
    if (language == AbuLanguage.arabic) {
      arabicFontPreset = value;
    } else {
      englishFontPreset = value;
    }
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      language == AbuLanguage.arabic ? _arabicFontKey : _englishFontKey,
      value.id,
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

/// Returns a localized, user-facing description for a point-ledger row.
///
/// Point reasons historically came from the server as English prose, and the
/// original sign-up reason even contained English and Arabic in the same
/// value. Deriving the presentation from [sourceType] keeps existing rows
/// readable after a language change without rewriting the immutable ledger.
String localizedPointTransactionReason({
  required String sourceType,
  required String storedReason,
  required AbuLanguage language,
}) {
  final kind = _pointTransactionKind(sourceType, storedReason);
  final isArabic = language == AbuLanguage.arabic;
  final localized = switch (kind) {
    _PointTransactionKind.signupBonus =>
      isArabic ? 'مكافأة التسجيل' : 'Signup bonus',
    _PointTransactionKind.dailyStreak =>
      isArabic ? 'مكافأة الدخول اليومي' : 'Daily streak check-in',
    _PointTransactionKind.exactPrediction =>
      isArabic ? 'توقع النتيجة الصحيحة' : 'Correct score prediction',
    _PointTransactionKind.firstScorer =>
      isArabic ? 'توقع أول مسجل' : 'First scorer prediction',
    _PointTransactionKind.matchWinner =>
      isArabic ? 'توقع الفائز بالمباراة' : 'Match winner prediction',
    _PointTransactionKind.videoChallenge =>
      isArabic ? 'إكمال تحدي الفيديو' : 'Video challenge completed',
    _PointTransactionKind.playerCard =>
      isArabic ? 'إجابة تخمين اللاعب' : 'Player Guess answered',
    _PointTransactionKind.achievement =>
      isArabic ? 'مكافأة إنجاز' : 'Achievement bonus',
    _PointTransactionKind.adminAdjustment =>
      isArabic
          ? 'تعديل النقاط من المشرف'
          : _englishPointReason(storedReason, fallback: 'Points adjustment'),
    _PointTransactionKind.unknown =>
      isArabic
          ? 'مكافأة نقاط'
          : _englishPointReason(storedReason, fallback: 'Points awarded'),
  };
  return localized;
}

/// Returns the localized category shown underneath a point transaction.
String localizedPointSourceLabel({
  required String sourceType,
  required AbuLanguage language,
}) {
  final isArabic = language == AbuLanguage.arabic;
  return switch (_pointTransactionKind(sourceType, '')) {
    _PointTransactionKind.signupBonus =>
      isArabic ? 'مكافأة التسجيل' : 'Signup bonus',
    _PointTransactionKind.dailyStreak =>
      isArabic ? 'الدخول اليومي' : 'Daily streak',
    _PointTransactionKind.exactPrediction => isArabic ? 'توقع' : 'Prediction',
    _PointTransactionKind.firstScorer => isArabic ? 'أول مسجل' : 'First scorer',
    _PointTransactionKind.matchWinner =>
      isArabic ? 'الفائز بالمباراة' : 'Match winner',
    _PointTransactionKind.videoChallenge =>
      isArabic ? 'تحدي الفيديو' : 'Video challenge',
    _PointTransactionKind.playerCard =>
      isArabic ? 'تخمين اللاعب' : 'Player Guess',
    _PointTransactionKind.achievement => isArabic ? 'إنجاز' : 'Achievement',
    _PointTransactionKind.adminAdjustment =>
      isArabic ? 'تعديل نقاط' : 'Points adjustment',
    _PointTransactionKind.unknown => isArabic ? 'أخرى' : 'Other',
  };
}

enum _PointTransactionKind {
  signupBonus,
  dailyStreak,
  exactPrediction,
  firstScorer,
  matchWinner,
  videoChallenge,
  playerCard,
  achievement,
  adminAdjustment,
  unknown,
}

_PointTransactionKind _pointTransactionKind(String sourceType, String reason) {
  final source = sourceType.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final normalizedReason = reason.toLowerCase();

  if ({'signupbonus', 'signup', 'registrationbonus'}.contains(source) ||
      ((normalizedReason.contains('sign-up') ||
              normalizedReason.contains('signup')) &&
          normalizedReason.contains('bonus')) ||
      reason.contains('مكافأة التسجيل')) {
    return _PointTransactionKind.signupBonus;
  }
  if ({'dailystreak', 'streak'}.contains(source) ||
      normalizedReason.contains('daily streak')) {
    return _PointTransactionKind.dailyStreak;
  }
  if ({'predictionexact', 'exactprediction', 'exactscore'}.contains(source) ||
      normalizedReason.contains('exact score')) {
    return _PointTransactionKind.exactPrediction;
  }
  if ({'predictionscorer', 'firstscorer'}.contains(source) ||
      normalizedReason.contains('first scorer')) {
    return _PointTransactionKind.firstScorer;
  }
  if ({
        'predictionwinner',
        'predictionwin',
        'winneroutcome',
        'matchwinner',
      }.contains(source) ||
      normalizedReason.contains('winner outcome') ||
      normalizedReason.contains('match winner')) {
    return _PointTransactionKind.matchWinner;
  }
  if ({'playercard'}.contains(source) ||
      normalizedReason.contains('player card')) {
    return _PointTransactionKind.playerCard;
  }
  if ({'videophrase', 'videoquestion', 'videochallenge'}.contains(source) ||
      normalizedReason.contains('solved challenge') ||
      normalizedReason.contains('challenge completed')) {
    return _PointTransactionKind.videoChallenge;
  }
  if ({'achievement', 'achievementbonus'}.contains(source) ||
      normalizedReason.startsWith('achievement:')) {
    return _PointTransactionKind.achievement;
  }
  if ({'adminadjustment', 'pointsadjustment'}.contains(source) ||
      normalizedReason.startsWith('admin adjustment')) {
    return _PointTransactionKind.adminAdjustment;
  }
  return _PointTransactionKind.unknown;
}

String _englishPointReason(String storedReason, {required String fallback}) {
  var value = storedReason.trim();
  if (value.isEmpty) return fallback;

  // Legacy sign-up rows used an Arabic translation in parentheses. Strip any
  // Arabic-only fragments when rendering English so the two locales never
  // leak into one another.
  value = value
      .replaceAll(RegExp(r'\s*[\(\[][^\)\]]*[\u0600-\u06ff][^\)\]]*[\)\]]'), '')
      .replaceAll(RegExp(r'[\u0600-\u06ff]+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'\s*[\u00b7|\-]\s*$'), '')
      .trim();
  return value.isEmpty ? fallback : value;
}
