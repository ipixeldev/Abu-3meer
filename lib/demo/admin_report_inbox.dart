part of 'fan_league_app.dart';

typedef AdminReportPageLoader = Future<AdminUserReportPage> Function({
  required String status,
  required int limit,
  required int offset,
});

typedef AdminReportResolver = Future<AdminUserReport> Function({
  required String reportId,
  required String status,
  required String resolutionNote,
});

/// Staff inbox for the user-reporting controls exposed on public profiles.
///
/// Loading and mutation callbacks are injectable so this safety-critical UI
/// can be exercised without Firebase or a live production server.
class AdminReportInbox extends StatefulWidget {
  const AdminReportInbox({
    super.key,
    required this.repository,
    this.loadPage,
    this.resolveReport,
  });

  final ProductionRepository repository;
  final AdminReportPageLoader? loadPage;
  final AdminReportResolver? resolveReport;

  @override
  State<AdminReportInbox> createState() => _AdminReportInboxState();
}

class _AdminReportInboxState extends State<AdminReportInbox> {
  static const _pageSize = 50;
  static const _statuses = <String>['open', 'resolved', 'dismissed', 'all'];

  late Future<AdminUserReportPage> _page;
  String _status = 'open';
  String? _busyReportId;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _page = _load();
  }

  Future<AdminUserReportPage> _load() {
    final loader = widget.loadPage;
    if (loader != null) {
      return loader(status: _status, limit: _pageSize, offset: _offset);
    }
    return widget.repository.fetchAdminUserReports(
      status: _status,
      limit: _pageSize,
      offset: _offset,
    );
  }

  Future<void> _refresh({bool resetOffset = false}) async {
    if (resetOffset) _offset = 0;
    final next = _load();
    setState(() => _page = next);
    await next;
  }

  void _selectStatus(String status) {
    if (status == _status) return;
    setState(() {
      _status = status;
      _offset = 0;
      _page = _load();
    });
  }

  String _statusLabel(BuildContext context, String value) => switch (value) {
    'resolved' => abuText(context, 'Resolved', 'تمت المعالجة'),
    'dismissed' => abuText(context, 'Dismissed', 'مرفوض'),
    'all' => abuText(context, 'All', 'الكل'),
    _ => abuText(context, 'Open', 'مفتوح'),
  };

  String _reasonLabel(BuildContext context, String value) => switch (value) {
    'inappropriate_content' => abuText(
      context,
      'Inappropriate content',
      'محتوى غير لائق',
    ),
    'harassment' => abuText(context, 'Harassment', 'مضايقة'),
    'hate_speech' => abuText(context, 'Hate speech', 'خطاب كراهية'),
    'impersonation' => abuText(context, 'Impersonation', 'انتحال شخصية'),
    'spam' => abuText(context, 'Spam', 'محتوى مزعج'),
    'other' => abuText(context, 'Other', 'أخرى'),
    _ => value.replaceAll('_', ' '),
  };

  String _timestamp(BuildContext context, DateTime value) {
    final local = value.toLocal();
    final date = MaterialLocalizations.of(context).formatMediumDate(local);
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(local));
    return '$date · $time';
  }

  Future<void> _recordDecision(AdminUserReport report, String decision) async {
    final note = await _askForResolutionNote(report, decision);
    if (note == null || !mounted) return;
    setState(() => _busyReportId = report.id);
    try {
      final resolver = widget.resolveReport;
      if (resolver != null) {
        await resolver(
          reportId: report.id,
          status: decision,
          resolutionNote: note,
        );
      } else {
        await widget.repository.resolveAdminUserReport(
          reportId: report.id,
          status: decision,
          resolutionNote: note,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            decision == 'resolved'
                ? abuText(
                    context,
                    'Report marked as resolved.',
                    'تمت معالجة البلاغ.',
                  )
                : abuText(
                    context,
                    'Report dismissed with an audit note.',
                    'تم رفض البلاغ مع تسجيل ملاحظة.',
                  ),
          ),
        ),
      );
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(productionErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _busyReportId = null);
    }
  }

  Future<String?> _askForResolutionNote(
    AdminUserReport report,
    String decision,
  ) {
    final formKey = GlobalKey<FormState>();
    var resolutionNote = '';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          decision == 'resolved'
              ? abuText(context, 'Resolve report', 'معالجة البلاغ')
              : abuText(context, 'Dismiss report', 'رفض البلاغ'),
        ),
        content: SizedBox(
          width: 480,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  abuText(
                    context,
                    '${report.reporter.label} reported ${report.target.label}.',
                    'أبلغ ${report.reporter.label} عن ${report.target.label}.',
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  autofocus: true,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 1000,
                  onChanged: (value) => resolutionNote = value,
                  decoration: InputDecoration(
                    labelText: abuText(
                      context,
                      'Resolution note (required)',
                      'ملاحظة القرار (مطلوبة)',
                    ),
                    hintText: abuText(
                      context,
                      'What was reviewed and what action was taken?',
                      'ما الذي تمت مراجعته وما الإجراء المتخذ؟',
                    ),
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? abuText(
                          context,
                          'Enter a note before saving this decision.',
                          'أدخل ملاحظة قبل حفظ القرار.',
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(abuText(context, 'CANCEL', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(dialogContext, resolutionNote.trim());
            },
            child: Text(
              decision == 'resolved'
                  ? abuText(context, 'RESOLVE', 'معالجة')
                  : abuText(context, 'DISMISS', 'رفض'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
    title: Row(
      children: [
        Icon(Icons.health_and_safety_rounded, color: _red),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            abuText(context, 'User report inbox', 'صندوق بلاغات المستخدمين'),
          ),
        ),
      ],
    ),
    content: SizedBox(
      width: 820,
      height: math.min(MediaQuery.sizeOf(context).height * .72, 680),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            abuText(
              context,
              'Review reports, record a decision, then use Roles & Admins if an account must be suspended.',
              'راجع البلاغ وسجّل القرار، ثم استخدم الأدوار والمشرفين إذا كان يجب إيقاف الحساب.',
            ),
            style: TextStyle(color: _muted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<String>(
                    segments: _statuses
                        .map(
                          (status) => ButtonSegment<String>(
                            value: status,
                            label: Text(_statusLabel(context, status)),
                          ),
                        )
                        .toList(growable: false),
                    selected: <String>{_status},
                    onSelectionChanged: (selection) =>
                        _selectStatus(selection.single),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: abuText(context, 'Refresh reports', 'تحديث البلاغات'),
                onPressed: _busyReportId == null ? () => _refresh() : null,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<AdminUserReportPage>(
              future: _page,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ProductionEmpty(
                    icon: Icons.cloud_off_rounded,
                    title: abuText(
                      context,
                      'Reports could not be loaded',
                      'تعذر تحميل البلاغات',
                    ),
                    body: productionErrorMessage(snapshot.error!),
                  );
                }
                final page = snapshot.data!;
                if (page.reports.isEmpty) {
                  return _ProductionEmpty(
                    icon: Icons.task_alt_rounded,
                    title: abuText(
                      context,
                      _status == 'open'
                          ? 'No open reports'
                          : 'No reports in this view',
                      _status == 'open'
                          ? 'لا توجد بلاغات مفتوحة'
                          : 'لا توجد بلاغات في هذا العرض',
                    ),
                    body: abuText(
                      context,
                      'New profile reports will appear here.',
                      'ستظهر بلاغات الملفات الشخصية الجديدة هنا.',
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      abuText(
                        context,
                        '${page.total} report${page.total == 1 ? '' : 's'}',
                        '${page.total} بلاغ',
                      ),
                      style: TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: page.reports.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) => _reportCard(
                            page.reports[index],
                            busy: _busyReportId == page.reports[index].id,
                          ),
                        ),
                      ),
                    ),
                    if (page.offset > 0 || page.hasMore) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: page.offset <= 0
                                ? null
                                : () {
                                    _offset = math.max(0, _offset - _pageSize);
                                    _refresh();
                                  },
                            icon: const Icon(Icons.chevron_left_rounded),
                            label: Text(abuText(context, 'PREVIOUS', 'السابق')),
                          ),
                          TextButton.icon(
                            onPressed: !page.hasMore
                                ? null
                                : () {
                                    _offset += _pageSize;
                                    _refresh();
                                  },
                            icon: const Icon(Icons.chevron_right_rounded),
                            label: Text(abuText(context, 'NEXT', 'التالي')),
                          ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      FilledButton(
        onPressed: _busyReportId == null ? () => Navigator.pop(context) : null,
        child: Text(abuText(context, 'DONE', 'تم')),
      ),
    ],
  );

  Widget _reportCard(AdminUserReport report, {required bool busy}) {
    final statusColor = switch (report.status) {
      'resolved' => _productionPrimary(context),
      'dismissed' => _muted,
      _ => _red,
    };
    final details = report.details?.trim() ?? '';
    final resolutionNote = report.resolutionNote?.trim() ?? '';
    return Container(
      key: ValueKey('admin-report-${report.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _AdminReportPerson(
                prefix: abuText(context, 'Reporter', 'المبلّغ'),
                user: report.reporter,
              ),
              Icon(Icons.arrow_forward_rounded, size: 18, color: _muted),
              _AdminReportPerson(
                prefix: abuText(context, 'Reported user', 'المُبلّغ عنه'),
                user: report.target,
              ),
              _ChallengeMetaChip(
                icon: report.isOpen
                    ? Icons.report_problem_rounded
                    : Icons.task_alt_rounded,
                label: _statusLabel(context, report.status),
                color: statusColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _reasonLabel(context, report.reason),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 5),
            SelectableText(details, style: TextStyle(color: _muted)),
          ],
          const SizedBox(height: 7),
          Text(
            _timestamp(context, report.createdAt),
            style: TextStyle(color: _muted, fontSize: 11),
          ),
          if (!report.isOpen) ...[
            const Divider(height: 22),
            Text(
              abuText(
                context,
                'Decision note: ${resolutionNote.isEmpty ? 'No note recorded' : resolutionNote}',
                'ملاحظة القرار: ${resolutionNote.isEmpty ? 'لا توجد ملاحظة' : resolutionNote}',
              ),
              style: TextStyle(color: _muted),
            ),
            if (report.resolvedBy case final resolver?)
              Text(
                abuText(
                  context,
                  'Handled by ${resolver.label}',
                  'تمت المعالجة بواسطة ${resolver.label}',
                ),
                style: TextStyle(color: _muted, fontSize: 11),
              ),
          ],
          if (report.isOpen) ...[
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => _recordDecision(report, 'dismissed'),
                  icon: const Icon(Icons.close_rounded),
                  label: Text(abuText(context, 'DISMISS', 'رفض')),
                ),
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => _recordDecision(report, 'resolved'),
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.task_alt_rounded),
                  label: Text(abuText(context, 'RESOLVE', 'معالجة')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AdminReportPerson extends StatelessWidget {
  const _AdminReportPerson({required this.prefix, required this.user});

  final String prefix;
  final ModerationUserSummary user;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = user.avatarUrl.trim();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 17,
          foregroundImage: avatarUrl.isEmpty ? null : NetworkImage(avatarUrl),
          child: avatarUrl.isEmpty
              ? Text(user.label.characters.first.toUpperCase())
              : null,
        ),
        const SizedBox(width: 7),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(prefix, style: TextStyle(color: _muted, fontSize: 10)),
            Text(
              user.label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (user.username.trim().isNotEmpty)
              Text(
                '@${user.username.trim()}',
                style: TextStyle(color: _muted, fontSize: 10),
              ),
          ],
        ),
      ],
    );
  }
}
