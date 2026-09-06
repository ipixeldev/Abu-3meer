import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

import '../../production/app_preferences.dart';
import '../../production/brand.dart';
import '../../production/subscription_plan_diagnostics.dart';
import '../../production/subscription_service.dart';
import 'subscription_feedback.dart';

/// Opens immediately, before StoreKit product loading. The published offering
/// is rendered by RevenueCatUI, not by a hard-coded replacement paywall.
class SubscriptionPaywallPage extends StatefulWidget {
  const SubscriptionPaywallPage({
    super.key,
    required this.service,
    required this.userId,
    this.diagnostics,
  });
  final SubscriptionService service;
  final String userId;
  final SubscriptionPlanDiagnosticsRunner? diagnostics;

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
  SubscriptionPlanDiagnosticReport? _diagnostic;
  bool _checkingStore = false;
  bool _diagnosticUnavailable = false;
  int _diagnosticRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load() async {
    _diagnosticRevision++;
    setState(() {
      _loading = true;
      _error = null;
      _offering = null;
      _diagnostic = null;
      _checkingStore = false;
      _diagnosticUnavailable = false;
    });
    try {
      final result = await widget.service.showPaywall(
        widget.userId,
        locale: Localizations.localeOf(context).toLanguageTag(),
        presenter: (offering) {
          if (!mounted || _closing) {
            return Future.value(PaywallResult.cancelled);
          }
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

  Future<void> _checkStore() async {
    final error = _error;
    if (error == null || _checkingStore || _closing) return;
    final revision = ++_diagnosticRevision;
    setState(() {
      _checkingStore = true;
      _diagnosticUnavailable = false;
      _diagnostic = null;
    });
    try {
      // Read product availability only. Never configure another identity,
      // restore a receipt, purchase, or use this result to grant access.
      final report =
          await (widget.diagnostics ?? SubscriptionPlanDiagnosticsRunner())
              .check(
                originalSupportCode: SubscriptionFeedback.supportCode(error),
              );
      if (!mounted || _closing || revision != _diagnosticRevision) return;
      setState(() {
        _diagnostic = report;
        _checkingStore = false;
      });
    } catch (_) {
      if (!mounted || _closing || revision != _diagnosticRevision) return;
      setState(() {
        _checkingStore = false;
        _diagnosticUnavailable = true;
      });
    }
  }

  String _diagnosticSummary(SubscriptionPlanDiagnosticReport report) {
    if (report.category == 'products_available') {
      return abuText(
        context,
        'The store returned both plans. Tap Try again. If the paywall still fails, send this report to support.',
        'أعاد المتجر الخطتين. اضغط حاول مجدداً. إذا استمر تعذر عرض الخطط، أرسل هذا التقرير للدعم.',
      );
    }
    if (report.category == 'products_missing') {
      return report.returnedProductIds.isEmpty
          ? abuText(
              context,
              'The store returned no subscription products. This app’s store agreements, product setup and availability need checking.',
              'لم يُرجع المتجر أي منتجات اشتراك. يجب مراجعة اتفاقيات المتجر وإعدادات المنتجات وتوفرها لهذا التطبيق.',
            )
          : abuText(
              context,
              'The store returned only one plan. The other plan’s store setup or availability needs checking.',
              'أعاد المتجر خطة واحدة فقط. يجب مراجعة إعدادات الخطة الأخرى وتوفرها في المتجر.',
            );
    }
    return abuText(
      context,
      'The store check failed. Send this report to support to identify the failing request.',
      'تعذر إكمال فحص المتجر. أرسل هذا التقرير للدعم لتحديد الطلب الذي فشل.',
    );
  }

  Future<void> _copyDiagnostic() async {
    final report = _diagnostic;
    if (report == null) return;
    await Clipboard.setData(ClipboardData(text: report.supportText));
    if (!mounted || _closing) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(abuText(context, 'Report copied', 'تم نسخ التقرير')),
      ),
    );
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
    if (mounted && !_closing) {
      setState(() {
        _purchaseInProgress = value;
      });
    }
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
                            onPressed: _checkingStore ? null : _load,
                            child: Text(
                              abuText(context, 'Try again', 'حاول مجدداً'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            key: const Key('check-subscription-store'),
                            onPressed: _checkingStore ? null : _checkStore,
                            icon: _checkingStore
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.troubleshoot),
                            label: Text(
                              abuText(
                                context,
                                _checkingStore
                                    ? 'Checking store…'
                                    : 'Check store connection',
                                _checkingStore
                                    ? 'جارٍ فحص المتجر…'
                                    : 'فحص الاتصال بالمتجر',
                              ),
                            ),
                          ),
                          if (_diagnosticUnavailable)
                            Text(
                              abuText(
                                context,
                                'Could not create the report. Try again.',
                                'تعذر إنشاء التقرير. حاول مجدداً.',
                              ),
                            ),
                          if (_diagnostic case final report?) ...[
                            const Divider(height: 28),
                            Text(
                              _diagnosticSummary(report),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            SelectableText(
                              report.supportText,
                              key: const Key('subscription-store-report'),
                              textDirection: TextDirection.ltr,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            TextButton.icon(
                              key: const Key('copy-subscription-store-report'),
                              onPressed: _copyDiagnostic,
                              icon: const Icon(Icons.copy),
                              label: Text(
                                abuText(context, 'Copy report', 'نسخ التقرير'),
                              ),
                            ),
                            Text(
                              abuText(
                                context,
                                'This checks product loading only. It does not purchase, activate access, or confirm production approval. No account details are included.',
                                'يفحص هذا الإجراء تحميل المنتجات فقط، ولا يجري شراءً أو يفعل الصلاحيات أو يؤكد الموافقة على النشر. لا يتضمن التقرير بيانات الحساب.',
                              ),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
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
