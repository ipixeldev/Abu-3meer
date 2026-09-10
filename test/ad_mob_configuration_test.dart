import 'package:abu_3meer/production/ad_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdMobConfiguration', () {
    test('debug builds use the correct official platform test units', () {
      expect(
        AdMobConfiguration.resolveBannerAdUnitId(
          platform: TargetPlatform.android,
          releaseMode: false,
        ),
        AdMobConfiguration.androidTestBannerId,
      );
      expect(
        AdMobConfiguration.resolveBannerAdUnitId(
          platform: TargetPlatform.iOS,
          releaseMode: false,
          iosProductionId: 'ca-app-pub-1234567890123456/1234567890',
        ),
        AdMobConfiguration.iosTestBannerId,
      );
    });

    test('release builds fail closed when no production unit is supplied', () {
      expect(
        AdMobConfiguration.resolveBannerAdUnitId(
          platform: TargetPlatform.android,
          releaseMode: true,
        ),
        isEmpty,
      );
      expect(
        AdMobConfiguration.resolveBannerAdUnitId(
          platform: TargetPlatform.iOS,
          releaseMode: true,
        ),
        isEmpty,
      );
    });

    test('release builds use only the matching platform production unit', () {
      expect(
        AdMobConfiguration.resolveBannerAdUnitId(
          platform: TargetPlatform.android,
          releaseMode: true,
          androidProductionId: ' ca-app-pub-1234567890123456/1234567890 ',
          iosProductionId: 'ca-app-pub-9876543210987654/9876543210',
        ),
        'ca-app-pub-1234567890123456/1234567890',
      );
      expect(
        AdMobConfiguration.resolveBannerAdUnitId(
          platform: TargetPlatform.iOS,
          releaseMode: true,
          androidProductionId: 'ca-app-pub-1234567890123456/1234567890',
          iosProductionId: ' ca-app-pub-9876543210987654/9876543210 ',
        ),
        'ca-app-pub-9876543210987654/9876543210',
      );
    });

    test('release builds reject malformed and Google sample units', () {
      expect(
        AdMobConfiguration.resolveBannerAdUnitId(
          platform: TargetPlatform.android,
          releaseMode: true,
          androidProductionId: 'not-an-ad-unit',
        ),
        isEmpty,
      );
      expect(
        AdMobConfiguration.resolveBannerAdUnitId(
          platform: TargetPlatform.iOS,
          releaseMode: true,
          iosProductionId: AdMobConfiguration.iosTestBannerId,
        ),
        isEmpty,
      );
      expect(
        AdMobConfiguration.resolveBannerAdUnitId(
          platform: TargetPlatform.android,
          releaseMode: true,
          androidProductionId: 'ca-app-pub-3940256099942544/4411468910',
        ),
        isEmpty,
      );
    });

    test('unsupported platforms never return an ad unit', () {
      expect(
        AdMobConfiguration.resolveBannerAdUnitId(
          platform: TargetPlatform.macOS,
          releaseMode: false,
          androidProductionId: 'ca-app-pub-1234567890123456/1234567890',
          iosProductionId: 'ca-app-pub-9876543210987654/9876543210',
        ),
        isEmpty,
      );
    });

    test('debug builds use official interstitial test units', () {
      expect(
        AdMobConfiguration.resolveInterstitialAdUnitId(
          platform: TargetPlatform.android,
          releaseMode: false,
          androidProductionId: 'ca-app-pub-1234567890123456/1234567890',
        ),
        AdMobConfiguration.androidTestInterstitialId,
      );
      expect(
        AdMobConfiguration.resolveInterstitialAdUnitId(
          platform: TargetPlatform.iOS,
          releaseMode: false,
        ),
        AdMobConfiguration.iosTestInterstitialId,
      );
    });

    test(
      'release interstitials fail closed without a format-specific unit',
      () {
        expect(
          AdMobConfiguration.resolveInterstitialAdUnitId(
            platform: TargetPlatform.android,
            releaseMode: true,
          ),
          isEmpty,
        );
        expect(
          AdMobConfiguration.resolveInterstitialAdUnitId(
            platform: TargetPlatform.iOS,
            releaseMode: true,
            iosProductionId: AdMobConfiguration.iosTestInterstitialId,
          ),
          isEmpty,
        );
      },
    );

    test('release interstitials accept matching production-format units', () {
      expect(
        AdMobConfiguration.resolveInterstitialAdUnitId(
          platform: TargetPlatform.android,
          releaseMode: true,
          androidProductionId: ' ca-app-pub-1234567890123456/2345678901 ',
          iosProductionId: 'ca-app-pub-9876543210987654/3456789012',
        ),
        'ca-app-pub-1234567890123456/2345678901',
      );
    });
  });

  group('InterstitialFrequencyPolicy', () {
    const policy = InterstitialFrequencyPolicy();
    final morning = DateTime(2026, 9, 10, 10);

    test('requires three completed activities', () {
      var state = const InterstitialFrequencyState();
      state = policy.recordCompletedActivity(state, morning);
      state = policy.recordCompletedActivity(state, morning);
      expect(policy.canShow(state, morning), isFalse);

      state = policy.recordCompletedActivity(state, morning);
      expect(policy.canShow(state, morning), isTrue);
    });

    test('enforces a twenty-minute interval after an impression', () {
      var state = const InterstitialFrequencyState(completedActivities: 3);
      state = policy.markShown(state, morning);
      for (var i = 0; i < 3; i += 1) {
        state = policy.recordCompletedActivity(
          state,
          morning.add(const Duration(minutes: 5)),
        );
      }

      expect(
        policy.canShow(state, morning.add(const Duration(minutes: 19))),
        isFalse,
      );
      expect(
        policy.canShow(state, morning.add(const Duration(minutes: 20))),
        isTrue,
      );
    });

    test('never allows more than two impressions per local day', () {
      var state = const InterstitialFrequencyState(completedActivities: 3);
      state = policy.markShown(state, morning);
      state = state.copyWith(completedActivities: 3);
      state = policy.markShown(state, morning.add(const Duration(minutes: 20)));
      state = state.copyWith(completedActivities: 3);

      expect(
        policy.canShow(state, morning.add(const Duration(hours: 1))),
        isFalse,
      );
      expect(
        policy.canShow(state, morning.add(const Duration(days: 1))),
        isTrue,
      );
    });
  });
}
