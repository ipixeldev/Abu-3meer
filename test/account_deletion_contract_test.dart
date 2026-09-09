import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'account deletion uses the authenticated self-hosted API fail closed',
    () {
      final api = File('lib/production/api_production_repository.dart')
          .readAsStringSync();
      final repository = File('lib/production/production_repository.dart')
          .readAsStringSync();

      expect(api, contains('Future<void> deleteAccount()'));
      expect(api, contains("api.delete('/profile/me', requireAuth: true)"));

      final methodStart = repository.indexOf(
        'Future<void> deleteAccount({String? currentPassword})',
      );
      final methodEnd = repository.indexOf(
        '// ── Achievements & Levels & Rewards CRUD stubs',
        methodStart,
      );
      final method = repository.substring(methodStart, methodEnd);
      final appleRevoke = method.indexOf('revokeTokenWithAuthorizationCode');
      final serverDelete = method.indexOf('await apiRepo.deleteAccount();');
      final firebaseDelete = method.indexOf('await user.delete();');

      expect(methodStart, greaterThanOrEqualTo(0));
      expect(appleRevoke, greaterThanOrEqualTo(0));
      expect(serverDelete, greaterThan(appleRevoke));
      expect(firebaseDelete, greaterThan(serverDelete));
      expect(method, isNot(contains("_call('deleteAccountData'")));
      expect(method, isNot(contains('catch (_) {}')));
    },
  );

  test('settings exposes permanent deletion behind typed confirmation', () {
    final ui = File('lib/demo/production_ui.dart').readAsStringSync();

    expect(ui, contains("'Delete account'"));
    expect(ui, contains("'Delete account permanently?'"));
    expect(ui, contains("confirmation.text.trim().toUpperCase() == 'DELETE'"));
    expect(ui, contains('accountDeletionNeedsPassword'));
    expect(ui, contains('widget.repository.deleteAccount'));
    expect(ui, contains('profile, XP, predictions, challenge answers'));
    expect(ui, isNot(contains('challenge answers, rewards')));
    expect(ui, contains('barrierDismissible: false'));
  });
}
