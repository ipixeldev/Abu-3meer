import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

class SubscriptionException implements Exception {
  const SubscriptionException(this.message, {this.code = 'subscription'});
  final String message;
  final String code;
  @override
  String toString() => message;
}

/// Parsed only from our authenticated server's subscription response. A store
/// receipt and permission to use production features are separate decisions.
class SubscriptionAccessResult {
  const SubscriptionAccessResult({
    required this.isActive,
    this.reason = 'unknown',
    this.environment = 'unknown',
    this.source = 'none',
    this.overrideMode = 'store',
    this.overrideExpiresAt,
    bool? hasMemberAccess,
    this.memberAccessSource = 'none',
    this.memberAccessReason = 'unknown',
    this.memberAccessExpiresAt,
    this.youtubeMembershipActive = false,
    this.youtubeMembershipVerifiedAt,
    this.youtubeMembershipExpiresAt,
    this.youtubeMembershipRecheckRequired = false,
  }) : hasMemberAccess =
           hasMemberAccess ?? (isActive || youtubeMembershipActive);

  final bool isActive;
  final String reason;
  final String environment;
  final String source;
  final String overrideMode;
  final DateTime? overrideExpiresAt;
  final bool hasMemberAccess;
  final String memberAccessSource;
  final String memberAccessReason;
  final DateTime? memberAccessExpiresAt;
  final bool youtubeMembershipActive;
  final DateTime? youtubeMembershipVerifiedAt;
  final DateTime? youtubeMembershipExpiresAt;
  final bool youtubeMembershipRecheckRequired;

  factory SubscriptionAccessResult.fromEnvelope(Object? envelope) {
    final data = envelope is Map ? envelope['data'] : null;
    if (data is! Map ||
        data['entitlementId'] != SubscriptionService.entitlementId) {
      return const SubscriptionAccessResult(isActive: false);
    }
    const reasons = {
      'active',
      'sandbox_not_allowed',
      'no_entitlement',
      'expired',
      'verification_required',
      'inactive',
      'admin_granted',
      'admin_revoked',
    };
    const environments = {'production', 'sandbox'};
    final isActive =
        data['isActive'] == true &&
        (!reasons.contains(data['accessReason']) ||
            data['accessReason'] == 'active' ||
            data['accessReason'] == 'admin_granted');
    final youtubeMembershipActive =
        data['youtubeMembershipActive'] == true ||
        data['isYouTubeMember'] == true;
    return SubscriptionAccessResult(
      isActive: isActive,
      reason: reasons.contains(data['accessReason'])
          ? data['accessReason'] as String
          : 'unknown',
      environment: environments.contains(data['environment'])
          ? data['environment'] as String
          : 'unknown',
      source: const {'admin', 'store', 'none'}.contains(data['accessSource'])
          ? data['accessSource'] as String
          : 'none',
      overrideMode:
          const {
            'active',
            'inactive',
            'store',
          }.contains(data['subscriptionAccessMode'])
          ? data['subscriptionAccessMode'] as String
          : 'store',
      overrideExpiresAt: DateTime.tryParse(
        (data['subscriptionAccessExpiresAt'] ?? '').toString(),
      ),
      hasMemberAccess: data['hasMemberAccess'] is bool
          ? data['hasMemberAccess'] as bool
          : isActive || youtubeMembershipActive,
      memberAccessSource:
          const {
            'youtube',
            'store',
            'admin',
            'none',
          }.contains(data['memberAccessSource'])
          ? data['memberAccessSource'] as String
          : youtubeMembershipActive
          ? 'youtube'
          : isActive
          ? (data['accessReason'] == 'admin_granted' ? 'admin' : 'store')
          : 'none',
      memberAccessReason:
          (data['memberAccessReason'] ?? data['accessReason'] ?? 'unknown')
              .toString(),
      memberAccessExpiresAt: DateTime.tryParse(
        (data['memberAccessExpiresAt'] ?? '').toString(),
      ),
      youtubeMembershipActive: youtubeMembershipActive,
      youtubeMembershipVerifiedAt: DateTime.tryParse(
        (data['youtubeMembershipVerifiedAt'] ?? '').toString(),
      ),
      youtubeMembershipExpiresAt: DateTime.tryParse(
        (data['youtubeMembershipExpiresAt'] ?? '').toString(),
      ),
      youtubeMembershipRecheckRequired:
          data['youtubeMembershipRecheckRequired'] == true,
    );
  }
}

/// Store state is for display only. Protected API access is independently
/// verified by the backend. No secret RevenueCat key belongs in this class.
class SubscriptionService extends ChangeNotifier {
  SubscriptionService._();
  @visibleForTesting
  SubscriptionService.forTesting();
  static final instance = SubscriptionService._();
  static const entitlementId = 'abu_3meer_pro';
  // RevenueCat public SDK keys are store-specific; iOS uses appl_, Android uses goog_.
  // This is a client identifier, not a secret REST API credential.
  static const _iosKey = String.fromEnvironment(
    'REVENUECAT_IOS_API_KEY',
    defaultValue: 'appl_iCzDOpoHTcRJOVHgbimJTxihuOS',
  );
  static const _androidKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_API_KEY',
    defaultValue: 'goog_GzZFSUOUejSWXQoegvVhVIDZIhu',
  );

  Future<void> _tail = Future<void>.value();
  bool _configured = false;
  bool _switching = false;
  int _generation = 0;
  int _logoutRevision = 0;
  int _pending = 0;
  String? _userId;
  CustomerInfo? _customerInfo;
  SubscriptionAccessResult? _serverAccess;

  CustomerInfo? get customerInfo => _customerInfo;
  SubscriptionAccessResult? get serverAccess => _serverAccess;

  /// Display diagnostics only; protected access and badges still use the
  /// independently refreshed server profile, never this cached verdict.
  void recordServerAccess(String userId, SubscriptionAccessResult access) {
    if (_userId != userId || _switching) return;
    _serverAccess = access;
    notifyListeners();
  }

  bool get busy => _pending > 0;
  bool get hasStoreEntitlement =>
      _customerInfo?.entitlements.active[entitlementId] != null;
  String? get userId => _userId;

  String get apiKey {
    if (kIsWeb) return '';
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android) {
      return '';
    }
    return defaultTargetPlatform == TargetPlatform.iOS ? _iosKey : _androidKey;
  }

  bool get available => validPublicKey(
    apiKey,
    isIOS: defaultTargetPlatform == TargetPlatform.iOS,
  );

  @visibleForTesting
  static bool validPublicKey(String key, {required bool isIOS}) =>
      !key.startsWith('sk_') &&
      key.startsWith(isIOS ? 'appl_' : 'goog_') &&
      key.length > 5;

  /// AbuApiClient preserves the API's {data: ...} envelope. Never mistake
  /// client SDK state or an unrelated entitlement for a server grant.
  static bool serverConfirmedAccess(Object? envelope) {
    return SubscriptionAccessResult.fromEnvelope(envelope).isActive;
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _pending++;
    notifyListeners();
    _tail = _tail.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      } finally {
        _pending--;
        notifyListeners();
      }
    });
    return result.future;
  }

  void _onCustomerInfo(CustomerInfo info) {
    if (_userId == null || _switching) return;
    final expected = _userId;
    final generation = _generation;
    // A delayed native callback from another login must not paint this account.
    unawaited(() async {
      try {
        final nativeId = await Purchases.appUserID;
        if (nativeId != expected || generation != _generation || _switching) {
          return;
        }
        _customerInfo = info;
        notifyListeners();
      } catch (_) {
        // A later explicit refresh retries. Never grant backend access here.
      }
    }());
  }

  Future<void> _connect(String userId) async {
    if (!available) {
      throw const SubscriptionException(
        'Subscriptions are not configured yet. Add the store-specific public RevenueCat SDK key (appl_ for iOS or goog_ for Android).',
      );
    }
    if (userId.isEmpty || userId == 'guest') {
      throw const SubscriptionException(
        'Sign in before managing a subscription.',
      );
    }
    if (_configured && _userId == userId) return;
    _switching = true;
    _customerInfo = null;
    _serverAccess = null;
    _userId = null;
    final generation = ++_generation;
    try {
      CustomerInfo info;
      if (!_configured) {
        await Purchases.setLogLevel(
          kDebugMode ? LogLevel.debug : LogLevel.error,
        );
        await Purchases.configure(
          PurchasesConfiguration(apiKey)..appUserID = userId,
        );
        _configured = true;
        Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);
        info = await Purchases.getCustomerInfo();
      } else {
        info = (await Purchases.logIn(userId)).customerInfo;
      }
      if (generation != _generation) {
        throw const SubscriptionException(
          'The account changed. Please open subscriptions again.',
        );
      }
      _customerInfo = info;
      _userId = userId;
    } finally {
      _switching = false;
    }
  }

  Future<T> _forUser<T>(String userId, Future<T> Function() action) {
    final revision = _logoutRevision;
    return _enqueue(() async {
      if (revision != _logoutRevision) {
        throw const SubscriptionException(
          'The account changed. Please open subscriptions again.',
        );
      }
      await _connect(userId);
      final generation = _generation;
      final result = await action();
      if (_userId != userId || generation != _generation) {
        _customerInfo = null;
        throw const SubscriptionException(
          'The account changed. Please open subscriptions again.',
        );
      }
      return result;
    });
  }

  Future<CustomerInfo> refresh(String userId) => _forUser(userId, () async {
    await Purchases.invalidateCustomerInfoCache();
    return _customerInfo = await Purchases.getCustomerInfo();
  });

  Future<Offering> offering(String userId) =>
      _forUser(userId, _currentOffering);

  Future<Offering> _currentOffering() async {
    final current = (await Purchases.getOfferings()).current;
    if (current == null || current.availablePackages.isEmpty) {
      throw const SubscriptionException(
        'Subscription plans are not available yet. Please try again later.',
        code: 'plans_unavailable',
      );
    }
    return current;
  }

  Future<PaywallResult> showPaywall(
    String userId, {
    Future<PaywallResult> Function(Offering)? presenter,
    String? locale,
  }) => _forUser(userId, () async {
    if (locale != null) await Purchases.overridePreferredUILocale(locale);
    final offering = await _currentOffering();
    // RevenueCatUI owns the purchase. Do not also call purchase() from callbacks.
    final result = presenter != null
        ? await presenter(offering)
        : await RevenueCatUI.presentPaywall(
            offering: offering,
            displayCloseButton: true,
          );
    if (result == PaywallResult.purchased || result == PaywallResult.restored) {
      try {
        _customerInfo = await Purchases.getCustomerInfo();
      } catch (error) {
        // Never turn a completed payment into a failed purchase/retry. The
        // caller must still ask the server to verify and refresh the profile.
        debugPrint(
          '[Subscriptions] Post-purchase refresh unavailable (RC-${errorCode(error).index}).',
        );
      }
    }
    return result;
  });

  Future<CustomerInfo> purchase(String userId, Package package) => _forUser(
    userId,
    () async {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      return _customerInfo = result.customerInfo;
    },
  );

  Future<CustomerInfo> restore(String userId) => _forUser(userId, () async {
    return _customerInfo = await Purchases.restorePurchases();
  });

  Future<void> showCustomerCenter(String userId, {String? locale}) =>
      _forUser(userId, () async {
        if (locale != null) await Purchases.overridePreferredUILocale(locale);
        await RevenueCatUI.presentCustomerCenter();
        await Purchases.invalidateCustomerInfoCache();
        _customerInfo = await Purchases.getCustomerInfo();
      });

  Future<void> clearIdentity() {
    // Immediately hide account state, even if a store sheet is still open.
    _generation++;
    _logoutRevision++;
    _userId = null;
    _customerInfo = null;
    _serverAccess = null;
    notifyListeners();
    return _enqueue(() async {
      if (!_configured) return;
      try {
        if (!await Purchases.isAnonymous) await Purchases.logOut();
      } catch (_) {
        // Next login is explicit; Firebase sign-out must never be blocked.
      }
    });
  }

  @override
  void dispose() {
    if (_configured) {
      Purchases.removeCustomerInfoUpdateListener(_onCustomerInfo);
    }
    super.dispose();
  }

  static bool isCancellation(Object error) =>
      errorCode(error) == PurchasesErrorCode.purchaseCancelledError;

  /// Native UI failures can have textual codes. The SDK helper parses with
  /// num.parse and can throw while handling the original exception.
  static PurchasesErrorCode errorCode(Object error) {
    if (error is PurchasesError) return error.code;
    if (error is! PlatformException) return PurchasesErrorCode.unknownError;
    final index = int.tryParse(error.code);
    if (index == null ||
        index < 0 ||
        index >= PurchasesErrorCode.values.length) {
      return PurchasesErrorCode.unknownError;
    }
    return PurchasesErrorCode.values[index];
  }

  static String errorMessage(Object error) {
    if (error is SubscriptionException) return error.message;
    if (error is PlatformException) {
      return switch (errorCode(error)) {
        PurchasesErrorCode.paymentPendingError => 'Payment is pending approval. Access activates after the store confirms it.',
        PurchasesErrorCode.networkError =>
          'Unable to reach the store. Check your connection and try again.',
        PurchasesErrorCode.purchaseNotAllowedError =>
          'Purchases are disabled for this device or store account.',
        PurchasesErrorCode.productAlreadyPurchasedError =>
          'You already purchased this subscription. Use Restore purchases.',
        _ => 'The store could not complete this request. Please try again or contact support.',
      };
    }
    return 'Unable to update subscriptions. Please try again.';
  }
}
