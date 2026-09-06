import 'package:flutter/material.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../production/app_preferences.dart';
import '../../production/brand.dart';
import '../../production/models.dart';
import '../../production/production_repository.dart';
import '../../production/subscription_service.dart';
import 'subscription_feedback.dart';

/// This panel never unlocks content from SDK state. The refreshed server
/// profile is the access authority, including for restores and renewals.
class SubscriptionPanel extends StatefulWidget {
  const SubscriptionPanel({
    super.key,
    required this.repository,
    required this.profile,
    this.subscriptionService,
  });
  final ProductionRepository repository;
  final AbuUserProfile profile;
  final SubscriptionService? subscriptionService;

  @override
  State<SubscriptionPanel> createState() => _SubscriptionPanelState();
}

class _SubscriptionPanelState extends State<SubscriptionPanel> {
  SubscriptionService get _store =>
      widget.subscriptionService ?? SubscriptionService.instance;
  bool _working = false;
  String? _activeAction;
  String? _message;

  Future<void> _perform(String action) async {
    final profile = widget.profile;
    if (_working || _store.busy || profile.isGuest) return;
    setState(() {
      _working = true;
      _activeAction = action;
      _message = null;
    });
    var storeCompleted = false;
    try {
      if (action == 'plans') {
        final result = await _store.showPaywall(profile.backendUserId);
        if (result == PaywallResult.cancelled ||
            result == PaywallResult.notPresented) {
          return;
        }
        if (result == PaywallResult.error) {
          throw const SubscriptionException(
            'The store could not open or complete this purchase. Please try again.',
          );
        }
      } else if (action == 'restore') {
        await _store.restore(profile.backendUserId);
      } else if (action == 'manage') {
        await _store.showCustomerCenter(profile.backendUserId);
      } else {
        await _store.refresh(profile.backendUserId);
      }
      storeCompleted = true;
      final serverActive = await widget.repository.syncSubscription(profile);
      if (!mounted || widget.profile.uid != profile.uid) return;
      final entitlement = _store
          .customerInfo
          ?.entitlements
          .active[SubscriptionService.entitlementId];
      final feedback = SubscriptionFeedback.checked(
        serverActive: serverActive,
        storeActive: entitlement != null,
        isSandbox: entitlement?.isSandbox ?? false,
      );
      setState(
        () => _message = abuText(context, feedback.english, feedback.arabic),
      );
    } catch (error) {
      if (!mounted ||
          widget.profile.uid != profile.uid ||
          SubscriptionService.isCancellation(error)) {
        return;
      }
      final feedback = SubscriptionFeedback.serverFailure(error);
      setState(
        () => _message = storeCompleted
            ? abuText(context, feedback.english, feedback.arabic)
            : SubscriptionService.errorMessage(error),
      );
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _activeAction = null;
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant SubscriptionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.uid != widget.profile.uid) _message = null;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _store,
    builder: (context, _) {
      final profile = widget.profile;
      final enabled =
          !_working &&
          !_store.busy &&
          !profile.isGuest &&
          profile.backendUserId.isNotEmpty &&
          _store.available;
      final info = _store.userId == profile.backendUserId
          ? _store.customerInfo
          : null;
      final entitlement =
          info?.entitlements.active[SubscriptionService.entitlementId];
      // A known store subscription must not lead the user back to buying it
      // again just because the separate server activation is unavailable.
      final hasSubscription = profile.isProSubscriber || entitlement != null;
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AbuBrand.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AbuBrand.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.workspace_premium_rounded,
                  color: AbuBrand.gold,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    abuText(context, 'OSTOORA3 MEMBERSHIP', 'عضوية الأسطورة'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (_working || _store.busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              abuText(
                context,
                'Ostoora3 · Monthly\nOstoora3 Pro Max · Yearly',
                'Ostoora3 · شهري\nOstoora3 Pro Max · سنوي',
              ),
              style: const TextStyle(height: 1.6),
            ),
            const SizedBox(height: 8),
            Text(
              abuText(
                context,
                'Both plans include Members Zone access and member bonuses. Prices and renewal terms are shown by the store before purchase.',
                'تتضمن الخطتان دخول منطقة الأعضاء ومزايا العضوية. يعرض المتجر السعر وشروط التجديد قبل الشراء.',
              ),
              style: const TextStyle(color: AbuBrand.muted, height: 1.4),
            ),
            if (profile.isProSubscriber) ...[
              const SizedBox(height: 12),
              Text(
                abuText(context, 'Subscription active', 'الاشتراك نشط'),
                style: const TextStyle(
                  color: AbuBrand.lime,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (entitlement != null && !entitlement.willRenew)
                Text(
                  abuText(
                    context,
                    'Renewal is off. Access continues until the current paid period ends.',
                    'التجديد متوقف. تستمر الصلاحيات حتى نهاية الفترة المدفوعة.',
                  ),
                ),
            ] else if (entitlement != null) ...[
              const SizedBox(height: 12),
              Text(
                abuText(
                  context,
                  'Store subscription found · activation pending',
                  'تم العثور على اشتراك المتجر · التفعيل قيد الانتظار',
                ),
                style: const TextStyle(
                  color: AbuBrand.gold,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (entitlement.isSandbox)
                Text(
                  abuText(
                    context,
                    'Test purchase · not a live paid subscription',
                    'عملية شراء تجريبية · ليست اشتراكاً مدفوعاً فعلياً',
                  ),
                ),
            ] else if (profile.isYouTubeMember) ...[
              const SizedBox(height: 12),
              Text(
                abuText(
                  context,
                  'Your CSV membership already includes member access. A store subscription is optional.',
                  'عضويتك في ملف CSV تمنحك صلاحيات الأعضاء بالفعل. اشتراك المتجر اختياري.',
                ),
                style: const TextStyle(color: AbuBrand.gold),
              ),
            ],
            if (profile.isGuest) ...[
              const SizedBox(height: 12),
              Text(
                abuText(
                  context,
                  'Sign in to subscribe or restore purchases.',
                  'سجّل الدخول للاشتراك أو استعادة المشتريات.',
                ),
              ),
            ] else if (!_store.available) ...[
              const SizedBox(height: 12),
              Text(
                abuText(
                  context,
                  'Subscriptions will be available once store setup is complete.',
                  'ستتوفر الاشتراكات بعد اكتمال إعداد المتجر.',
                ),
              ),
            ],
            if (_store.usesTestStore) ...[
              const SizedBox(height: 8),
              Text(
                abuText(
                  context,
                  'TEST STORE · simulated purchases only',
                  'متجر تجريبي · مشتريات محاكاة فقط',
                ),
                style: const TextStyle(color: AbuBrand.gold, fontSize: 12),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: enabled
                  ? () => _perform(hasSubscription ? 'manage' : 'plans')
                  : null,
              icon: Icon(
                hasSubscription
                    ? Icons.manage_accounts_outlined
                    : Icons.star_outline_rounded,
              ),
              label: Text(
                abuText(
                  context,
                  hasSubscription ? 'Manage subscription' : 'View plans',
                  hasSubscription ? 'إدارة الاشتراك' : 'عرض الخطط',
                ),
              ),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: enabled ? () => _perform('restore') : null,
                  child: Text(
                    abuText(context, 'Restore purchases', 'استعادة المشتريات'),
                  ),
                ),
                TextButton(
                  onPressed: enabled ? () => _perform('refresh') : null,
                  child: Text(
                    abuText(
                      context,
                      _activeAction == 'refresh'
                          ? 'Refreshing…'
                          : 'Refresh access',
                      _activeAction == 'refresh'
                          ? 'جارٍ التحديث…'
                          : 'تحديث الصلاحيات',
                    ),
                  ),
                ),
                if (!hasSubscription)
                  TextButton(
                    onPressed: enabled ? () => _perform('manage') : null,
                    child: Text(
                      abuText(context, 'Customer Center', 'مركز العملاء'),
                    ),
                  ),
              ],
            ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(_message!, style: const TextStyle(height: 1.45)),
              ),
            ],
            const Divider(),
            Text(
              abuText(
                context,
                'Auto-renewing subscriptions. Manage or cancel in your store account settings. Deleting the app or your app account does not cancel a subscription.',
                'تتجدد الاشتراكات تلقائياً. يمكنك إدارتها أو إلغاؤها من إعدادات حساب المتجر. حذف التطبيق أو حسابك فيه لا يلغي الاشتراك.',
              ),
              style: const TextStyle(
                fontSize: 11,
                color: AbuBrand.muted,
                height: 1.4,
              ),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse(AbuBrand.privacyUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(abuText(context, 'Privacy', 'الخصوصية')),
                ),
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse(AbuBrand.termsUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(abuText(context, 'Terms', 'الشروط')),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
