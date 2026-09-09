import 'dart:convert';
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
      final forcedTokenRefresh = method.indexOf('await user.getIdToken(true);');

      expect(methodStart, greaterThanOrEqualTo(0));
      expect(appleRevoke, greaterThanOrEqualTo(0));
      expect(forcedTokenRefresh, greaterThan(appleRevoke));
      expect(serverDelete, greaterThan(forcedTokenRefresh));
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
    expect(
      ui.indexOf(
        'Deleting this account does not cancel an Apple App Store subscription.',
      ),
      lessThan(ui.indexOf('This cannot be undone. Your profile, XP')),
    );
    expect(ui, contains("'MANAGE APPLE SUBSCRIPTION'"));
    expect(ui, contains("'MANAGE GOOGLE PLAY SUBSCRIPTION'"));
  });

  test('legacy nested account data has collection-group deletion indexes', () {
    final decoded = jsonDecode(
      File('firestore.indexes.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final overrides = (decoded['fieldOverrides'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    for (final collection in const <String>[
      'attempts',
      'reactions',
      'comments',
      'taps',
    ]) {
      final override = overrides.singleWhere(
        (entry) =>
            entry['collectionGroup'] == collection &&
            entry['fieldPath'] == 'userId',
      );
      final indexes = (override['indexes'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(
        indexes.any(
          (index) =>
              index['queryScope'] == 'COLLECTION_GROUP' &&
              index['order'] == 'ASCENDING',
        ),
        isTrue,
        reason: '$collection.userId must support collection-group deletion',
      );
    }
  });
}
