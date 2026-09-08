import 'dart:math';

import 'package:abu_3meer/production/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'notification installation IDs are stable-schema opaque identifiers',
    () {
      final first = newNotificationInstallationId(Random(42));
      final replay = newNotificationInstallationId(Random(42));
      final another = newNotificationInstallationId(Random(43));

      expect(first, hasLength(32));
      expect(first, matches(RegExp(r'^[a-f0-9]{32}$')));
      expect(replay, first);
      expect(another, isNot(first));
    },
  );

  test('iOS token registration retries quickly, then caps its backoff', () {
    expect(notificationTokenRetryDelay(-1), const Duration(seconds: 2));
    expect(notificationTokenRetryDelay(0), const Duration(seconds: 2));
    expect(notificationTokenRetryDelay(1), const Duration(seconds: 5));
    expect(notificationTokenRetryDelay(2), const Duration(seconds: 15));
    expect(notificationTokenRetryDelay(3), const Duration(seconds: 30));
    expect(notificationTokenRetryDelay(4), const Duration(minutes: 1));
    expect(notificationTokenRetryDelay(100), const Duration(minutes: 1));
  });
}
