import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('account credentials live in Settings, not the profile editor', () {
    final source = File('lib/demo/production_ui.dart').readAsStringSync();
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
  });
}
