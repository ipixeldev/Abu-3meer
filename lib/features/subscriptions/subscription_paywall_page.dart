import 'dart:async';

import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

import '../../production/app_preferences.dart';
import '../../production/brand.dart';
import '../../production/subscription_service.dart';
import 'subscription_feedback.dart';

/// Opens immediately, before StoreKit product loading. The published offering
/// is rendered by RevenueCatUI, not by a hard-coded replacement paywall.
class SubscriptionPaywallPage extends StatefulWidget {
  const SubscriptionPaywallPage({
    super.key,
    required this.service,
    required this.userId,
  });
  final SubscriptionService service;
  final String userId;

  static Future<PaywallResult> open(
    BuildContext context, {
    required SubscriptionService service,
    required String userId,
  }) async =>
      await Navigator.of(context).push<PaywallResult>(
        MaterialPageRoute(
          builder: (_) =>
              SubscriptionPaywallPage(service: service, userId: userId),
        ),
      ) ??
      PaywallResult.cancelled;

  @override
  State<SubscriptionPaywallPage> createState() =>
      _SubscriptionPaywallPageState();
}

class _SubscriptionPaywallPageState extends State<SubscriptionPaywallPage> {
  Offering? _offering;
  Object? _error;
  Completer<PaywallResult>? _presentation;
  bool _loading = true;
  bool _purchaseInProgress = false;
  bool _closing = false;
  PaywallResult? _completedPurchase;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _offering = null;
    });
    try {
      final result = await widget.service.showPaywall(
        widget.userId,
        locale: Localizations.localeOf(context).toLanguageTag(),
        presenter: (offering) {
          if (!mounted || _closing)
            return Future.value(PaywallResult.cancelled);
          _presentation = Completer<PaywallResult>();
          setState(() {
            _offering = offering;
            _loading = false;
          });
          return _presentation!.future;
        },
      );
      if (!mounted || _closing) return;
      if (result == PaywallResult.error ||
          result == PaywallResult.notPresented) {
        throw const SubscriptionException('Paywall could not be displayed.');
      }
      if (ModalRoute.of(context)?.isCurrent != true) return;
      _closing = true;
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted || _closing) return;
      setState(() {
        _error = error;
        _loading = false;
        _offering = null;
      });
    }
  }

  void _complete(PaywallResult result) {
    if (result == PaywallResult.purchased || result == PaywallResult.restored) {
      _completedPurchase = result;
    }
    final pending = _presentation;
    if (pending != null && !pending.isCompleted) pending.complete(result);
  }

  void _close() {
    if (_purchaseInProgress || _closing) return;
    _closing = true;
    _complete(PaywallResult.cancelled);
    Navigator.of(context).pop(_completedPurchase ?? PaywallResult.cancelled);
  }

  void _storeError(PurchasesError error) {
    if (!mounted || _closing) return;
    setState(() {
      _purchaseInProgress = false;
    });
    if (SubscriptionService.isCancellation(error)) return;
    final feedback = SubscriptionFeedback.storeFailure(error);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${abuText(context, feedback.english, feedback.arabic)} (${SubscriptionFeedback.supportCode(error)})',
        ),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  void _setPurchasing(bool value) {
    if (mounted && !_closing)
      setState(() {
        _purchaseInProgress = value;
      });
  }

  @override
  void dispose() {
    _complete(PaywallResult.cancelled);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final feedback = error == null
        ? null
        : SubscriptionFeedback.storeFailure(error);
    return PopScope(
      canPop: !_purchaseInProgress && _completedPurchase == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _closing = true;
          _complete(PaywallResult.cancelled);
        }
      },
      child: Scaffold(
        key: const Key('subscription-paywall-page'),
        backgroundColor: AbuBrand.ink,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(abuText(context, 'Membership', 'العضوية')),
          actions: [
            IconButton(
              key: const Key('close-subscription-paywall'),
              tooltip: abuText(context, 'Close', 'إغلاق'),
              onPressed: _purchaseInProgress ? null : _close,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: _offering != null
              ? PaywallView(
                  key: ValueKey(_offering!.identifier),
                  offering: _offering,
                  displayCloseButton: true,
                  onPurchaseStarted: (_) => _setPurchasing(true),
                  onPurchaseCancelled: () => _setPurchasing(false),
                  onPurchaseCompleted: (_, _) {
                    _setPurchasing(false);
                    _complete(PaywallResult.purchased);
                  },
                  onRestoreCompleted: (_) => _complete(PaywallResult.restored),
                  onPurchaseError: _storeError,
                  onRestoreError: _storeError,
                  onDismiss: () => _complete(PaywallResult.cancelled),
                )
              : Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_loading) ...[
                          const CircularProgressIndicator(),
                          const SizedBox(height: 20),
                          Text(
                            abuText(
                              context,
                              'Loading subscription plans…',
                              'جارٍ تحميل خطط الاشتراك…',
                            ),
                          ),
                        ] else if (feedback != null) ...[
                          const Icon(
                            Icons.cloud_off_outlined,
                            size: 42,
                            color: AbuBrand.gold,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            abuText(
                              context,
                              'Plans unavailable',
                              'الخطط غير متاحة',
                            ),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            abuText(context, feedback.english, feedback.arabic),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            SubscriptionFeedback.supportCode(error!),
                            textDirection: TextDirection.ltr,
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _load,
                            child: Text(
                              abuText(context, 'Try again', 'حاول مجدداً'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
