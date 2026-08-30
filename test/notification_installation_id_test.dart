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
}
