import 'package:abu_3meer/production/notification_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the Apple system banner for foreground notification payloads', () {
    expect(
      shouldPresentForegroundNotificationLocally(
        isApplePlatform: true,
        appleSystemPresentationEnabled: true,
        hasNotificationPayload: true,
      ),
      isFalse,
    );
  });

  test('uses a local banner for Apple data-only messages', () {
    expect(
      shouldPresentForegroundNotificationLocally(
        isApplePlatform: true,
        appleSystemPresentationEnabled: true,
        hasNotificationPayload: false,
      ),
      isTrue,
    );
  });

  test('uses a local banner on Android', () {
    expect(
      shouldPresentForegroundNotificationLocally(
        isApplePlatform: false,
        appleSystemPresentationEnabled: false,
        hasNotificationPayload: true,
      ),
      isTrue,
    );
  });

  test('falls back to a local banner if Apple presentation setup failed', () {
    expect(
      shouldPresentForegroundNotificationLocally(
        isApplePlatform: true,
        appleSystemPresentationEnabled: false,
        hasNotificationPayload: true,
      ),
      isTrue,
    );
  });
}
