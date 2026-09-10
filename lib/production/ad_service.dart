import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

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

  static const _androidProductionBannerId = String.fromEnvironment(
    'ADMOB_ANDROID_BANNER_ID',
    defaultValue: 'ca-app-pub-1153776263866015/2031726336',
  );
  static const _iosProductionBannerId = String.fromEnvironment(
    'ADMOB_IOS_BANNER_ID',
    defaultValue: 'ca-app-pub-1153776263866015/4755655690',
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

  static bool get adsEnabled =>
      isSupportedPlatform && bannerAdUnitId.isNotEmpty;

  static bool get usesGoogleTestUnit =>
      bannerAdUnitId == androidTestBannerId ||
      bannerAdUnitId == iosTestBannerId;

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

  static bool _looksLikeProductionBannerId(String value) =>
      RegExp(r'^ca-app-pub-\d+/\d+$').hasMatch(value);
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
  }

  /// Requests only non-personalized, restricted-data-processing ads.
  static const privacyPreservingRequest = AdRequest(
    nonPersonalizedAds: true,
    extras: <String, String>{'rdp': '1'},
  );
}
