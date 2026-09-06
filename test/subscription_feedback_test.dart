import 'package:abu_3meer/features/subscriptions/subscription_feedback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production-only rejection does not ask user to buy a test again', () {
    final result = SubscriptionFeedback.checked(
      serverActive: false,
      storeActive: true,
      isSandbox: true,
      accessReason: 'sandbox_not_allowed',
    );
    expect(result.english, contains('production purchases only'));
    expect(result.english, contains('Do not purchase again'));
    expect(result.english, isNot(contains('Membership confirmed')));
    expect(result.arabic, contains('مشتريات الإنتاج فقط'));
  });

  test('missing entitlement does not falsely diagnose a sandbox denial', () {
    final result = SubscriptionFeedback.checked(
      serverActive: false,
      storeActive: true,
      isSandbox: true,
      accessReason: 'no_entitlement',
    );
    expect(result.english, contains('did not find the membership entitlement'));
    expect(result.english, isNot(contains('production purchases only')));
  });

  test(
    'expired and stale verification have different recovery instructions',
    () {
      for (final entry in {
        'expired': 'expired subscription',
        'verification_required': 'verification is out of date',
      }.entries) {
        final result = SubscriptionFeedback.checked(
          serverActive: false,
          storeActive: true,
          isSandbox: false,
          accessReason: entry.key,
        );
        expect(result.english, contains(entry.value));
        expect(result.english, contains('Do not purchase again'));
        expect(result.arabic, isNotEmpty);
      }
    },
  );

  test(
    'confirmed server result takes precedence over stale diagnostic fields',
    () {
      final result = SubscriptionFeedback.checked(
        serverActive: true,
        storeActive: false,
        isSandbox: false,
        accessReason: 'unknown',
      );
      expect(result.english, startsWith('Membership confirmed'));
    },
  );
}
