import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/widgets/subscriber_badge.dart';
import '../../production/api_client.dart';
import '../../production/api_production_repository.dart';
import '../../production/app_preferences.dart';
import '../../production/models.dart';
import '../../production/production_repository.dart';
import '../../production/subscription_service.dart';

String _modeLabel(BuildContext context, SubscriptionAccessMode mode) =>
    switch (mode) {
      SubscriptionAccessMode.active => abuText(
        context,
        'Activate access',
        'تفعيل الصلاحيات',
      ),
      SubscriptionAccessMode.inactive => abuText(
        context,
        'Deactivate access',
        'تعطيل الصلاحيات',
      ),
      SubscriptionAccessMode.store => abuText(
        context,
        'Use store status',
        'استخدام حالة المتجر',
      ),
    };

String _billingWarning(BuildContext context) => abuText(
  context,
  'This changes app access only. It does not cancel, renew, or refund an Apple or Google subscription. Store billing continues separately. YouTube CSV membership is not changed.',
  'يغيّر هذا صلاحيات التطبيق فقط. لا يلغي اشتراك Apple أو Google ولا يجدده أو يرد مبلغه. تستمر فوترة المتجر بشكل منفصل. لا تتغير عضوية ملف CSV في يوتيوب.',
);

String _accessError(BuildContext context, Object error) {
  if (error is AbuApiException && error.statusCode == 403) {
    return abuText(
      context,
      'Only admins and super admins can manage access.',
      'يمكن للمدير والمدير الأعلى فقط إدارة الصلاحيات.',
    );
  }
  if (error is AbuApiException && error.statusCode == 404) {
    return abuText(
      context,
      'The user was not found or the server needs an update. Refresh and contact support.',
      'لم يُعثر على المستخدم أو يحتاج الخادم إلى تحديث. حدّث القائمة وتواصل مع الدعم.',
    );
  }
  return abuText(
    context,
    'Could not confirm the access change. Refresh this user before trying again.',
    'تعذر تأكيد تغيير الصلاحيات. حدّث بيانات المستخدم قبل المحاولة مجدداً.',
  );
}

typedef AdminUserPageLoader = Future<AdminUserPage> Function({
  required String search,
  required int limit,
  required int offset,
});

/// A separate directory avoids exposing super-admin-only role controls.
class AdminSubscriptionDialog extends StatefulWidget {
  const AdminSubscriptionDialog({
    super.key,
    required this.repository,
    required this.currentProfile,
    this.loadUsersPage,
  });
  final ProductionRepository repository;
  final AbuUserProfile currentProfile;
  final AdminUserPageLoader? loadUsersPage;

  @override
  State<AdminSubscriptionDialog> createState() =>
      _AdminSubscriptionDialogState();
}

class _AdminSubscriptionDialogState extends State<AdminSubscriptionDialog> {
  static const _pageSize = 200;

  final _search = TextEditingController();
  Timer? _debounce;
  List<AbuUserProfile> _users = const [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _nextOffset = 0;
  int _loadGeneration = 0;
  String _loadedSearch = '';
  Object? _loadError;
  Object? _loadMoreError;

  @override
  void initState() {
    super.initState();
    if (widget.currentProfile.canManageSubscriptions) {
      _loading = true;
      unawaited(_loadFirstPage(updateLoadingState: false));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    if (!mounted || !widget.currentProfile.canManageSubscriptions) return;
    unawaited(_loadFirstPage());
  }

  Future<AdminUserPage> _fetchPage({
    required String search,
    required int offset,
  }) {
    final loader = widget.loadUsersPage;
    return loader != null
        ? loader(search: search, limit: _pageSize, offset: offset)
        : widget.repository.fetchAdminUserPage(
            search: search,
            limit: _pageSize,
            offset: offset,
          );
  }

  Future<void> _loadFirstPage({bool updateLoadingState = true}) async {
    final generation = ++_loadGeneration;
    final search = _search.text.trim();
    if (updateLoadingState) {
      setState(() {
        _loading = true;
        _loadingMore = false;
        _loadError = null;
        _loadMoreError = null;
      });
    }
    try {
      final page = await _fetchPage(search: search, offset: 0);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _users = page.users;
        _loadedSearch = search;
        _nextOffset = page.offset + page.users.length;
        _hasMore = page.hasMore && page.users.isNotEmpty;
        _loading = false;
        _loadError = null;
        _loadMoreError = null;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    final generation = _loadGeneration;
    final search = _loadedSearch;
    final offset = _nextOffset;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final page = await _fetchPage(search: search, offset: offset);
      if (!mounted || generation != _loadGeneration) return;
      final knownUsers = <String>{
        for (final user in _users) _userIdentity(user),
      };
      final newUsers = page.users
          .where((user) => knownUsers.add(_userIdentity(user)))
          .toList(growable: false);
      setState(() {
        _users = [..._users, ...newUsers];
        _nextOffset = page.offset + page.users.length;
        _hasMore = page.hasMore && page.users.isNotEmpty;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadingMore = false;
        _loadMoreError = error;
      });
    }
  }

  String _userIdentity(AbuUserProfile user) => user.backendUserId.isNotEmpty
      ? 'backend:${user.backendUserId}'
      : 'firebase:${user.uid}';

  Widget _paginationFooter() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: OutlinedButton.icon(
          key: const Key('admin-access-load-more'),
          onPressed: _loadMore,
          icon: const Icon(Icons.refresh),
          label: Text(
            abuText(context, 'Retry loading more', 'أعد تحميل المزيد'),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: OutlinedButton.icon(
        key: const Key('admin-access-load-more'),
        onPressed: _loadMore,
        icon: const Icon(Icons.expand_more),
        label: Text(
          abuText(context, 'Load more users', 'تحميل مستخدمين آخرين'),
        ),
      ),
    );
  }

  Future<void> _edit(AbuUserProfile user) async {
    if (!widget.currentProfile.canManageSubscriptions) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AdminSubscriptionAccessEditor(
        user: user,
        onSave: ({required mode, required reason, expiresAt}) =>
            widget.repository.setAdminSubscriptionAccess(
              userId: user.backendUserId,
              mode: mode,
              reason: reason,
              expiresAt: expiresAt,
            ),
      ),
    );
    if (saved == true && mounted) _refresh();
  }

  String _status(AbuUserProfile user) {
    final expiry = user.subscriptionAccessExpiresAt;
    if (user.subscriptionAccessMode == SubscriptionAccessMode.active &&
        expiry != null &&
        !expiry.isAfter(DateTime.now())) {
      return abuText(
        context,
        'Admin grant expired · using store status',
        'انتهى منح المدير · تُستخدم حالة المتجر',
      );
    }
    return switch (user.subscriptionAccessMode) {
      SubscriptionAccessMode.active => abuText(
        context,
        'Admin-granted access',
        'صلاحيات ممنوحة من المدير',
      ),
      SubscriptionAccessMode.inactive => abuText(
        context,
        'Access blocked by admin',
        'الصلاحيات معطلة من المدير',
      ),
      SubscriptionAccessMode.store => abuText(
        context,
        'Managed by store status',
        'حسب حالة المتجر',
      ),
    };
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
    title: Text(abuText(context, 'Membership access', 'صلاحيات العضوية')),
    content: !widget.currentProfile.canManageSubscriptions
        ? Text(
            abuText(context, 'Admin access required.', 'تتطلب صلاحيات المدير.'),
          )
        : SizedBox(
            width: 640,
            height: math.min(MediaQuery.sizeOf(context).height * .66, 620),
            child: Column(
              children: [
                TextField(
                  key: const Key('admin-access-search'),
                  controller: _search,
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(
                      const Duration(milliseconds: 350),
                      _refresh,
                    );
                  },
                  decoration: InputDecoration(
                    labelText: abuText(
                      context,
                      'Search users',
                      'ابحث عن المستخدمين',
                    ),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      tooltip: abuText(context, 'Refresh', 'تحديث'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _loadError != null
                      ? Center(
                          child: Text(
                            abuText(
                              context,
                              'Users could not be loaded. Tap refresh to retry.',
                              'تعذر تحميل المستخدمين. اضغط تحديث للمحاولة.',
                            ),
                          ),
                        )
                      : _users.isEmpty
                      ? Center(
                          child: Text(
                            abuText(
                              context,
                              'No matching users',
                              'لا يوجد مستخدمون مطابقون',
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount:
                              _users.length +
                              ((_hasMore ||
                                      _loadingMore ||
                                      _loadMoreError != null)
                                  ? 1
                                  : 0),
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            if (index == _users.length) {
                              return _paginationFooter();
                            }
                            final user = _users[index];
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    SubscriberName(
                                      user.displayName.isNotEmpty
                                          ? user.displayName
                                          : user.username,
                                      isSubscriber: user.isProSubscriber,
                                      maxLines: 2,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      '@${user.username}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      user.isProSubscriber
                                          ? abuText(
                                              context,
                                              'App subscription access: active',
                                              'صلاحيات اشتراك التطبيق: نشطة',
                                            )
                                          : abuText(
                                              context,
                                              'App subscription access: inactive',
                                              'صلاحيات اشتراك التطبيق: غير نشطة',
                                            ),
                                    ),
                                    Text(
                                      _status(user),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                    if (user.subscriptionAccessExpiresAt !=
                                        null)
                                      Text(
                                        '${abuText(context, 'Grant ends', 'انتهاء المنح')}: ${MaterialLocalizations.of(context).formatMediumDate(user.subscriptionAccessExpiresAt!.toLocal())}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    const SizedBox(height: 6),
                                    OutlinedButton.icon(
                                      key: ValueKey(
                                        'admin-manage-access-${user.uid}',
                                      ),
                                      onPressed: user.backendUserId.isEmpty
                                          ? null
                                          : () => _edit(user),
                                      icon: const Icon(
                                        Icons.admin_panel_settings_outlined,
                                      ),
                                      label: Text(
                                        abuText(
                                          context,
                                          'Manage access',
                                          'إدارة الصلاحيات',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(abuText(context, 'Close', 'إغلاق')),
      ),
    ],
  );
}

typedef AdminAccessSave = Future<SubscriptionAccessResult> Function({
  required SubscriptionAccessMode mode,
  required String reason,
  DateTime? expiresAt,
});

class AdminSubscriptionAccessEditor extends StatefulWidget {
  const AdminSubscriptionAccessEditor({
    super.key,
    required this.user,
    required this.onSave,
  });
  final AbuUserProfile user;
  final AdminAccessSave onSave;

  @override
  State<AdminSubscriptionAccessEditor> createState() =>
      _AdminSubscriptionAccessEditorState();
}

class _AdminSubscriptionAccessEditorState
    extends State<AdminSubscriptionAccessEditor> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  late SubscriptionAccessMode _mode = widget.user.subscriptionAccessMode;
  late final DateTime? _existingGrantExpiry;
  late int _days;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final expiry = widget.user.subscriptionAccessExpiresAt;
    _existingGrantExpiry =
        widget.user.subscriptionAccessMode == SubscriptionAccessMode.active &&
            expiry != null &&
            expiry.isAfter(DateTime.now())
        ? expiry.toUtc()
        : null;
    // Preserve an existing audited end date unless the admin explicitly picks
    // a new duration. Reopening the editor must not silently make it permanent.
    _days = _existingGrantExpiry == null ? 0 : -1;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _review() async {
    if (_saving || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final reason = _reason.text.trim();
    final mode = _mode;
    final expiresAt = mode != SubscriptionAccessMode.active
        ? null
        : _days == -1
        ? _existingGrantExpiry
        : _days > 0
        ? DateTime.now().toUtc().add(Duration(days: _days))
        : null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(
          abuText(context, 'Confirm access change', 'تأكيد تغيير الصلاحيات'),
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.user.displayName.isNotEmpty
                  ? widget.user.displayName
                  : widget.user.username,
            ),
            Text(
              _modeLabel(context, mode),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(reason),
            if (mode == SubscriptionAccessMode.active) ...[
              const SizedBox(height: 8),
              Text(
                expiresAt == null
                    ? abuText(
                        context,
                        'Grant ends: when changed by an admin',
                        'ينتهي المنح: عندما يغيّره المدير',
                      )
                    : '${abuText(context, 'Grant ends', 'انتهاء المنح')}: ${MaterialLocalizations.of(context).formatMediumDate(expiresAt.toLocal())}',
              ),
            ],
            const SizedBox(height: 12),
            Text(_billingWarning(context)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(abuText(context, 'Cancel', 'إلغاء')),
          ),
          FilledButton(
            key: const Key('admin-access-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(abuText(context, 'Confirm change', 'تأكيد التغيير')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(mode: mode, reason: reason, expiresAt: expiresAt);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = _accessError(context, error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      scrollable: true,
      title: Text(
        abuText(context, 'Manage app access', 'إدارة صلاحيات التطبيق'),
      ),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.user.displayName.isNotEmpty
                    ? widget.user.displayName
                    : widget.user.username,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(_billingWarning(context)),
              const SizedBox(height: 16),
              DropdownButtonFormField<SubscriptionAccessMode>(
                key: const Key('admin-access-mode'),
                initialValue: _mode,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: abuText(context, 'Access mode', 'وضع الصلاحيات'),
                ),
                items: [
                  for (final mode in SubscriptionAccessMode.values)
                    DropdownMenuItem(
                      value: mode,
                      child: Text(_modeLabel(context, mode)),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (mode) {
                        if (mode != null) setState(() => _mode = mode);
                      },
              ),
              const SizedBox(height: 8),
              Text(switch (_mode) {
                SubscriptionAccessMode.active => abuText(
                  context,
                  'Grant member access without creating a store purchase.',
                  'منح صلاحيات الأعضاء دون إنشاء عملية شراء في المتجر.',
                ),
                SubscriptionAccessMode.inactive => abuText(
                  context,
                  'Block subscription-based app access even if the store subscription is active. Billing is not cancelled.',
                  'تعطيل صلاحيات اشتراك التطبيق حتى لو كان اشتراك المتجر نشطاً. لن تُلغى الفوترة.',
                ),
                SubscriptionAccessMode.store => abuText(
                  context,
                  'Remove the admin override. Verified store status decides access again.',
                  'إزالة قرار المدير. تحدد حالة المتجر الموثقة الصلاحيات مجدداً.',
                ),
              }),
              if (_mode == SubscriptionAccessMode.active) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: const Key('admin-access-duration'),
                  initialValue: _days,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: abuText(context, 'Grant duration', 'مدة المنح'),
                  ),
                  items: [
                    if (_existingGrantExpiry != null)
                      DropdownMenuItem(
                        value: -1,
                        child: Text(
                          '${abuText(context, 'Keep current end date', 'الإبقاء على تاريخ الانتهاء')}: ${MaterialLocalizations.of(context).formatMediumDate(_existingGrantExpiry.toLocal())}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    for (final days in [0, 7, 30, 90])
                      DropdownMenuItem(
                        value: days,
                        child: Text(
                          days == 0
                              ? abuText(
                                  context,
                                  'Until changed by an admin',
                                  'حتى يغيّره المدير',
                                )
                              : abuText(context, '$days days', '$days يوم'),
                        ),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (days) {
                          if (days != null) setState(() => _days = days);
                        },
                ),
              ],
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('admin-access-reason'),
                controller: _reason,
                enabled: !_saving,
                maxLength: 500,
                maxLines: 1,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: abuText(
                    context,
                    'Reason (required)',
                    'السبب (مطلوب)',
                  ),
                ),
                validator: (value) {
                  final reason = (value ?? '').trim();
                  if (reason.length < 3) {
                    return abuText(
                      context,
                      'Enter a reason of at least 3 characters.',
                      'أدخل سبباً من 3 أحرف على الأقل.',
                    );
                  }
                  if (reason.length > 500) {
                    return abuText(
                      context,
                      'Keep the reason within 500 characters.',
                      'اجعل السبب ضمن 500 حرف.',
                    );
                  }
                  if (!isValidAdminSubscriptionReason(reason)) {
                    return abuText(
                      context,
                      'Remove hidden control or formatting characters.',
                      'احذف رموز التحكم أو التنسيق المخفية.',
                    );
                  }
                  return null;
                },
              ),
              if (_error != null)
                Text(
                  _error!,
                  key: const Key('admin-access-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(abuText(context, 'Cancel', 'إلغاء')),
        ),
        FilledButton(
          key: const Key('admin-access-review'),
          onPressed: _saving ? null : _review,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(abuText(context, 'Review change', 'مراجعة التغيير')),
        ),
      ],
    ),
  );
}
