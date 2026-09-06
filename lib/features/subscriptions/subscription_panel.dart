import 'package:flutter/material.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../production/app_preferences.dart';
import '../../production/brand.dart';
import '../../production/models.dart';
import '../../production/production_repository.dart';
import '../../production/subscription_service.dart';
import 'subscription_feedback.dart';
import 'subscription_paywall_page.dart';

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
  SubscriptionFeedback? _message;
  String? _localAccessReason;
  String? get _accessReason =>
      _localAccessReason ??
      (_store.userId == widget.profile.backendUserId
          ? _store.serverAccess?.reason
          : null);
  final _detailsRevision = ValueNotifier<int>(0);
  bool _detailsOpen = false;

  void _update(VoidCallback change) {
    if (!mounted) return;
    setState(change);
    _detailsRevision.value++;
  }

  @override
  void dispose() {
    _detailsRevision.dispose();
    super.dispose();
  }

  Future<void> _perform(String action) async {
    final profile = widget.profile;
    if (_working || _store.busy || profile.isGuest) return;
    _update(() {
      _working = true;
      _activeAction = action;
      _message = null;
    });
    var storeCompleted = false;
    var showDetails = false;
    try {
      if (action == 'plans') {
        final result = await SubscriptionPaywallPage.open(
          context,
          service: _store,
          userId: profile.backendUserId,
        );
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
        await _store.showCustomerCenter(
          profile.backendUserId,
          locale: Localizations.localeOf(context).toLanguageTag(),
        );
      } else {
        await _store.refresh(profile.backendUserId);
      }
      storeCompleted = true;
      final access = await widget.repository.syncSubscriptionAccess(profile);
      if (!mounted || widget.profile.uid != profile.uid) return;
      final entitlement = _store
          .customerInfo
          ?.entitlements
          .active[SubscriptionService.entitlementId];
      final feedback = SubscriptionFeedback.checked(
        serverActive: access.isActive,
        storeActive: entitlement != null,
        isSandbox: entitlement?.isSandbox ?? false,
        accessReason: access.reason,
      );
      _update(() {
        _localAccessReason = access.reason;
        _message = feedback;
      });
      showDetails = action == 'plans' && !access.isActive;
    } catch (error) {
      if (!mounted ||
          widget.profile.uid != profile.uid ||
          SubscriptionService.isCancellation(error)) {
        return;
      }
      final feedback = SubscriptionFeedback.serverFailure(error);
      _update(
        () => _message = storeCompleted
            ? feedback
            : SubscriptionFeedback.storeFailure(error),
      );
      showDetails = action == 'plans';
    } finally {
      if (mounted) {
        _update(() {
          _working = false;
          _activeAction = null;
        });
      }
    }
    if (showDetails && mounted && widget.profile.uid == profile.uid) {
      await _openDetails();
    }
  }

  @override
  void didUpdateWidget(covariant SubscriptionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.uid != widget.profile.uid ||
        oldWidget.profile.backendUserId != widget.profile.backendUserId) {
      _message = null;
      _localAccessReason = null;
    }
    if (!identical(oldWidget.profile, widget.profile)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _detailsRevision.value++;
      });
    }
  }

  Future<void> _openDetails() async {
    if (_detailsOpen) return;
    _detailsOpen = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .88,
          ),
          child: AnimatedBuilder(
            animation: Listenable.merge([_store, _detailsRevision]),
            builder: (sheetContext, _) => Column(
              key: const Key('subscription-details-sheet'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          abuText(
                            sheetContext,
                            'Subscription details',
                            'تفاصيل الاشتراك',
                          ),
                          style: Theme.of(sheetContext).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        key: const Key('close-subscription-details'),
                        tooltip: abuText(sheetContext, 'Close', 'إغلاق'),
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      24 + MediaQuery.viewInsetsOf(sheetContext).bottom,
                    ),
                    child: _buildDetails(sheetContext),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      _detailsOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _store,
    builder: (context, _) {
      final profile = widget.profile;
      final storeActive =
          _store.userId == profile.backendUserId &&
          _store.customerInfo?.entitlements.active[SubscriptionService
                  .entitlementId] !=
              null;
      final active = profile.isProSubscriber;
      final memberAccess = active || profile.isYouTubeMember;
      final pending = !active && storeActive;
      final storeSandbox =
          pending &&
          _store
                  .customerInfo
                  ?.entitlements
                  .active[SubscriptionService.entitlementId]
                  ?.isSandbox ==
              true;
      final testSubscription =
          !active && (_accessReason == 'sandbox_not_allowed' || storeSandbox);
      final accessNotActive =
          !active &&
          const [
            'no_entitlement',
            'expired',
            'inactive',
          ].contains(_accessReason);
      final showPlans = !memberAccess && !pending && !testSubscription;
      final working = _working || _store.busy;
      final enabled =
          !working &&
          !profile.isGuest &&
          profile.backendUserId.isNotEmpty &&
          _store.available;
      final title = active
          ? abuText(context, 'Subscription active', 'الاشتراك نشط')
          : accessNotActive && pending
          ? abuText(context, 'Access not active', 'الصلاحيات غير مفعّلة')
          : testSubscription
          ? abuText(context, 'Test subscription', 'اشتراك تجريبي')
          : pending
          ? abuText(context, 'Access not confirmed', 'لم يتم تأكيد الصلاحيات')
          : memberAccess
          ? abuText(context, 'Member access active', 'مزايا العضوية مفعّلة')
          : abuText(context, 'Ostoora3 membership', 'عضوية الأسطورة');
      final subtitle = accessNotActive && pending
          ? abuText(context, 'Review subscription status', 'راجع حالة الاشتراك')
          : testSubscription
          ? abuText(
              context,
              'Not a live paid subscription',
              'ليس اشتراكاً مدفوعاً فعلياً',
            )
          : pending
          ? abuText(
              context,
              'Store subscription found',
              'تم العثور على اشتراك المتجر',
            )
          : active
          ? abuText(
              context,
              'Members + member bonuses',
              'قسم الأعضاء ومزايا العضوية',
            )
          : memberAccess
          ? abuText(context, 'YouTube membership', 'عضوية يوتيوب')
          : profile.isGuest
          ? abuText(context, 'Sign in to subscribe', 'سجّل الدخول للاشتراك')
          : abuText(
              context,
              'Members + member bonuses',
              'قسم الأعضاء ومزايا العضوية',
            );
      final color = memberAccess ? AbuBrand.lime : AbuBrand.gold;
      return Container(
        key: const Key('subscription-summary'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AbuBrand.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AbuBrand.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              pending
                  ? Icons.schedule_rounded
                  : Icons.workspace_premium_rounded,
              color: color,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: _openDetails,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _message != null && !active && !testSubscription
                            ? abuText(
                                context,
                                'Review subscription status',
                                'راجع حالة الاشتراك',
                              )
                            : subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AbuBrand.muted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (working)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (showPlans && enabled)
              FilledButton(
                key: const Key('subscription-view-plans'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 44),
                ),
                onPressed: () => _perform('plans'),
                child: Text(abuText(context, 'View plans', 'عرض الخطط')),
              )
            else
              TextButton(
                key: const Key('subscription-open-details'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 44),
                ),
                onPressed: _openDetails,
                child: Text(
                  abuText(
                    context,
                    active ? 'Manage' : 'Details',
                    active ? 'إدارة' : 'التفاصيل',
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );

  Widget _buildDetails(BuildContext context) => AnimatedBuilder(
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
      final hasSubscription =
          profile.isProSubscriber ||
          entitlement != null ||
          _accessReason == 'sandbox_not_allowed';
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
                'Both plans include access to Members and member bonuses. Prices and renewal terms are shown by the store before purchase.',
                'تتضمن الخطتان محتوى الأعضاء ومزايا العضوية. يعرض المتجر السعر وشروط التجديد قبل الشراء.',
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
                  entitlement.isSandbox
                      ? 'Test subscription · access not active'
                      : const [
                          'no_entitlement',
                          'expired',
                          'inactive',
                        ].contains(_accessReason)
                      ? 'Store subscription found · access not active'
                      : 'Store subscription found · access not confirmed',
                  entitlement.isSandbox
                      ? 'اشتراك تجريبي · الصلاحيات غير مفعّلة'
                      : const [
                          'no_entitlement',
                          'expired',
                          'inactive',
                        ].contains(_accessReason)
                      ? 'تم العثور على اشتراك المتجر · الصلاحيات غير مفعّلة'
                      : 'تم العثور على اشتراك المتجر · لم يتم تأكيد الصلاحيات',
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
            if (hasSubscription)
              TextButton.icon(
                key: const Key('subscription-details-view-plans'),
                onPressed: enabled ? () => _perform('plans') : null,
                icon: const Icon(Icons.view_carousel_outlined),
                label: Text(abuText(context, 'View plans', 'عرض الخطط')),
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
                child: Text(
                  abuText(context, _message!.english, _message!.arabic),
                  style: const TextStyle(height: 1.45),
                ),
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
