import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS declares and requests ATT before Mobile Ads starts', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    final service = File('lib/production/ad_service.dart').readAsStringSync();

    expect(pubspec, contains('app_tracking_transparency:'));
    expect(infoPlist, contains('<key>NSUserTrackingUsageDescription</key>'));

    final consentForm = service.indexOf(
      'ConsentForm.loadAndShowConsentFormIfRequired',
    );
    final attRequest = service.indexOf(
      'await _requestTrackingAuthorizationIfNeeded();',
    );
    final adsInitialization = service.indexOf(
      'await MobileAds.instance.initialize();',
    );

    expect(consentForm, greaterThanOrEqualTo(0));
    expect(attRequest, greaterThan(consentForm));
    expect(adsInitialization, greaterThan(attRequest));
    expect(
      service,
      contains('AppTrackingTransparency.requestTrackingAuthorization()'),
    );
  });

  test('App Store privacy mapping declares only Device ID as tracking', () {
    final privacy = jsonDecode(
      File('ios/fastlane/app_privacy.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    expect(privacy['tracking'], isTrue);
    expect(privacy['minimumBuild'], 35);

    final usages = (privacy['dataUsages'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final trackingUsages = usages.where((usage) {
      final protections = (usage['dataProtections'] as List<dynamic>)
          .cast<String>();
      return protections.contains('DATA_USED_TO_TRACK_YOU');
    }).toList();

    expect(trackingUsages, hasLength(1));
    expect(trackingUsages.single['category'], 'DEVICE_ID');
  });
}
