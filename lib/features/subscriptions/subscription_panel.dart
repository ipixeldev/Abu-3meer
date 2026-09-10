import 'package:flutter/material.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../production/app_preferences.dart';
import '../../production/brand.dart';
import '../../production/models.dart';
import '../../production/production_repository.dart';
import '../../production/subscription_service.dart';
import '../../production/youtube_membership_check.dart';
import '../membership/manual_membership_dialog.dart';
import 'subscription_feedback.dart';
import 'subscription_paywall_page.dart';
import '../support/whatsapp_support_button.dart';

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
  SubscriptionAccessResult? _localAccess;
  YouTubeMembershipCheckResult? _localYouTubeCheck;
  String? get _accessReason =>
      _localAccess?.reason ??
      (widget.profile.subscriptionAccessReason != 'unknown'
          ? widget.profile.subscriptionAccessReason
          : _store.userId == widget.profile.backendUserId
          ? _store.serverAccess?.reason
          : null);
  bool get _accessActive =>
      _localAccess?.isActive ?? widget.profile.isProSubscriber;
  bool get _youtubeAccessActive => _localYouTubeCheck != null
      ? _localYouTubeCheck!.isYouTubeMember
      : (_localAccess?.youtubeMembershipActive ?? false) ||
            widget.profile.isYouTubeMember;
  bool get _memberAccessActive {
    if (_accessReason == 'admin_revoked') return false;
    if (_localYouTubeCheck != null) {
      return _localYouTubeCheck!.isYouTubeMember || _accessActive;
    }
    final local = _localAccess;
    if (local != null) {
      return local.hasMemberAccess;
    }
    return widget.profile.hasMemberAccess;
  }

  String get _memberAccessSource {
    if (_accessReason == 'admin_revoked') return 'admin';
    if (_localYouTubeCheck?.isYouTubeMember == true) return 'youtube';
    final source = _localAccess?.memberAccessSource;
    if (source != null && source != 'none') return source;
    if (widget.profile.memberAccessSource != 'none') {
      return widget.profile.memberAccessSource;
    }
    if (_youtubeAccessActive) return 'youtube';
    if (_accessActive) {
      return _accessReason == 'admin_granted' ? 'admin' : 'store';
    }
    return 'none';
  }

  DateTime? get _youtubeAccessExpiresAt =>
      _localYouTubeCheck?.recheckRequiredAt ??
      _localYouTubeCheck?.snapshotExpiresAt ??
      _localAccess?.youtubeMembershipExpiresAt ??
      widget.profile.youtubeMembershipExpiresAt ??
      (_memberAccessSource == 'youtube'
          ? _localAccess?.memberAccessExpiresAt ??
                widget.profile.memberAccessExpiresAt
          : null);

  bool get _youtubeRecheckRequired =>
      (_localAccess?.youtubeMembershipRecheckRequired ?? false) ||
      widget.profile.youtubeMembershipRecheckRequired;
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
    final localAccessOnly =
        action == 'refresh' &&
        const ['admin_granted', 'admin_revoked'].contains(_accessReason);
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
      } else if (!localAccessOnly) {
        await _store.refresh(profile.backendUserId);
      }
      storeCompleted = true;
      final access = localAccessOnly
          ? await widget.repository.refreshSubscriptionAccess(profile)
          : await widget.repository.syncSubscriptionAccess(profile);
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
        _localAccess = access;
        _message =
            (access.hasMemberAccess && access.memberAccessSource == 'youtube')
            ? SubscriptionFeedback.youtubeMembershipActive(
                expiresAt: access.youtubeMembershipExpiresAt,
              )
            : feedback;
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

  Future<void> _checkYouTubeMembership() async {
    final profile = widget.profile;
    if (_working || profile.isGuest) return;
    final result = await showDialog<YouTubeMembershipCheckResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ManualMembershipDialog(
        onCheck: widget.repository.checkYouTubeMembership,
      ),
    );
    if (result == null || !mounted || widget.profile.uid != profile.uid) {
      return;
    }
    _update(() {
      _localYouTubeCheck = result;
      _message = result.isYouTubeMember && _accessReason != 'admin_revoked'
          ? SubscriptionFeedback.youtubeMembershipActive(
              expiresAt: result.recheckRequiredAt ?? result.snapshotExpiresAt,
            )
          : _accessReason == 'admin_revoked'
          ? SubscriptionFeedback.checked(
              serverActive: false,
              storeActive: false,
              isSandbox: false,
              accessReason: 'admin_revoked',
            )
          : SubscriptionFeedback.youtubeMembershipNotActive();
    });
    // The membership endpoint already refreshes once; this second read makes
    // the profile stream and every badge deterministic before the dialog is
    // dismissed, even when it previously held a cached profile.
    await widget.repository.refreshProfile(profile.uid, force: true);
  }

  String _formatDate(BuildContext context, DateTime value) =>
      MaterialLocalizations.of(context).formatMediumDate(value.toLocal());

  @override
  void didUpdateWidget(covariant SubscriptionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.uid != widget.profile.uid ||
        oldWidget.profile.backendUserId != widget.profile.backendUserId) {
      _message = null;
      _localAccess = null;
      _localYouTubeCheck = null;
    } else if (oldWidget.profile.isProSubscriber !=
            widget.profile.isProSubscriber ||
        oldWidget.profile.hasMemberAccess != widget.profile.hasMemberAccess ||
        oldWidget.profile.subscriptionAccessReason !=
            widget.profile.subscriptionAccessReason ||
        oldWidget.profile.subscriptionAccessMode !=
            widget.profile.subscriptionAccessMode ||
        oldWidget.profile.subscriptionAccessExpiresAt !=
            widget.profile.subscriptionAccessExpiresAt ||
        oldWidget.profile.isYouTubeMember != widget.profile.isYouTubeMember ||
        oldWidget.profile.youtubeMembershipExpiresAt !=
            widget.profile.youtubeMembershipExpiresAt ||
        oldWidget.profile.youtubeMembershipRecheckRequired !=
            widget.profile.youtubeMembershipRecheckRequired ||
        oldWidget.profile.memberAccessSource !=
            widget.profile.memberAccessSource) {
      // A newly delivered profile is authoritative over an earlier local
      // response. Until it arrives, the response keeps the panel from showing
      // the stale pre-refresh reason and access verdict.
      _localAccess = null;
      _localYouTubeCheck = null;
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
      final storeEntitlement = _store.userId == profile.backendUserId
          ? _store.customerInfo?.entitlements.active[SubscriptionService
                .entitlementId]
          : null;
      final storeActive = storeEntitlement != null;
      final active = _accessActive;
      final adminGranted = active && _accessReason == 'admin_granted';
      final adminBlocked = !active && _accessReason == 'admin_revoked';
      final youtubeActive = _youtubeAccessActive;
      final memberAccess = _memberAccessActive;
      final youtubePrimary =
          memberAccess &&
          youtubeActive &&
          (_memberAccessSource == 'youtube' || !active);
      final activeSandboxStore =
          active &&
          !youtubePrimary &&
          !adminGranted &&
          (storeEntitlement?.isSandbox == true ||
              (_localAccess?.environment == 'sandbox' &&
                  _localAccess?.memberAccessSource == 'store'));
      final youtubeRecheckRequired = !youtubeActive && _youtubeRecheckRequired;
      final pending = !memberAccess && storeActive && !adminBlocked;
      final storeSandbox =
          pending &&
          _store
                  .customerInfo
                  ?.entitlements
                  .active[SubscriptionService.entitlementId]
                  ?.isSandbox ==
              true;
      final testSubscription =
          !memberAccess &&
          !adminBlocked &&
          (_accessReason == 'sandbox_not_allowed' || storeSandbox);
      final accessNotActive =
          !active &&
          const [
            'no_entitlement',
            'expired',
            'inactive',
          ].contains(_accessReason);
      final showPlans =
          !memberAccess && !pending && !testSubscription && !adminBlocked;
      final working = _working || _store.busy;
      final enabled =
          !working &&
          !profile.isGuest &&
          profile.backendUserId.isNotEmpty &&
          _store.available;
      final title = youtubePrimary
          ? abuText(context, 'YouTube membership active', 'عضوية يوتيوب مفعّلة')
          : adminGranted
          ? abuText(context, 'Admin-granted access', 'صلاحيات ممنوحة من المدير')
          : adminBlocked
          ? abuText(
              context,
              'Subscription access blocked',
              'صلاحيات الاشتراك معطلة',
            )
          : active
          ? activeSandboxStore
                ? abuText(context, 'Sandbox active', 'اشتراك تجريبي مفعّل')
                : abuText(context, 'Subscription active', 'الاشتراك نشط')
          : youtubeRecheckRequired
          ? abuText(
              context,
              'YouTube membership needs recheck',
              'عضوية يوتيوب تحتاج إلى إعادة تحقق',
            )
          : accessNotActive && pending
          ? abuText(context, 'Access not active', 'الصلاحيات غير مفعّلة')
          : testSubscription
          ? abuText(context, 'Test subscription', 'اشتراك تجريبي')
          : pending
          ? abuText(context, 'Access not confirmed', 'لم يتم تأكيد الصلاحيات')
          : memberAccess
          ? abuText(context, 'Member access active', 'مزايا العضوية مفعّلة')
          : abuText(context, 'Ostoora3 membership', 'عضوية الأسطورة');
      final youtubeExpiry = _youtubeAccessExpiresAt;
      final subtitle = youtubePrimary
          ? youtubeExpiry == null
                ? abuText(
                    context,
                    'Verified from the current channel members list',
                    'موثّقة من قائمة أعضاء القناة الحالية',
                  )
                : abuText(
                    context,
                    'Active until ${_formatDate(context, youtubeExpiry)} · recheck required',
                    'مفعّلة حتى ${_formatDate(context, youtubeExpiry)} · يلزم إعادة التحقق',
                  )
          : adminGranted
          ? abuText(context, 'Not a store purchase', 'ليس شراءً من المتجر')
          : adminBlocked
          ? abuText(
              context,
              'Contact support · billing unchanged',
              'تواصل مع الدعم · الفوترة لم تتغير',
            )
          : active
          ? activeSandboxStore
                ? abuText(
                    context,
                    'Test purchase · badge active',
                    'شراء تجريبي · الشارة مفعّلة',
                  )
                : abuText(
                    context,
                    'Members + member bonuses',
                    'قسم الأعضاء ومزايا العضوية',
                  )
          : youtubeRecheckRequired
          ? abuText(
              context,
              'Check again or subscribe through the store',
              'تحقق مجدداً أو اشترك عبر المتجر',
            )
          : accessNotActive && pending
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
                        _message != null &&
                                !memberAccess &&
                                !testSubscription &&
                                !adminBlocked &&
                                !youtubeRecheckRequired
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
                    active && !adminGranted ? 'Manage' : 'Details',
                    active && !adminGranted ? 'إدارة' : 'التفاصيل',
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
      final accessActive = _accessActive;
      final youtubeActive =
          _memberAccessActive &&
          _youtubeAccessActive &&
          _memberAccessSource == 'youtube';
      final youtubeRecheckRequired = !youtubeActive && _youtubeRecheckRequired;
      final youtubeExpiresAt = _youtubeAccessExpiresAt;
      final enabled =
          !_working &&
          !_store.busy &&
          !profile.isGuest &&
          profile.backendUserId.isNotEmpty &&
          _store.available;
      final canCheckYouTube = !_working && !_store.busy && !profile.isGuest;
      final canRefreshLocalAccess =
          !_working &&
          !_store.busy &&
          !profile.isGuest &&
          profile.backendUserId.isNotEmpty &&
          const ['admin_granted', 'admin_revoked'].contains(_accessReason);
      final info = _store.userId == profile.backendUserId
          ? _store.customerInfo
          : null;
      final entitlement =
          info?.entitlements.active[SubscriptionService.entitlementId];
      final sandboxStoreAccess =
          entitlement?.isSandbox == true ||
          (_localAccess?.environment == 'sandbox' &&
              _localAccess?.memberAccessSource == 'store');
      final adminBlocked = _accessReason == 'admin_revoked';
      // A known store subscription must not lead the user back to buying it
      // again just because the separate server activation is unavailable.
      final hasStoreSubscription =
          (accessActive && _accessReason != 'admin_granted') ||
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
                    youtubeActive
                        ? abuText(context, 'YOUTUBE MEMBERSHIP', 'عضوية يوتيوب')
                        : abuText(
                            context,
                            'OSTOORA3 MEMBERSHIP',
                            'عضوية الأسطورة',
                          ),
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
            if (youtubeActive) ...[
              Text(
                abuText(
                  context,
                  'Your channel is present in the current members list. This membership is separate from store billing and does not auto-renew through this app.',
                  'قناتك موجودة في قائمة الأعضاء الحالية. هذه العضوية منفصلة عن فوترة المتجر ولا تتجدد عبر التطبيق.',
                ),
                style: const TextStyle(color: AbuBrand.muted, height: 1.45),
              ),
            ] else ...[
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
            ],
            if (youtubeActive) ...[
              const SizedBox(height: 12),
              Text(
                abuText(
                  context,
                  'YouTube membership active',
                  'عضوية يوتيوب مفعّلة',
                ),
                style: const TextStyle(
                  color: AbuBrand.lime,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                youtubeExpiresAt == null
                    ? abuText(
                        context,
                        'Member access and your badge are active. Check membership again when the app asks you to.',
                        'تم تفعيل مزايا الأعضاء والشارة. أعد التحقق عندما يطلب منك التطبيق ذلك.',
                      )
                    : abuText(
                        context,
                        'Access and your badge remain active through ${_formatDate(context, youtubeExpiresAt)}. Check membership again after that date.',
                        'تظل صلاحياتك والشارة مفعّلة حتى ${_formatDate(context, youtubeExpiresAt)}. أعد التحقق بعد ذلك التاريخ.',
                      ),
                style: const TextStyle(height: 1.45),
              ),
            ] else if (_accessReason == 'admin_granted' ||
                _accessReason == 'admin_revoked') ...[
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final feedback = SubscriptionFeedback.checked(
                    serverActive: accessActive,
                    storeActive: entitlement != null,
                    isSandbox: entitlement?.isSandbox ?? false,
                    accessReason: _accessReason!,
                  );
                  return Text(
                    abuText(context, feedback.english, feedback.arabic),
                    style: const TextStyle(color: AbuBrand.gold, height: 1.45),
                  );
                },
              ),
            ] else if (accessActive) ...[
              const SizedBox(height: 12),
              Text(
                sandboxStoreAccess
                    ? abuText(
                        context,
                        'Sandbox subscription active',
                        'اشتراك تجريبي مفعّل',
                      )
                    : abuText(context, 'Subscription active', 'الاشتراك نشط'),
                style: const TextStyle(
                  color: AbuBrand.lime,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (sandboxStoreAccess)
                Text(
                  abuText(
                    context,
                    'This is a test purchase, not a live charge. Member access and your badge are active in this sandbox environment.',
                    'هذه عملية شراء تجريبية وليست رسماً فعلياً. مزايا العضوية والشارة مفعّلة في بيئة Sandbox.',
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
            ] else if (youtubeRecheckRequired) ...[
              const SizedBox(height: 12),
              Text(
                abuText(
                  context,
                  'Your previous YouTube membership check has expired. Check the channel again to reactivate access, or subscribe through the store.',
                  'انتهت صلاحية التحقق السابق من عضوية يوتيوب. تحقق من القناة مجدداً لإعادة تفعيل الصلاحيات، أو اشترك عبر المتجر.',
                ),
                style: const TextStyle(color: AbuBrand.gold),
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
            const SizedBox(height: 14),
            if (youtubeActive || youtubeRecheckRequired)
              FilledButton.tonalIcon(
                key: const Key('youtube-membership-recheck'),
                onPressed: canCheckYouTube ? _checkYouTubeMembership : null,
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(
                  abuText(
                    context,
                    youtubeActive
                        ? 'Check YouTube membership again'
                        : 'Recheck YouTube membership',
                    youtubeActive
                        ? 'تحقق من عضوية يوتيوب مجدداً'
                        : 'أعد التحقق من عضوية يوتيوب',
                  ),
                ),
              ),
            if (youtubeActive || youtubeRecheckRequired)
              const SizedBox(height: 8),
            if (!adminBlocked || hasStoreSubscription)
              FilledButton.icon(
                onPressed: enabled
                    ? () => _perform(hasStoreSubscription ? 'manage' : 'plans')
                    : null,
                icon: Icon(
                  hasStoreSubscription
                      ? Icons.manage_accounts_outlined
                      : Icons.star_outline_rounded,
                ),
                label: Text(
                  abuText(
                    context,
                    hasStoreSubscription
                        ? 'Manage store subscription'
                        : youtubeActive || youtubeRecheckRequired
                        ? 'View store plans'
                        : 'View plans',
                    hasStoreSubscription
                        ? 'إدارة اشتراك المتجر'
                        : youtubeActive || youtubeRecheckRequired
                        ? 'عرض خطط المتجر'
                        : 'عرض الخطط',
                  ),
                ),
              ),
            if (hasStoreSubscription && !adminBlocked)
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
                if (!adminBlocked)
                  TextButton(
                    onPressed: enabled ? () => _perform('restore') : null,
                    child: Text(
                      abuText(
                        context,
                        'Restore purchases',
                        'استعادة المشتريات',
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: enabled || canRefreshLocalAccess
                      ? () => _perform('refresh')
                      : null,
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
                if (!hasStoreSubscription && !adminBlocked)
                  TextButton(
                    onPressed: enabled ? () => _perform('manage') : null,
                    child: Text(
                      abuText(context, 'Customer Center', 'مركز العملاء'),
                    ),
                  ),
              ],
            ),
            const WhatsAppSupportButton(),
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
              youtubeActive
                  ? abuText(
                      context,
                      'YouTube membership does not auto-renew through this app. App Store and Google Play plans are separate auto-renewing subscriptions and can be managed in your store account settings.',
                      'عضوية يوتيوب لا تتجدد عبر هذا التطبيق. خطط App Store وGoogle Play هي اشتراكات منفصلة تتجدد تلقائياً ويمكن إدارتها من إعدادات حساب المتجر.',
                    )
                  : abuText(
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
