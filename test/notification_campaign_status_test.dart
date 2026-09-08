import 'package:flutter_test/flutter_test.dart';

import 'package:abu_3meer/production/api_production_repository.dart';

void main() {
  test('notification campaign polling stops on completed delivery', () async {
    var calls = 0;
    final waits = <Duration>[];

    final result = await pollNotificationCampaignDelivery(
      maxPolls: 5,
      interval: const Duration(milliseconds: 10),
      wait: (duration) async => waits.add(duration),
      fetch: () async {
        calls += 1;
        if (calls < 3) {
          return <String, dynamic>{'status': 'processing', 'terminal': false};
        }
        return <String, dynamic>{
          'status': 'completed',
          'terminal': true,
          'sentCount': 2,
        };
      },
    );

    expect(calls, 3);
    expect(waits, const <Duration>[
      Duration(milliseconds: 10),
      Duration(milliseconds: 10),
    ]);
    expect(result['sentCount'], 2);
  });

  test(
    'notification campaign polling stops on APNs configuration error',
    () async {
      var calls = 0;
      final result = await pollNotificationCampaignDelivery(
        maxPolls: 5,
        wait: (_) async {},
        fetch: () async {
          calls += 1;
          return <String, dynamic>{
            'status': 'failed',
            'terminal': false,
            'providerConfigurationError': true,
            'failureCodes': <String>['messaging/third-party-auth-error'],
          };
        },
      );

      expect(calls, 1);
      expect(result['providerConfigurationError'], isTrue);
    },
  );

  test(
    'notification campaign polling returns latest pending status at limit',
    () async {
      var calls = 0;
      final result = await pollNotificationCampaignDelivery(
        maxPolls: 2,
        wait: (_) async {},
        fetch: () async => <String, dynamic>{
          'status': 'processing',
          'terminal': false,
          'sequence': ++calls,
        },
      );

      expect(calls, 2);
      expect(result['sequence'], 2);
    },
  );
}
