import 'dart:async';

import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

enum SubscriptionPlanDiagnosticCategory {
  productsAvailable('products_available'),
  productsMissing('products_missing'),
  storeRequestFailed('store_request_failed');

  const SubscriptionPlanDiagnosticCategory(this.code);
  final String code;
}

/// A deliberately limited support report, never a subscription/access decision.
///
/// Only this library can construct reports, so raw SDK errors, unknown product
/// identifiers, credentials and customer data cannot enter the report fields.
class SubscriptionPlanDiagnosticReport {
  SubscriptionPlanDiagnosticReport._({
    required this.categoryKind,
    required this.checkedAtUtc,
    required List<String> returnedProductIds,
    required this.storefrontCountryCode,
    required this.originalSupportCode,
    required this.productLookupErrorCode,
    required this.storefrontErrorCode,
  }) : returnedProductIds = List.unmodifiable(returnedProductIds);

  final SubscriptionPlanDiagnosticCategory categoryKind;
  String get category => categoryKind.code;
  final DateTime checkedAtUtc;
  List<String> get requestedProductIds =>
      SubscriptionPlanDiagnosticsRunner.knownProductIds;
  final List<String> returnedProductIds;
  List<String> get missingProductIds => List.unmodifiable(
    requestedProductIds.where((id) => !returnedProductIds.contains(id)),
  );
  final String? storefrontCountryCode;
  final String? originalSupportCode;
  final String? productLookupErrorCode;
  final String? storefrontErrorCode;

  String get supportText => [
    'ABU 3MEER subscription plan diagnostic v1',
    'Checked at (UTC): ${checkedAtUtc.toIso8601String()}',
    'Result: $category',
    'Original error: ${_describeCode(originalSupportCode, absent: 'not_provided')}',
    'Requested products: ${requestedProductIds.join(', ')}',
    'Returned products: ${_describeIds(returnedProductIds)}',
    'Missing products: ${_describeIds(missingProductIds)}',
    'Storefront country: ${storefrontCountryCode ?? 'unavailable'}',
    'Product lookup: ${_describeCode(productLookupErrorCode, absent: 'completed')}',
    'Storefront lookup: ${_describeCode(storefrontErrorCode, absent: 'completed')}',
    'Read-only SDK product check. No purchase or restore was requested.',
    'Product availability does not confirm payment, entitlement or release readiness.',
  ].join('\n');

  @override
  String toString() => supportText;
}

typedef SubscriptionProductLookup = Future<List<String>> Function(
  List<String> productIds,
);
typedef SubscriptionStorefrontLookup = Future<String?> Function();

/// Checks the configured SDK's product response without changing SDK identity.
///
/// The caller must already have configured RevenueCat. This runner does not
/// configure, log in/out, purchase, restore, read receipts or retrieve customers.
/// SDK reads may use their own cache; this is not proof of a fresh store request.
class SubscriptionPlanDiagnosticsRunner {
  SubscriptionPlanDiagnosticsRunner({
    SubscriptionProductLookup? getProducts,
    SubscriptionStorefrontLookup? getStorefrontCountry,
    Duration timeout = const Duration(seconds: 15),
    DateTime Function()? now,
  }) : _getProducts = getProducts ?? _sdkProducts,
       _getStorefrontCountry = getStorefrontCountry ?? _sdkStorefrontCountry,
       _timeout = timeout,
       _now = now ?? DateTime.now {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive');
    }
  }

  static const knownProductIds = ['Ostoora3', 'Ostoora3_Pro_Max'];

  final SubscriptionProductLookup _getProducts;
  final SubscriptionStorefrontLookup _getStorefrontCountry;
  final Duration _timeout;
  final DateTime Function() _now;

  Future<SubscriptionPlanDiagnosticReport> check({
    String? originalSupportCode,
  }) async {
    final checkedAtUtc = _now().toUtc();
    // Both reads start before either is awaited. Each independently times out.
    final productsRead = _read(() => _getProducts(knownProductIds));
    final storefrontRead = _read(_getStorefrontCountry);
    final products = await productsRead;
    final storefront = await storefrontRead;

    // Ignore unexpected identifiers entirely, including duplicates and casing
    // variants. Keeping only known IDs also prevents untrusted data in reports.
    final returnedProductIds = knownProductIds
        .where((id) => products.value?.contains(id) ?? false)
        .toList(growable: false);
    final category = products.errorCode != null
        ? SubscriptionPlanDiagnosticCategory.storeRequestFailed
        : returnedProductIds.length == knownProductIds.length
        ? SubscriptionPlanDiagnosticCategory.productsAvailable
        : SubscriptionPlanDiagnosticCategory.productsMissing;

    return SubscriptionPlanDiagnosticReport._(
      categoryKind: category,
      checkedAtUtc: checkedAtUtc,
      returnedProductIds: returnedProductIds,
      storefrontCountryCode: _safeCountryCode(storefront.value),
      originalSupportCode: originalSupportCode == null
          ? null
          : _safeSupportCode(originalSupportCode) ?? 'unknown_error',
      productLookupErrorCode: products.errorCode,
      storefrontErrorCode: storefront.errorCode,
    );
  }

  Future<_ReadResult<T>> _read<T>(Future<T> Function() read) async {
    try {
      return _ReadResult(value: await Future<T>.sync(read).timeout(_timeout));
    } on TimeoutException {
      // A timeout stops waiting; it does not cancel the native SDK request.
      return _ReadResult(errorCode: 'timeout');
    } on PlatformException catch (error) {
      return _ReadResult(
        errorCode: _safeSupportCode(error.code) ?? 'unknown_error',
      );
    } catch (_) {
      return _ReadResult(errorCode: 'unknown_error');
    }
  }

  static Future<List<String>> _sdkProducts(List<String> ids) async =>
      (await Purchases.getProducts(
        ids,
        productCategory: ProductCategory.subscription,
      )).map((product) => product.identifier).toList(growable: false);

  static Future<String?> _sdkStorefrontCountry() async =>
      (await Purchases.storefront)?.countryCode;
}

class _ReadResult<T> {
  const _ReadResult({this.value, this.errorCode});
  final T? value;
  final String? errorCode;
}

String _describeIds(List<String> ids) => ids.isEmpty ? 'none' : ids.join(', ');

String? _safeCountryCode(String? value) {
  if (value == null || !RegExp(r'^[A-Za-z]{2,3}$').hasMatch(value)) {
    return null;
  }
  return value.toUpperCase();
}

String? _safeSupportCode(String value) {
  // Exact matching only: never extract a code from a free-form native message.
  if (value == 'RC-PLANS' || value == 'plans_unavailable') return 'RC-PLANS';
  for (final error in PurchasesErrorCode.values) {
    if (value == '${error.index}' ||
        value == 'RC-${error.index}' ||
        value == error.name) {
      return 'RC-${error.index}';
    }
  }
  return null;
}

String _describeCode(String? code, {required String absent}) {
  if (code == null) return absent;
  for (final error in PurchasesErrorCode.values) {
    if (code == 'RC-${error.index}') return '$code (${error.name})';
  }
  return code;
}
