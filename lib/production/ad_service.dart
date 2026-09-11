import 'dart:async';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Build-time AdMob configuration.
///
/// Debug builds use Google's public sample units. Release builds use the
/// matching platform's committed public AdMob banner identifier, with optional
/// dart-define overrides for a different release environment.
abstract final class AdMobConfiguration {
  static const _googleSamplePublisherPrefix = 'ca-app-pub-3940256099942544';
  static const androidTestAppId = 'ca-app-pub-3940256099942544~3347511713';
  static const iosTestAppId = 'ca-app-pub-3940256099942544~1458002511';
  static const androidTestBannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const iosTestBannerId = 'ca-app-pub-3940256099942544/2934735716';
  static const androidTestInterstitialId =
      'ca-app-pub-3940256099942544/1033173712';
  static const iosTestInterstitialId = 'ca-app-pub-3940256099942544/4411468910';

  static const _androidProductionBannerId = String.fromEnvironment(
    'ADMOB_ANDROID_BANNER_ID',
    defaultValue: 'ca-app-pub-1153776263866015/2031726336',
  );
  static const _iosProductionBannerId = String.fromEnvironment(
    'ADMOB_IOS_BANNER_ID',
    defaultValue: 'ca-app-pub-1153776263866015/4755655690',
  );
  // Interstitial ads stay disabled in release builds until format-specific
  // unit IDs are created in AdMob. A banner unit must never be reused here.
  static const _androidProductionInterstitialId = String.fromEnvironment(
    'ADMOB_ANDROID_INTERSTITIAL_ID',
  );
  static const _iosProductionInterstitialId = String.fromEnvironment(
    'ADMOB_IOS_INTERSTITIAL_ID',
  );

  static bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static String get bannerAdUnitId => resolveBannerAdUnitId(
    platform: defaultTargetPlatform,
    releaseMode: kReleaseMode,
    androidProductionId: _androidProductionBannerId,
    iosProductionId: _iosProductionBannerId,
  );

  static String get interstitialAdUnitId => resolveInterstitialAdUnitId(
    platform: defaultTargetPlatform,
    releaseMode: kReleaseMode,
    androidProductionId: _androidProductionInterstitialId,
    iosProductionId: _iosProductionInterstitialId,
  );

  static bool get bannerAdsEnabled =>
      isSupportedPlatform && bannerAdUnitId.isNotEmpty;

  static bool get interstitialAdsEnabled =>
      isSupportedPlatform && interstitialAdUnitId.isNotEmpty;

  static bool get adsEnabled => bannerAdsEnabled || interstitialAdsEnabled;

  static bool get usesGoogleTestUnit =>
      bannerAdUnitId == androidTestBannerId ||
      bannerAdUnitId == iosTestBannerId ||
      interstitialAdUnitId == androidTestInterstitialId ||
      interstitialAdUnitId == iosTestInterstitialId;

  @visibleForTesting
  static String resolveBannerAdUnitId({
    required TargetPlatform platform,
    required bool releaseMode,
    String androidProductionId = '',
    String iosProductionId = '',
  }) {
    final testId = switch (platform) {
      TargetPlatform.android => androidTestBannerId,
      TargetPlatform.iOS => iosTestBannerId,
      _ => '',
    };
    // A debug build must never request a live ad, even if a developer happens
    // to have production dart-defines in their shell environment.
    if (!releaseMode) return testId;

    final productionId = switch (platform) {
      TargetPlatform.android => androidProductionId.trim(),
      TargetPlatform.iOS => iosProductionId.trim(),
      _ => '',
    };
    if (!_looksLikeProductionBannerId(productionId) ||
        productionId.startsWith(_googleSamplePublisherPrefix)) {
      return '';
    }
    return productionId;
  }

  @visibleForTesting
  static String resolveInterstitialAdUnitId({
    required TargetPlatform platform,
    required bool releaseMode,
    String androidProductionId = '',
    String iosProductionId = '',
  }) {
    final testId = switch (platform) {
      TargetPlatform.android => androidTestInterstitialId,
      TargetPlatform.iOS => iosTestInterstitialId,
      _ => '',
    };
    if (!releaseMode) return testId;

    final productionId = switch (platform) {
      TargetPlatform.android => androidProductionId.trim(),
      TargetPlatform.iOS => iosProductionId.trim(),
      _ => '',
    };
    if (!_looksLikeProductionAdUnitId(productionId) ||
        productionId.startsWith(_googleSamplePublisherPrefix)) {
      return '';
    }
    return productionId;
  }

  static bool _looksLikeProductionBannerId(String value) =>
      _looksLikeProductionAdUnitId(value);

  static bool _looksLikeProductionAdUnitId(String value) =>
      RegExp(r'^ca-app-pub-\d+/\d+$').hasMatch(value);
}

@immutable
class InterstitialFrequencyState {
  const InterstitialFrequencyState({
    this.completedActivities = 0,
    this.lastShownAt,
    this.shownDay = '',
    this.shownToday = 0,
  });

  final int completedActivities;
  final DateTime? lastShownAt;
  final String shownDay;
  final int shownToday;

  InterstitialFrequencyState copyWith({
    int? completedActivities,
    DateTime? lastShownAt,
    String? shownDay,
    int? shownToday,
  }) => InterstitialFrequencyState(
    completedActivities: completedActivities ?? this.completedActivities,
    lastShownAt: lastShownAt ?? this.lastShownAt,
    shownDay: shownDay ?? this.shownDay,
    shownToday: shownToday ?? this.shownToday,
  );
}

/// A deliberately conservative full-screen-ad policy.
///
/// An interstitial is eligible only after three meaningful, server-confirmed
/// activities, never more often than every 20 minutes, and at most twice per
/// local calendar day. Merely navigating or tapping controls never counts.
class InterstitialFrequencyPolicy {
  const InterstitialFrequencyPolicy({
    this.activitiesRequired = 3,
    this.minimumInterval = const Duration(minutes: 20),
    this.maximumPerDay = 2,
  });

  final int activitiesRequired;
  final Duration minimumInterval;
  final int maximumPerDay;

  InterstitialFrequencyState recordCompletedActivity(
    InterstitialFrequencyState state,
    DateTime now,
  ) {
    final normalized = _normalizeDay(state, now);
    return normalized.copyWith(
      completedActivities: normalized.completedActivities + 1,
    );
  }

  bool canShow(InterstitialFrequencyState state, DateTime now) {
    final normalized = _normalizeDay(state, now);
    if (normalized.completedActivities < activitiesRequired ||
        normalized.shownToday >= maximumPerDay) {
      return false;
    }
    final lastShownAt = normalized.lastShownAt;
    return lastShownAt == null ||
        now.difference(lastShownAt) >= minimumInterval;
  }

  InterstitialFrequencyState markShown(
    InterstitialFrequencyState state,
    DateTime now,
  ) {
    final normalized = _normalizeDay(state, now);
    return InterstitialFrequencyState(
      lastShownAt: now,
      shownDay: _dayKey(now),
      shownToday: normalized.shownToday + 1,
    );
  }

  InterstitialFrequencyState _normalizeDay(
    InterstitialFrequencyState state,
    DateTime now,
  ) {
    if (state.shownDay.isEmpty || state.shownDay == _dayKey(now)) return state;
    return InterstitialFrequencyState(
      completedActivities: state.completedActivities,
      lastShownAt: state.lastShownAt,
      shownDay: _dayKey(now),
    );
  }

  String _dayKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

/// Owns Google UMP consent and Mobile Ads SDK initialization.
///
/// Ad requests stay blocked until UMP reports that ads may be requested. The
/// app asks for updated consent information on every launch and exposes the
/// required privacy-options entry point through Settings.
class AdMobService extends ChangeNotifier {
  AdMobService._();

  static final AdMobService instance = AdMobService._();

  Future<void>? _initialization;
  bool _canShowAds = false;
  bool _privacyOptionsRequired = false;
  bool _sdkInitialized = false;
  InterstitialAd? _interstitial;
  bool _interstitialLoading = false;
  bool _interstitialShowing = false;
  Future<void> _interstitialActivityQueue = Future<void>.value();

  static const _interstitialActivitiesKey =
      'admob_interstitial_completed_activities';
  static const _interstitialLastShownKey = 'admob_interstitial_last_shown';
  static const _interstitialShownDayKey = 'admob_interstitial_shown_day';
  static const _interstitialShownTodayKey = 'admob_interstitial_shown_today';
  static const interstitialFrequencyPolicy = InterstitialFrequencyPolicy();

  bool get canShowAds => AdMobConfiguration.adsEnabled && _canShowAds;
  bool get privacyOptionsRequired =>
      AdMobConfiguration.adsEnabled && _privacyOptionsRequired;

  Future<void> initialize() {
    if (!AdMobConfiguration.adsEnabled) return Future<void>.value();
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    final consentInformation = ConsentInformation.instance;
    final update = Completer<void>();
    consentInformation.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      update.complete,
      (error) {
        debugPrint(
          '[AdMob] Consent information update failed '
          '(${error.errorCode}): ${error.message}',
        );
        update.complete();
      },
    );
    await update.future;

    try {
      await ConsentForm.loadAndShowConsentFormIfRequired((error) {
        if (error != null) {
          debugPrint(
            '[AdMob] Consent form failed '
            '(${error.errorCode}): ${error.message}',
          );
        }
      });
    } catch (error) {
      debugPrint('[AdMob] Consent form unavailable: $error');
    }

    // App Review requires Apple's system ATT choice in addition to Google's
    // regional consent form. Do not initialize the ads SDK or request an ad
    // until the system prompt has completed. Android has no ATT equivalent.
    await _requestTrackingAuthorizationIfNeeded();

    try {
      _privacyOptionsRequired =
          await consentInformation.getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
    } catch (error) {
      debugPrint('[AdMob] Privacy options status unavailable: $error');
    }

    try {
      _canShowAds = await consentInformation.canRequestAds();
      await _configureAndInitializeAdsIfAllowed();
    } catch (error) {
      _canShowAds = false;
      debugPrint('[AdMob] SDK initialization failed: $error');
    }
    notifyListeners();
  }

  Future<void> _requestTrackingAuthorizationIfNeeded() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      final status = await AppTrackingTransparency.trackingAuthorizationStatus;
      if (status != TrackingStatus.notDetermined) return;

      // Give the UMP form time to dismiss. iOS will not present two native
      // permission dialogs simultaneously, and ATT only appears while the app
      // is active.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await AppTrackingTransparency.requestTrackingAuthorization();
    } catch (error) {
      // A restricted/managed device may not permit an ATT prompt. Ads remain
      // privacy-preserving and do not depend on authorization to function.
      debugPrint('[AdMob] ATT authorization unavailable: $error');
    }
  }

  Future<void> showPrivacyOptions() async {
    if (!privacyOptionsRequired) return;
    FormError? formError;
    await ConsentForm.showPrivacyOptionsForm((error) {
      formError = error;
    });
    if (formError != null) {
      throw StateError('Privacy options unavailable: ${formError!.message}');
    }

    final consentInformation = ConsentInformation.instance;
    _privacyOptionsRequired =
        await consentInformation.getPrivacyOptionsRequirementStatus() ==
        PrivacyOptionsRequirementStatus.required;
    try {
      _canShowAds = await consentInformation.canRequestAds();
      await _configureAndInitializeAdsIfAllowed();
    } catch (error) {
      _canShowAds = false;
      debugPrint('[AdMob] SDK initialization failed: $error');
    }
    // Existing banners must be recreated after a privacy choice changes so a
    // request never keeps using stale consent signals.
    notifyListeners();
  }

  Future<void> _configureAndInitializeAdsIfAllowed() async {
    if (!_canShowAds || _sdkInitialized) return;

    // The iOS SDK enables a publisher-scoped first-party identifier by
    // default. Disable that extra identifier as a data-minimization measure;
    // Apple's ATT choice above separately governs IDFA access. This call is a
    // no-op on Android.
    await MobileAds.instance.setSameAppKeyEnabled(false);

    // Abu 3meer is rated 13+. Apply conservative teen treatment to every
    // request and prevent mature ad creatives from being eligible.
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(
        maxAdContentRating: MaxAdContentRating.pg,
        ageRestrictedTreatment: AgeRestrictedTreatment.teen,
      ),
    );
    await MobileAds.instance.initialize();
    _sdkInitialized = true;
    _loadInterstitialIfNeeded();
  }

  /// Records one meaningful, server-confirmed activity and may show a
  /// preloaded interstitial at this natural break. Members never see ads.
  Future<void> noteMeaningfulActivity({required bool hasMemberAccess}) {
    final previous = _interstitialActivityQueue;
    final next = () async {
      await previous;
      try {
        await _noteMeaningfulActivity(hasMemberAccess: hasMemberAccess);
      } catch (error, stackTrace) {
        debugPrint(
          '[AdMob] Interstitial activity tracking failed: '
          '$error\n$stackTrace',
        );
      }
    }();
    _interstitialActivityQueue = next;
    return next;
  }

  Future<void> _noteMeaningfulActivity({required bool hasMemberAccess}) async {
    if (hasMemberAccess ||
        !canShowAds ||
        !AdMobConfiguration.interstitialAdsEnabled ||
        _interstitialShowing) {
      return;
    }

    final preferences = await SharedPreferences.getInstance();
    var state = _readInterstitialState(preferences);
    final now = DateTime.now();
    state = interstitialFrequencyPolicy.recordCompletedActivity(state, now);
    await _writeInterstitialState(preferences, state);
    if (!interstitialFrequencyPolicy.canShow(state, now)) return;

    final ad = _interstitial;
    if (ad == null) {
      _loadInterstitialIfNeeded();
      return;
    }

    // Persist the cap before asking the platform to present. This makes rapid
    // duplicate callbacks fail closed instead of ever exceeding the limit.
    state = interstitialFrequencyPolicy.markShown(state, now);
    await _writeInterstitialState(preferences, state);
    _interstitial = null;
    _interstitialShowing = true;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (shownAd) {
        shownAd.dispose();
        _interstitialShowing = false;
        _loadInterstitialIfNeeded();
      },
      onAdFailedToShowFullScreenContent: (failedAd, error) {
        debugPrint(
          '[AdMob] Interstitial failed to show '
          '(${error.code}): ${error.message}',
        );
        failedAd.dispose();
        _interstitialShowing = false;
        _loadInterstitialIfNeeded();
      },
    );
    try {
      await ad.show();
    } catch (error) {
      debugPrint('[AdMob] Interstitial show failed: $error');
      ad.dispose();
      _interstitialShowing = false;
      _loadInterstitialIfNeeded();
    }
  }

  void _loadInterstitialIfNeeded() {
    if (!_sdkInitialized ||
        !AdMobConfiguration.interstitialAdsEnabled ||
        _interstitial != null ||
        _interstitialLoading ||
        _interstitialShowing) {
      return;
    }
    _interstitialLoading = true;
    InterstitialAd.load(
      adUnitId: AdMobConfiguration.interstitialAdUnitId,
      request: privacyPreservingRequest,
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialLoading = false;
          _interstitial = ad;
        },
        onAdFailedToLoad: (error) {
          _interstitialLoading = false;
          debugPrint(
            '[AdMob] Interstitial failed to load '
            '(${error.code}): ${error.message}',
          );
        },
      ),
    );
  }

  InterstitialFrequencyState _readInterstitialState(
    SharedPreferences preferences,
  ) => InterstitialFrequencyState(
    completedActivities: preferences.getInt(_interstitialActivitiesKey) ?? 0,
    lastShownAt: DateTime.tryParse(
      preferences.getString(_interstitialLastShownKey) ?? '',
    ),
    shownDay: preferences.getString(_interstitialShownDayKey) ?? '',
    shownToday: preferences.getInt(_interstitialShownTodayKey) ?? 0,
  );

  Future<void> _writeInterstitialState(
    SharedPreferences preferences,
    InterstitialFrequencyState state,
  ) async {
    await preferences.setInt(
      _interstitialActivitiesKey,
      state.completedActivities,
    );
    final lastShownAt = state.lastShownAt;
    if (lastShownAt == null) {
      await preferences.remove(_interstitialLastShownKey);
    } else {
      await preferences.setString(
        _interstitialLastShownKey,
        lastShownAt.toIso8601String(),
      );
    }
    await preferences.setString(_interstitialShownDayKey, state.shownDay);
    await preferences.setInt(_interstitialShownTodayKey, state.shownToday);
  }

  /// Requests only non-personalized, restricted-data-processing ads.
  static const privacyPreservingRequest = AdRequest(
    nonPersonalizedAds: true,
    extras: <String, String>{'rdp': '1'},
  );
}
