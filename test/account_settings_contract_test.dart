import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('account credentials live in Settings, not the profile editor', () {
    final source = File('lib/demo/production_ui.dart').readAsStringSync();
    final repository = File('lib/production/production_repository.dart')
        .readAsStringSync();
    final editorStart = source.indexOf('Future<void> editProfile()');
    final editorEnd = source.indexOf(
      '\n  @override\n  void initState()',
      editorStart,
    );
    expect(editorStart, greaterThanOrEqualTo(0));
    expect(editorEnd, greaterThan(editorStart));

    final profileEditor = source.substring(editorStart, editorEnd);
    expect(profileEditor, isNot(contains('verifyBeforeUpdateEmail')));
    expect(profileEditor, isNot(contains('updatePassword')));
    expect(profileEditor, isNot(contains('ACCOUNT CREDENTIALS')));
    expect(profileEditor, contains("'Edit Profile'"));

    final settingsStart = source.indexOf('class _ProductionSettings');
    expect(settingsStart, greaterThanOrEqualTo(0));
    final settings = source.substring(settingsStart);
    expect(settings, contains("'Account email'"));
    expect(settings, contains("'Change password'"));
    expect(source, contains('verifyBeforeUpdateEmail(nextEmail)'));
    expect(source, contains('updatePassword(nextPassword)'));
    expect(source, contains('refreshAuthenticatedIdentity()'));
    expect(repository, contains("await auth.currentUser!.reload()"));
    expect(repository, contains('await refreshedUser.getIdToken(true)'));
    expect(
      source,
      contains('your signed-in account will update automatically.'),
    );
  });

  test(
    'public profile edits do not mutate the Firebase authentication session',
    () {
      final repository = File('lib/production/production_repository.dart')
          .readAsStringSync();
      final methodStart = repository.indexOf('Future<void> updateProfile({');
      final methodEnd = repository.indexOf(
        '\n  Future<int> checkInDailyStreak',
        methodStart,
      );
      final method = repository.substring(methodStart, methodEnd);

      expect(method, contains('apiRepo.updateProfile'));
      expect(method, contains('_profileResources[user.uid]?.emit(updated)'));
      expect(method, isNot(contains('user.updateDisplayName')));
      expect(method, isNot(contains('user.updatePhotoURL')));
      expect(method, isNot(contains('auth.signOut')));
    },
  );
}
