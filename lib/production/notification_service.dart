import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import 'api_production_repository.dart';
import 'api_client.dart';
import 'app_preferences.dart';

@pragma('vm:entry-point')
Future<void> abuFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  debugPrint('[FCM Background] messageId=${message.messageId}');
}

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  static const String channelId = 'abu_3meer_high_importance';
  static const String _prefKeyNotificationsEnabled =
      'pref_notifications_enabled';
  static bool _backgroundHandlerRegistered = false;

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final StreamController<Map<String, dynamic>> _notificationTapController =
      StreamController<Map<String, dynamic>>.broadcast();

  ApiProductionRepository? _apiRepo;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<dynamic>? _authSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  String? _registeredToken;
  String? _registeredUserId;
  final Set<String> _registeringTokens = <String>{};
  bool _initialized = false;

  Stream<Map<String, dynamic>> get notificationTaps =>
      _notificationTapController.stream;

  static void registerBackgroundHandler() {
    if (_backgroundHandlerRegistered || kIsWeb) return;
    FirebaseMessaging.onBackgroundMessage(
      abuFirebaseMessagingBackgroundHandler,
    );
    _backgroundHandlerRegistered = true;
  }

  Future<void> initialize({ApiProductionRepository? apiRepo}) async {
    if (apiRepo != null) {
      await attachRepository(apiRepo);
    }
    if (_initialized) return;
    _initialized = true;
    registerBackgroundHandler();

    // Be explicit because users can restore an iOS backup containing an old
    // Firebase auto-init preference. Token creation and refresh must remain on
    // for server-delivered notifications.
    try {
      await _fcm.setAutoInitEnabled(true);
    } catch (error) {
      debugPrint('[FCM] Could not enable token auto-init yet: $error');
    }

    const initializationSettingsDarwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
      defaultPresentBanner: true,
      defaultPresentList: true,
    );
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: initializationSettingsDarwin,
      macOS: initializationSettingsDarwin,
    );

    await _localNotifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        _emitTap(_decodePayload(details.payload));
      },
    );

    if (!kIsWeb && Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        channelId,
        'Abu 3meer Match & Challenge Alerts',
        description: 'Notifications for match kickoffs, challenge releases, and points won.',
        importance: Importance.max,
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }

    // Foreground messages are converted into real OS notification banners.
    // Background notification payloads are displayed by FCM/APNs itself.
    _foregroundSubscription ??= FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      unawaited(
        _showLocalNotification(
          id: message.messageId?.hashCode ?? message.hashCode,
          title: notification?.title ?? 'Abu 3meer ⚽',
          body: notification?.body ?? '',
          payload: _encodePayload(message.data),
        ),
      );
    });
    _openedSubscription ??= FirebaseMessaging.onMessageOpenedApp.listen((
      message,
    ) {
      _emitTap(message.data);
    });
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      _emitTap(initialMessage.data);
    }

    _tokenRefreshSubscription ??= _fcm.onTokenRefresh.listen((token) {
      unawaited(_registerTokenSafely(token));
    });

    final preferences = await SharedPreferences.getInstance();
    final enabled = preferences.getBool(_prefKeyNotificationsEnabled) ?? true;
    if (enabled && _apiRepo != null) {
      unawaited(_syncTokenSafely(_apiRepo!));
    }
  }

  /// Attaches the authenticated self-hosted API even when notification plugin
  /// initialization already happened during the splash screen.
  Future<void> attachRepository(ApiProductionRepository apiRepo) async {
    if (identical(_apiRepo, apiRepo) && _authSubscription != null) return;
    _apiRepo = apiRepo;
    await _authSubscription?.cancel();
    _authSubscription = apiRepo.authChanges.listen((user) {
      if (user != null) {
        if (_registeredUserId != user.uid) {
          _registeredToken = null;
          _registeredUserId = null;
        }
        unawaited(_syncTokenSafely(apiRepo));
      } else {
        _registeredToken = null;
        _registeredUserId = null;
      }
    });
    if (apiRepo.auth.currentUser != null) {
      unawaited(_syncTokenSafely(apiRepo));
    }
  }

  Future<bool> requestPermission({ApiProductionRepository? apiRepo}) async {
    if (apiRepo != null) await attachRepository(apiRepo);
    late NotificationSettings settings;
    try {
      settings = await _fcm.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        settings = await _fcm.requestPermission(
          alert: true,
          announcement: false,
          badge: true,
          carPlay: false,
          criticalAlert: false,
          provisional: false,
          sound: true,
        );
      }
    } catch (error) {
      debugPrint('[Notifications] Permission check failed: $error');
      return false;
    }

    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_prefKeyNotificationsEnabled, granted);
    } catch (error) {
      // Local preference storage is independent of the OS authorization
      // result and must never turn an authorized iPhone into a false denial.
      debugPrint('[Notifications] Could not cache permission state: $error');
    }
    if (granted && _apiRepo != null) {
      try {
        await syncTokenWithBackend(_apiRepo!);
        await syncPreferencesFromLocal();
      } catch (error) {
        // A backend/tunnel outage is not an operating-system permission
        // denial. Registration will retry on auth/token refresh.
        debugPrint('[Notifications] Server sync deferred: $error');
      }
    }
    return granted;
  }

  Future<void> syncTokenWithBackend(
    ApiProductionRepository apiRepo, {
    bool forceRegistration = false,
  }) async {
    _apiRepo = apiRepo;
    if (apiRepo.auth.currentUser == null) return;
    try {
      final settings = await _fcm.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return;
      }

      // APNs must issue its native token before Firebase can mint an iOS FCM
      // token. The short retry avoids the common first-launch race.
      if (!kIsWeb && Platform.isIOS) {
        String? apnsToken;
        for (var attempt = 0; attempt < 20 && apnsToken == null; attempt++) {
          apnsToken = await _fcm.getAPNSToken();
          if (apnsToken == null) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        }
        if (apnsToken == null) {
          debugPrint(
            '[FCM] APNs token is not available yet; registration deferred.',
          );
          return;
        }
      }

      final token = await _fcm.getToken();
      if (token != null && token.isNotEmpty) {
        await _registerToken(token, force: forceRegistration);
      }
    } catch (error) {
      debugPrint('[FCM] Token registration failed: $error');
      rethrow;
    }
  }

  Future<void> _registerToken(String token, {bool force = false}) async {
    final repository = _apiRepo;
    final currentUser = repository?.auth.currentUser;
    if (repository == null || currentUser == null) return;
    if ((!force &&
            _registeredToken == token &&
            _registeredUserId == currentUser.uid) ||
        !_registeringTokens.add(token)) {
      return;
    }
    final platform = kIsWeb
        ? 'web'
        : Platform.isIOS
        ? 'ios'
        : 'android';
    try {
      await repository.registerFcmToken(
        token,
        platform,
        locale: AbuAppPreferences.instance.locale.toLanguageTag(),
      );
      _registeredToken = token;
      _registeredUserId = currentUser.uid;
      debugPrint('[FCM] Device token registered with the self-hosted API.');
    } finally {
      _registeringTokens.remove(token);
    }
  }

  Future<void> _syncTokenSafely(ApiProductionRepository repository) async {
    try {
      await syncTokenWithBackend(repository);
    } catch (error) {
      debugPrint('[FCM] Deferred token sync: $error');
    }
  }

  Future<void> _registerTokenSafely(String token) async {
    try {
      await _registerToken(token);
    } catch (error) {
      debugPrint('[FCM] Deferred refreshed-token sync: $error');
    }
  }

  Future<void> syncPreferencesFromLocal() async {
    final repository = _apiRepo;
    if (repository == null || repository.auth.currentUser == null) return;
    try {
      final local = AbuAppPreferences.instance;
      final permission = await _fcm.getNotificationSettings();
      final enabled =
          permission.authorizationStatus == AuthorizationStatus.authorized ||
          permission.authorizationStatus == AuthorizationStatus.provisional;
      await repository.updateNotificationPreferences(
        enabled: enabled,
        matchEnabled: local.matchNotifications,
        challengeEnabled: local.challengeNotifications,
        rewardEnabled: local.rewardNotifications,
        newsEnabled: local.newsNotifications,
      );
    } catch (error) {
      // Preferences are already persisted on-device. The server copy is
      // retried later when the tunnel/backend is reachable.
      debugPrint('[Notifications] Preference sync deferred: $error');
    }
  }

  Future<Map<String, dynamic>> sendRemoteTest() async {
    final repository = _apiRepo;
    if (repository == null || repository.auth.currentUser == null) {
      throw StateError('Sign in before testing push notifications.');
    }
    // Always upsert before a test. This repairs an inactive migrated row and
    // re-associates the token if the person changed Firebase accounts.
    await syncTokenWithBackend(repository, forceRegistration: true);
    var result = await repository.sendPushNotificationTest();

    // FCM explicitly told us the token is permanently unusable (stale,
    // unregistered, or minted by another Firebase sender). Rotate it once,
    // register the replacement, and retry without requiring a reinstall.
    if (result['requiresTokenRefresh'] == true) {
      await _replaceMessagingToken(repository);
      result = await repository.sendPushNotificationTest();
    }

    if (result['providerConfigurationError'] == true) {
      throw AbuApiException(
        statusCode: 502,
        message: 'Firebase could not authenticate with Apple Push Notification service. Verify the APNs authentication key for com.abu3meer.app in the abu-3meer-9fd70 Firebase project.',
        details: result['failureCodes'],
      );
    }
    if ((result['failedCount'] as num? ?? 0) > 0) {
      final codes =
          (result['failureCodes'] as List?)?.whereType<String>().join(', ') ??
          'unknown';
      throw AbuApiException(
        statusCode: 502,
        message: 'Firebase rejected the push notification ($codes).',
        details: result['failureCodes'],
      );
    }
    return result;
  }

  Future<void> _replaceMessagingToken(
    ApiProductionRepository repository,
  ) async {
    _registeredToken = null;
    _registeredUserId = null;
    await _fcm.deleteToken();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await syncTokenWithBackend(repository, forceRegistration: true);
  }

  Future<void> unregisterCurrentDevice() async {
    final repository = _apiRepo;
    if (repository == null || repository.auth.currentUser == null) return;
    final token = _registeredToken ?? await _fcm.getToken();
    if (token == null || token.isEmpty) return;
    await repository.unregisterFcmToken(token);
    _registeredToken = null;
    _registeredUserId = null;
  }

  Future<void> _showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        'Abu 3meer Match & Challenge Alerts',
        channelDescription: 'Notifications for match kickoffs, challenge releases, and points won.',
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        presentBanner: true,
        presentList: true,
        interruptionLevel: InterruptionLevel.active,
      ),
    );
    await _localNotifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  Future<void> showInAppNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    await _showLocalNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      payload: payload,
    );
  }

  void _emitTap(Map<String, dynamic> data) {
    if (!_notificationTapController.isClosed) {
      _notificationTapController.add(data);
    }
  }

  String _encodePayload(Map<String, dynamic> data) => data.entries
      .map(
        (entry) =>
            '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent('${entry.value}')}',
      )
      .join('&');

  Map<String, dynamic> _decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) return const {};
    return Uri.splitQueryString(payload);
  }
}
