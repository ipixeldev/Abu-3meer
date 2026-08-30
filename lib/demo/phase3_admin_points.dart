part of 'fan_league_app.dart';

Future<void> showAdminPointAdjustments(
  BuildContext context,
  ProductionRepository repository,
) => showDialog<void>(
  context: context,
  builder: (_) => _AdminPointAdjustmentDialog(repository: repository),
);

class _AdminPointAdjustmentDialog extends StatefulWidget {
  const _AdminPointAdjustmentDialog({required this.repository});

  final ProductionRepository repository;

  @override
  State<_AdminPointAdjustmentDialog> createState() =>
      _AdminPointAdjustmentDialogState();
}

class _AdminPointAdjustmentDialogState
    extends State<_AdminPointAdjustmentDialog> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  final _userSearch = TextEditingController();
  Timer? _searchDebounce;
  late Future<List<AbuUserProfile>> _users;
  String? _targetUserId;
  late String _idempotencyKey;
  bool _deduct = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _idempotencyKey = widget.repository.newAdminPointAdjustmentKey();
    _users = widget.repository.fetchAdminUsers();
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    _userSearch.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _queueUserSearch(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _refreshUsers);
  }

  void _refreshUsers() {
    if (!mounted) return;
    setState(() {
      _users = widget.repository.fetchAdminUsers(search: _userSearch.text);
    });
  }

  AbuUserProfile? _selectedUser(List<AbuUserProfile> users) {
    for (final user in users) {
      if (user.uid == _targetUserId) return user;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
    titlePadding: const EdgeInsets.fromLTRB(24, 22, 12, 8),
    title: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _productionPrimary(context).withValues(alpha: .12),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(Icons.tune_rounded, color: _productionPrimary(context)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                abuText(context, 'Point adjustments', 'تعديل النقاط'),
                style: _display(24),
              ),
              Text(
                abuText(
                  context,
                  'Atomic corrections · immutable audit history',
                  'تصحيحات ذرية · سجل تدقيق غير قابل للتعديل',
                ),
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: _submitting ? null : () => Navigator.pop(context),
          icon: Icon(Icons.close_rounded),
        ),
      ],
    ),
    content: SizedBox(
      width: 980,
      height: math.min(MediaQuery.sizeOf(context).height * .74, 690),
      child: Column(
        children: [
          TextField(
            controller: _userSearch,
            enabled: !_submitting,
            onChanged: _queueUserSearch,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _refreshUsers(),
            decoration: InputDecoration(
              labelText: abuText(
                context,
                'Search name, username or email',
                'ابحث بالاسم أو اسم المستخدم أو البريد',
              ),
              prefixIcon: const Icon(Icons.person_search_rounded),
              suffixIcon: IconButton(
                tooltip: _userSearch.text.isEmpty
                    ? abuText(context, 'Refresh', 'تحديث')
                    : abuText(context, 'Clear', 'مسح'),
                onPressed: _submitting
                    ? null
                    : () {
                        if (_userSearch.text.isNotEmpty) _userSearch.clear();
                        _refreshUsers();
                      },
                icon: Icon(
                  _userSearch.text.isEmpty
                      ? Icons.refresh_rounded
                      : Icons.close_rounded,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<List<AbuUserProfile>>(
              future: _users,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ProductionEmpty(
                    icon: Icons.cloud_off_rounded,
                    title: abuText(
                      context,
                      'Users could not be loaded',
                      'تعذر تحميل المستخدمين',
                    ),
                    body: productionErrorMessage(snapshot.error!),
                  );
                }
                final users = snapshot.data ?? const <AbuUserProfile>[];
                if (users.isEmpty) {
                  return _ProductionEmpty(
                    icon: Icons.people_outline_rounded,
                    title: abuText(
                      context,
                      'No matching users',
                      'لا يوجد مستخدمون مطابقون',
                    ),
                    body: abuText(
                      context,
                      'Try another name, username or email.',
                      'جرّب اسماً أو اسم مستخدم أو بريداً آخر.',
                    ),
                  );
                }
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final editor = _buildEditor(users);
                    final history = _buildHistory();
                    if (constraints.maxWidth >= 790) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 365, child: editor),
                          const SizedBox(width: 16),
                          Expanded(child: history),
                        ],
                      );
                    }
                    return ListView(
                      children: [
                        editor,
                        const SizedBox(height: 14),
                        SizedBox(height: 430, child: history),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildEditor(List<AbuUserProfile> users) {
    final selected = _selectedUser(users);
    final selectedUserId = users.any((user) => user.uid == _targetUserId)
        ? _targetUserId
        : null;
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    final signedAmount = _deduct ? -amount.abs() : amount.abs();
    return Card(
      margin: EdgeInsets.zero,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              abuText(context, 'NEW CORRECTION', 'تصحيح جديد'),
              style: TextStyle(
                color: _productionPrimary(context),
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: ValueKey('$selectedUserId-${users.length}'),
              initialValue: selectedUserId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: abuText(context, 'Fan account', 'حساب المشجع'),
                prefixIcon: Icon(Icons.person_search_rounded),
              ),
              hint: Text(abuText(context, 'Select a user', 'اختر مستخدماً')),
              items: users
                  .map(
                    (user) => DropdownMenuItem<String>(
                      value: user.uid,
                      enabled: !user.suspended,
                      child: Text(
                        '${user.displayName.isEmpty ? user.username : user.displayName}'
                        '  ·  @${user.username}'
                        '${user.email.isEmpty ? '' : '  ·  ${user.email}'}'
                        '${user.suspended ? '  ·  ${abuText(context, 'SUSPENDED', 'موقوف')}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _submitting
                  ? null
                  : (value) => setState(() {
                      _targetUserId = value;
                      _error = null;
                    }),
            ),
            if (selected != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _line),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _PointBalanceLabel(
                        label: abuText(context, 'ALL TIME', 'الإجمالي'),
                        value: selected.totalPoints,
                      ),
                    ),
                    Expanded(
                      child: _PointBalanceLabel(
                        label: abuText(context, 'SEASON', 'الموسم'),
                        value: selected.seasonPoints,
                      ),
                    ),
                    Expanded(
                      child: _PointBalanceLabel(
                        label: abuText(context, 'MONTH', 'الشهر'),
                        value: selected.monthlyPoints,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment<bool>(
                  value: false,
                  icon: Icon(Icons.add_circle_outline_rounded),
                  label: Text(abuText(context, 'ADD', 'إضافة')),
                ),
                ButtonSegment<bool>(
                  value: true,
                  icon: Icon(Icons.remove_circle_outline_rounded),
                  label: Text(abuText(context, 'DEDUCT', 'خصم')),
                ),
              ],
              selected: {_deduct},
              onSelectionChanged: _submitting
                  ? null
                  : (value) => setState(() {
                      _deduct = value.first;
                      _error = null;
                    }),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _amount,
              enabled: !_submitting,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                labelText: abuText(context, 'Points', 'النقاط'),
                prefixIcon: Icon(
                  _deduct ? Icons.remove_rounded : Icons.add_rounded,
                  color: _deduct ? _red : _productionPrimary(context),
                ),
                helperText: abuText(
                  context,
                  '1–5,000 points per correction',
                  'من 1 إلى 5,000 نقطة لكل تصحيح',
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              enabled: !_submitting,
              minLines: 2,
              maxLines: 4,
              maxLength: 240,
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                labelText: abuText(
                  context,
                  'Reason (required)',
                  'السبب (مطلوب)',
                ),
                hintText: abuText(
                  context,
                  'Example: corrected event result',
                  'مثال: تصحيح نتيجة فعالية',
                ),
                alignLabelWithHint: true,
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _gold.withValues(alpha: .25)),
              ),
              child: Text(
                abuText(
                  context,
                  'All-time points can never fall below zero. Monthly and season counters stop at zero. Loyalty credit is not changed.',
                  'لا يمكن أن يقل إجمالي النقاط عن صفر. تتوقف نقاط الشهر والموسم عند صفر، ولا يتغير رصيد الولاء.',
                ),
                style: TextStyle(color: _muted, fontSize: 11, height: 1.4),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: _red, fontSize: 12)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _submitting || selected == null || selected.suspended
                  ? null
                  : () => _submit(selected),
              icon: _submitting
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_deduct ? Icons.remove_rounded : Icons.add_rounded),
              label: Text(
                _submitting
                    ? abuText(context, 'SAVING…', 'جارٍ الحفظ…')
                    : abuText(
                        context,
                        signedAmount == 0
                            ? 'REVIEW ADJUSTMENT'
                            : 'REVIEW ${_signedPoints(signedAmount)}',
                        signedAmount == 0
                            ? 'مراجعة التعديل'
                            : 'مراجعة ${_signedPoints(signedAmount)}',
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistory() => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      abuText(context, 'AUDIT HISTORY', 'سجل التدقيق'),
                      style: _display(18),
                    ),
                    Text(
                      abuText(
                        context,
                        'Permanent server-created receipts',
                        'إيصالات دائمة ينشئها الخادم',
                      ),
                      style: TextStyle(color: _muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Icon(Icons.lock_rounded, color: _gold, size: 19),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Expanded(
            child: StreamBuilder<List<AdminPointAdjustment>>(
              stream: widget.repository.watchAdminPointAdjustments(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ProductionEmpty(
                    icon: Icons.history_toggle_off_rounded,
                    title: abuText(
                      context,
                      'History could not be loaded',
                      'تعذر تحميل السجل',
                    ),
                    body: productionErrorMessage(snapshot.error!),
                  );
                }
                final adjustments =
                    snapshot.data ?? const <AdminPointAdjustment>[];
                if (adjustments.isEmpty) {
                  return _ProductionEmpty(
                    icon: Icons.receipt_long_outlined,
                    title: abuText(
                      context,
                      'No point corrections yet',
                      'لا توجد تصحيحات نقاط بعد',
                    ),
                    body: abuText(
                      context,
                      'Every completed correction will be recorded here.',
                      'سيتم تسجيل كل تصحيح مكتمل هنا.',
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: adjustments.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 9),
                  itemBuilder: (_, index) =>
                      _PointAdjustmentAuditTile(adjustment: adjustments[index]),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _submit(AbuUserProfile user) async {
    final magnitude = int.tryParse(_amount.text.trim());
    final reason = _reason.text.trim();
    if (magnitude == null || magnitude < 1 || magnitude > 5000) {
      setState(() {
        _error = abuText(
          context,
          'Enter an amount between 1 and 5,000.',
          'أدخل مبلغاً بين 1 و5,000.',
        );
      });
      return;
    }
    if (reason.length < 5 || reason.length > 240) {
      setState(() {
        _error = abuText(
          context,
          'Enter a clear reason between 5 and 240 characters.',
          'أدخل سبباً واضحاً بين 5 و240 حرفاً.',
        );
      });
      return;
    }
    final delta = _deduct ? -magnitude : magnitude;
    if (delta < 0 && magnitude > user.totalPoints) {
      setState(() {
        _error = abuText(
          context,
          'This deduction is greater than the current all-time balance.',
          'هذا الخصم أكبر من الرصيد الإجمالي الحالي.',
        );
      });
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          abuText(context, 'Confirm point correction', 'تأكيد تصحيح النقاط'),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${user.displayName} · @${user.username}',
                style: _display(19),
              ),
              const SizedBox(height: 10),
              Text(
                _signedPoints(delta),
                style: _display(34).copyWith(
                  color: delta < 0 ? _red : _productionPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(reason, style: TextStyle(color: _muted, height: 1.4)),
              const SizedBox(height: 14),
              Text(
                abuText(
                  context,
                  'This writes the user balance, leaderboard and permanent audit receipt together.',
                  'سيتم تحديث رصيد المستخدم ولوحة الصدارة وإيصال التدقيق الدائم معاً.',
                ),
                style: TextStyle(fontSize: 11, color: _gold),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(abuText(context, 'CANCEL', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(abuText(context, 'CONFIRM', 'تأكيد')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await widget.repository.adjustUserPoints(
        targetUserId: user.uid,
        delta: delta,
        reason: reason,
        idempotencyKey: _idempotencyKey,
      );
      if (!mounted) return;
      final feedback = result.duplicate
          ? abuText(
              context,
              'This correction was already saved. No duplicate points were applied.',
              'تم حفظ هذا التصحيح مسبقاً ولم تُطبق نقاط مكررة.',
            )
          : abuText(
              context,
              'Balance updated to ${result.totalPoints} points.',
              'تم تحديث الرصيد إلى ${result.totalPoints} نقطة.',
            );
      _amount.clear();
      _reason.clear();
      setState(() {
        _submitting = false;
        _idempotencyKey = widget.repository.newAdminPointAdjustmentKey();
      });
      _refreshUsers();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(feedback)));
    } catch (error) {
      if (!mounted) return;
      // Keep the same key after a transport failure so a retry can never
      // apply the same correction twice.
      setState(() {
        _submitting = false;
        _error = productionErrorMessage(error);
      });
    }
  }
}

class _PointBalanceLabel extends StatelessWidget {
  const _PointBalanceLabel({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value.toString(),
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: TextStyle(
          color: _muted,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: .5,
        ),
      ),
    ],
  );
}

class _PointAdjustmentAuditTile extends StatelessWidget {
  const _PointAdjustmentAuditTile({required this.adjustment});

  final AdminPointAdjustment adjustment;

  @override
  Widget build(BuildContext context) {
    final positive = adjustment.delta > 0;
    final color = positive ? _productionPrimary(context) : _red;
    final userLabel = adjustment.targetDisplayName.isNotEmpty
        ? adjustment.targetDisplayName
        : adjustment.targetUsername.isNotEmpty
        ? '@${adjustment.targetUsername}'
        : adjustment.targetUserId;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  positive ? Icons.add_rounded : Icons.remove_rounded,
                  color: color,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      _formatPointAuditTime(adjustment.createdAt),
                      style: TextStyle(color: _muted, fontSize: 10),
                    ),
                  ],
                ),
              ),
              Text(
                _signedPoints(adjustment.delta),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(adjustment.reason, style: TextStyle(fontSize: 12, height: 1.35)),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 6,
            children: [
              _PointAuditChip(
                label: abuText(context, 'ALL TIME', 'الإجمالي'),
                before: adjustment.totalBefore,
                after: adjustment.totalAfter,
              ),
              _PointAuditChip(
                label: abuText(context, 'SEASON', 'الموسم'),
                before: adjustment.seasonBefore,
                after: adjustment.seasonAfter,
              ),
              _PointAuditChip(
                label: abuText(context, 'MONTH', 'الشهر'),
                before: adjustment.monthlyBefore,
                after: adjustment.monthlyAfter,
              ),
              if (adjustment.periodFloorApplied)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    abuText(context, 'PERIOD FLOOR', 'حد الفترة'),
                    style: TextStyle(
                      color: _gold,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            abuText(
              context,
              'By ${adjustment.adminDisplayName.isEmpty ? adjustment.adminId : adjustment.adminDisplayName}',
              'بواسطة ${adjustment.adminDisplayName.isEmpty ? adjustment.adminId : adjustment.adminDisplayName}',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: _muted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _PointAuditChip extends StatelessWidget {
  const _PointAuditChip({
    required this.label,
    required this.before,
    required this.after,
  });

  final String label;
  final int before;
  final int after;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _line),
    ),
    child: Text(
      '$label  $before → $after',
      style: TextStyle(color: _muted, fontSize: 9),
    ),
  );
}

String _signedPoints(int value) => '${value > 0 ? '+' : ''}$value XP';

String _formatPointAuditTime(DateTime value) {
  if (value.millisecondsSinceEpoch == 0) return '—';
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
