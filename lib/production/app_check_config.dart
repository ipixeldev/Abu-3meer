/// Firebase App Check client configuration.
///
/// App Check is intentionally unavailable until all provider registrations
/// and the Firebase App Check API are configured in Firebase Console.
///
/// Keep this facade in the bootstrap so App Check can be restored without
/// changing application startup. Re-add `firebase_app_check`, configure the
/// providers, and restore provider activation here before setting
/// `--dart-define=ABU_APP_CHECK_ENABLED=true`.
abstract final class AbuAppCheckConfig {
  static const bool enabled = bool.fromEnvironment(
    'ABU_APP_CHECK_ENABLED',
    defaultValue: false,
  );

  static Future<void> activate() async {
    if (!enabled) return;
    throw StateError(
      'ABU_APP_CHECK_ENABLED=true requires the Firebase App Check SDK and '
      'provider registration to be restored first.',
    );
  }
}
