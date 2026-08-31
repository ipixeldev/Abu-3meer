import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import 'api_production_repository.dart';
import 'app_preferences.dart';
import 'notification_presentation.dart';

@visibleForTesting
String newNotificationInstallationId([Random? source]) {
  final random = source ?? Random.secure();
  return List<int>.generate(
    16,
    (_) => random.nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}

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
  static const String _prefKeyInstallationId =
      'notification_installation_id_v1';
  static const String _prefKeyPendingRevocationToken =
      'notification_pending_revocation_token_v1';
  static const String _prefKeyPendingRevocationInstallation =
      'notification_pending_revocation_installation_v1';
  static bool _backgroundHandlerRegistered = false;

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final StreamController<Map<String, dynamic>> _notificationTapController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>>
  _foregroundNotificationController =
      StreamController<Map<String, dynamic>>.broadcast();
  Map<String, dynamic>? _pendingNotificationTap;

  ApiProductionRepository? _apiRepo;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<dynamic>? _authSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  String? _registeredToken;
  String? _registeredUserId;
  final Set<String> _registeringTokens = <String>{};
  Future<void> _tokenMutationTail = Future<void>.value();
  Future<void>? _initializationFuture;
  bool _initialized = false;
  bool _appleSystemForegroundPresentationEnabled = false;
  Future<String>? _installationIdFuture;
  Timer? _revocationRetryTimer;

  Stream<Map<String, dynamic>> get notificationTaps =>
      _notificationTapController.stream;
  Stream<Map<String, dynamic>> get foregroundNotifications =>
      _foregroundNotificationController.stream;

  /// Cold-start messages can arrive before the authenticated shell subscribes.
  /// Keep the latest tap once so its destination can still be opened.
  Map<String, dynamic>? takePendingNotificationTap() {
    final pending = _pendingNotificationTap;
    _pendingNotificationTap = null;
    return pending;
  }

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
    final pending = _initializationFuture;
    if (pending != null) return await pending;

    final operation = _initializeMessaging();
    _initializationFuture = operation;
    try {
      await operation;
      _initialized = true;
    } finally {
      if (identical(_initializationFuture, operation)) {
        _initializationFuture = null;
      }
    }
  }

  Future<void> _initializeMessaging() async {
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

    final isApplePlatform = !kIsWeb && (Platform.isIOS || Platform.isMacOS);
    if (isApplePlatform) {
      try {
        await _fcm.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
        _appleSystemForegroundPresentationEnabled = true;
        debugPrint('[FCM] Apple foreground system banners enabled.');
      } catch (error) {
        _appleSystemForegroundPresentationEnabled = false;
        debugPrint(
          '[FCM] Apple foreground presentation setup failed; using local fallback: $error',
        );
      }
    }

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

    // Apple displays notification payloads through the system foreground
    // presentation options above. Android and data-only Apple messages use a
    // local notification. Background payloads are displayed by FCM/APNs.
    _foregroundSubscription ??= FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (!_foregroundNotificationController.isClosed) {
        _foregroundNotificationController.add(
          Map<String, dynamic>.from(message.data),
        );
      }
      final useLocalPresentation = shouldPresentForegroundNotificationLocally(
        isApplePlatform: isApplePlatform,
        appleSystemPresentationEnabled:
            _appleSystemForegroundPresentationEnabled,
        hasNotificationPayload: notification != null,
      );
      debugPrint(
        '[FCM Foreground] messageId=${message.messageId} notificationPayload=${notification != null} presentation=${useLocalPresentation ? 'local' : 'apple-system'}',
      );
      if (!useLocalPresentation) return;
      unawaited(
        _showLocalNotification(
          id: message.messageId?.hashCode ?? message.hashCode,
          title: notification?.title ?? 'Abu 3meer ⚽',
          body: notification?.body ?? '',
          payload: _encodePayload(message.data),
        ).catchError((Object error) {
          debugPrint('[FCM Foreground] Local banner failed: $error');
        }),
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
    unawaited(_retryPendingDeviceRevocation());
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
    unawaited(_retryPendingDeviceRevocation());
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

    final authorized =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    final isApplePlatform = !kIsWeb && (Platform.isIOS || Platform.isMacOS);
    final alertsEnabled =
        !isApplePlatform || settings.alert == AppleNotificationSetting.enabled;
    final granted = authorized && alertsEnabled;
    if (isApplePlatform) {
      debugPrint(
        '[FCM Permission] authorization=${settings.authorizationStatus.name} alerts=${settings.alert.name} notificationCenter=${settings.notificationCenter.name} sound=${settings.sound.name}',
      );
    }
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

  Future<T> _serializeTokenMutation<T>(Future<T> Function() operation) {
    final previous = _tokenMutationTail;
    final completer = Completer<T>();
    _tokenMutationTail = () async {
      try {
        await previous;
      } catch (_) {
        // Each caller receives its own error; a failed operation must not
        // poison the queue for logout or a later token refresh.
      }
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }();
    return completer.future;
  }

  Future<void> _registerToken(String token, {bool force = false}) =>
      _serializeTokenMutation(
        () => _registerTokenUnlocked(token, force: force),
      );

  Future<void> _registerTokenUnlocked(
    String token, {
    bool force = false,
  }) async {
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
      final installationId = await _installationId();
      await repository.registerFcmToken(
        token,
        platform,
        installationId: installationId,
        locale: AbuAppPreferences.instance.locale.toLanguageTag(),
      );
      _registeredToken = token;
      _registeredUserId = currentUser.uid;
      await _clearPendingRevocationForInstallation(installationId);
      debugPrint('[FCM] Device token registered with the self-hosted API.');
    } finally {
      _registeringTokens.remove(token);
    }
  }

  Future<String> _installationId() {
    final pending = _installationIdFuture;
    if (pending != null) return pending;
    final operation = _loadOrCreateInstallationId();
    _installationIdFuture = operation;
    return operation;
  }

  Future<String> _loadOrCreateInstallationId() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(_prefKeyInstallationId)?.trim();
    if (existing != null &&
        RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(existing)) {
      return existing;
    }
    final created = newNotificationInstallationId();
    await preferences.setString(_prefKeyInstallationId, created);
    return created;
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
        // Kept in the wire shape for backward-compatible servers only. Reward
        // notifications are retired with the XP-only recognition model.
        rewardEnabled: false,
        newsEnabled: local.newsNotifications,
      );
    } catch (error) {
      // Preferences are already persisted on-device. The server copy is
      // retried later when the tunnel/backend is reachable.
      debugPrint('[Notifications] Preference sync deferred: $error');
    }
  }

  Future<void> unregisterCurrentDevice() =>
      _serializeTokenMutation(_unregisterCurrentDeviceUnlocked);

  Future<void> _unregisterCurrentDeviceUnlocked() async {
    final repository = _apiRepo;
    if (repository == null || repository.auth.currentUser == null) return;
    final token = _registeredToken ?? await _fcm.getToken();
    if (token == null || token.isEmpty) return;
    final installationId = await _installationId();
    await _persistPendingRevocation(token, installationId);
    try {
      await repository.unregisterFcmToken(token);
      await _clearPendingRevocationForInstallation(installationId);
    } catch (_) {
      // If the API is unreachable, invalidate the Firebase registration as a
      // second line of defense so this signed-out installation cannot keep
      // receiving user-targeted notifications under the old token.
      try {
        await _fcm.deleteToken();
      } catch (error) {
        debugPrint('[FCM] Local token revocation also failed: $error');
      }
      _schedulePendingRevocationRetry();
      rethrow;
    } finally {
      _registeredToken = null;
      _registeredUserId = null;
    }
  }

  Future<void> _persistPendingRevocation(
    String token,
    String installationId,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_prefKeyPendingRevocationToken, token);
    await preferences.setString(
      _prefKeyPendingRevocationInstallation,
      installationId,
    );
  }

  Future<void> _clearPendingRevocationForInstallation(
    String installationId,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getString(_prefKeyPendingRevocationInstallation) !=
        installationId) {
      return;
    }
    await preferences.remove(_prefKeyPendingRevocationToken);
    await preferences.remove(_prefKeyPendingRevocationInstallation);
    _revocationRetryTimer?.cancel();
    _revocationRetryTimer = null;
  }

  Future<void> _retryPendingDeviceRevocation() =>
      _serializeTokenMutation(_retryPendingDeviceRevocationUnlocked);

  Future<void> _retryPendingDeviceRevocationUnlocked() async {
    final repository = _apiRepo;
    if (repository == null) return;
    final preferences = await SharedPreferences.getInstance();
    final token = preferences.getString(_prefKeyPendingRevocationToken)?.trim();
    final installationId = preferences
        .getString(_prefKeyPendingRevocationInstallation)
        ?.trim();
    if (token == null ||
        token.isEmpty ||
        installationId == null ||
        installationId.isEmpty) {
      _revocationRetryTimer?.cancel();
      _revocationRetryTimer = null;
      return;
    }
    try {
      await repository.revokeFcmInstallation(
        fcmToken: token,
        installationId: installationId,
      );
      await _clearPendingRevocationForInstallation(installationId);
    } catch (error) {
      debugPrint('[FCM] Pending device revocation deferred: $error');
      _schedulePendingRevocationRetry();
    }
  }

  void _schedulePendingRevocationRetry() {
    _revocationRetryTimer ??= Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(_retryPendingDeviceRevocation());
    });
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
      if (_notificationTapController.hasListener) {
        _notificationTapController.add(data);
      } else {
        _pendingNotificationTap = Map<String, dynamic>.from(data);
      }
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
