import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production auth exposes Apple only on iOS', () {
    final ui = File('lib/demo/production_ui.dart').readAsStringSync();
    final repository = File('lib/production/production_repository.dart')
        .readAsStringSync();

    expect(
      ui,
      contains('!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS'),
    );
    expect(ui, contains('SignInWithAppleButton('));
    expect(ui, contains("'Continue with Apple'"));
    expect(ui, contains('SignInWithAppleButtonStyle.white'));
    expect(ui, isNot(contains('Icons.apple')));
    expect(ui, contains('repository.signInWithApple'));
    expect(repository, contains('Future<void> signInWithApple()'));
    expect(repository, contains('AppleAuthProvider()'));
    expect(repository, contains('auth.signInWithProvider(provider)'));
  });

  test('iOS entitlement and Apple account revocation are configured', () {
    final entitlements = File('ios/Runner/Runner.entitlements')
        .readAsStringSync();
    final repository = File('lib/production/production_repository.dart')
        .readAsStringSync();
    final project = File('ios/Runner.xcodeproj/project.pbxproj')
        .readAsStringSync();

    expect(entitlements, contains('com.apple.developer.applesignin'));
    expect(entitlements, contains('<string>Default</string>'));
    expect(project, contains('com.apple.SignInWithApple'));
    expect(repository, contains('reauthenticateWithProvider(provider)'));
    expect(repository, contains('revokeTokenWithAuthorizationCode'));
  });
}
