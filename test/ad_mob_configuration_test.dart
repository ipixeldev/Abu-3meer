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
  });
}
