import 'package:abu_3meer/production/api_production_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Point adjustment subscriber identity', () {
    test('preserves independently verified admin and target subscriptions', () {
      final adjustment = parseAdminPointAdjustment(<String, dynamic>{
        'id': 'adjustment-1',
        'adminIsProSubscriber': true,
        'targetIsProSubscriber': false,
      });

      expect(adjustment.adminIsProSubscriber, isTrue);
      expect(adjustment.targetIsProSubscriber, isFalse);

      final targetSubscribed = parseAdminPointAdjustment(<String, dynamic>{
        'adminIsProSubscriber': false,
        'targetIsProSubscriber': true,
      });
      expect(targetSubscribed.adminIsProSubscriber, isFalse);
      expect(targetSubscribed.targetIsProSubscriber, isTrue);
    });

    test('legacy responses and non-boolean flags cannot grant badges', () {
      for (final value in <Object?>[null, 'true', 1]) {
        final adjustment = parseAdminPointAdjustment(<String, dynamic>{
          'adminIsProSubscriber': value,
          'targetIsProSubscriber': value,
          'role': 'member',
          'isYouTubeMember': true,
        });

        expect(adjustment.adminIsProSubscriber, isFalse);
        expect(adjustment.targetIsProSubscriber, isFalse);
      }
      final legacyAdjustment = parseAdminPointAdjustment(<String, dynamic>{});
      expect(legacyAdjustment.adminIsProSubscriber, isFalse);
      expect(legacyAdjustment.targetIsProSubscriber, isFalse);
    });

    test(
      'YouTube membership grants audit-row badges without a store subscription',
      () {
        final adjustment = parseAdminPointAdjustment(<String, dynamic>{
          'adminIsProSubscriber': false,
          'adminIsYouTubeMember': true,
          'targetIsProSubscriber': false,
          'targetHasMemberAccess': true,
        });

        expect(adjustment.adminHasMemberAccess, isTrue);
        expect(adjustment.targetHasMemberAccess, isTrue);
        expect(adjustment.adminIsProSubscriber, isFalse);
        expect(adjustment.targetIsProSubscriber, isFalse);
      },
    );

    test(
      'explicit effective-access denial overrides legacy membership flags',
      () {
        final adjustment = parseAdminPointAdjustment(<String, dynamic>{
          'adminHasMemberAccess': false,
          'adminIsYouTubeMember': true,
          'adminIsProSubscriber': true,
          'targetHasMemberAccess': false,
          'targetIsYouTubeMember': true,
          'targetIsProSubscriber': true,
        });

        expect(adjustment.adminHasMemberAccess, isFalse);
        expect(adjustment.targetHasMemberAccess, isFalse);
      },
    );
  });
}
