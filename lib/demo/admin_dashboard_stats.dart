part of 'fan_league_app.dart';

typedef AdminDashboardStatsLoader = Future<AdminDashboardStats> Function();

/// Compact, server-backed account statistics for the in-app Admin Studio.
class AdminDashboardStatsPanel extends StatefulWidget {
  const AdminDashboardStatsPanel({super.key, this.repository, this.loadStats})
    : assert(repository != null || loadStats != null);

  final ProductionRepository? repository;
  final AdminDashboardStatsLoader? loadStats;

  @override
  State<AdminDashboardStatsPanel> createState() =>
      _AdminDashboardStatsPanelState();
}

class _AdminDashboardStatsPanelState extends State<AdminDashboardStatsPanel> {
  late Future<AdminDashboardStats> _stats;

  @override
  void initState() {
    super.initState();
    _stats = _load();
  }

  Future<AdminDashboardStats> _load() =>
      widget.loadStats?.call() ?? widget.repository!.fetchAdminDashboardStats();

  void _refresh() => setState(() {
    _stats = _load();
  });

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('admin-dashboard-statistics'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _productionPrimary(context).withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.insights_rounded,
                  color: _productionPrimary(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      abuText(
                        context,
                        'COMMUNITY STATISTICS',
                        'إحصاءات المجتمع',
                      ),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .4,
                      ),
                    ),
                    Text(
                      abuText(
                        context,
                        'Server totals · active = last 30 days',
                        'إجماليات الخادم · النشطون خلال آخر 30 يوماً',
                      ),
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('refresh-admin-dashboard-statistics'),
                tooltip: abuText(
                  context,
                  'Refresh statistics',
                  'تحديث الإحصاءات',
                ),
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FutureBuilder<AdminDashboardStats>(
            future: _stats,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return _AdminStatsError(
                  message: productionErrorMessage(snapshot.error!),
                  onRetry: _refresh,
                );
              }
              final stats = snapshot.requireData;
              final primaryMetrics = <_AdminStatMetric>[
                _AdminStatMetric(
                  label: abuText(context, 'TOTAL USERS', 'إجمالي المستخدمين'),
                  value: stats.totalUsers,
                  icon: Icons.groups_2_rounded,
                  color: _productionPrimary(context),
                ),
                _AdminStatMetric(
                  label: abuText(context, 'ACTIVE 30D', 'نشطون 30 يوماً'),
                  value: stats.activeUsers,
                  icon: Icons.person_search_rounded,
                  color: _blue,
                ),
                _AdminStatMetric(
                  label: abuText(context, 'ACTIVE TODAY', 'نشطون اليوم'),
                  value: stats.activeToday,
                  icon: Icons.bolt_rounded,
                  color: _gold,
                ),
              ];
              final secondaryMetrics = <_AdminStatMetric>[
                _AdminStatMetric(
                  label: abuText(
                    context,
                    'VERIFIED MEMBERS',
                    'الأعضاء الموثقون',
                  ),
                  value: stats.activeMemberships,
                  icon: Icons.workspace_premium_rounded,
                  color: _gold,
                ),
                _AdminStatMetric(
                  label: abuText(context, 'FANS', 'المشجعون'),
                  value: stats.fans,
                  icon: Icons.sports_soccer_rounded,
                  color: _productionPrimary(context),
                ),
                _AdminStatMetric(
                  label: abuText(context, 'YOUTUBE LINKED', 'يوتيوب مرتبط'),
                  value: stats.linkedYouTubeChannels,
                  icon: Icons.link_rounded,
                  color: _red,
                ),
                _AdminStatMetric(
                  label: abuText(context, 'MODERATORS', 'المشرفون'),
                  value: stats.moderators,
                  icon: Icons.shield_rounded,
                  color: _blue,
                ),
                _AdminStatMetric(
                  label: abuText(context, 'ADMINS', 'المديرون'),
                  value: stats.admins + stats.superAdmins,
                  icon: Icons.admin_panel_settings_rounded,
                  color: _red,
                ),
                _AdminStatMetric(
                  label: abuText(context, 'SUSPENDED', 'الموقوفون'),
                  value: stats.suspendedUsers,
                  icon: Icons.block_rounded,
                  color: _red,
                ),
              ];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    key: const Key('admin-stats-primary-strip'),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _surface2,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: _line),
                    ),
                    child: Row(
                      children: [
                        for (
                          var index = 0;
                          index < primaryMetrics.length;
                          index++
                        ) ...[
                          if (index > 0)
                            Container(width: 1, height: 48, color: _line),
                          Expanded(
                            child: _AdminPrimaryStat(
                              metric: primaryMetrics[index],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        abuText(context, 'BREAKDOWN', 'التفاصيل'),
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .8,
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.swipe_rounded, size: 16, color: _muted),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    key: const Key('admin-stats-secondary-scroll'),
                    height: 82,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: secondaryMetrics.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 9),
                      itemBuilder: (context, index) => SizedBox(
                        width: 124,
                        child: _AdminStatMetricTile(
                          metric: secondaryMetrics[index],
                        ),
                      ),
                    ),
                  ),
                  if (stats.generatedAt != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      abuText(
                        context,
                        'Updated ${_productionDate(stats.generatedAt!)}',
                        'آخر تحديث ${_productionDate(stats.generatedAt!)}',
                      ),
                      textAlign: TextAlign.end,
                      style: const TextStyle(color: _muted, fontSize: 10),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}

class _AdminPrimaryStat extends StatelessWidget {
  const _AdminPrimaryStat({required this.metric});

  final _AdminStatMetric metric;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 5),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(metric.icon, size: 17, color: metric.color),
        const SizedBox(height: 5),
        Text(
          metric.value.toString(),
          style: TextStyle(
            color: metric.color,
            fontSize: 23,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          metric.label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _muted,
            fontSize: 9,
            height: 1.1,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _AdminStatMetric {
  const _AdminStatMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;
}

class _AdminStatMetricTile extends StatelessWidget {
  const _AdminStatMetricTile({required this.metric});

  final _AdminStatMetric metric;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
    decoration: BoxDecoration(
      color: _surface2,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _line),
    ),
    child: Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: metric.color.withValues(alpha: .11),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(metric.icon, size: 16, color: metric.color),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                metric.value.toString(),
                style: TextStyle(
                  color: metric.color,
                  fontSize: 20,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                metric.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 9,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AdminStatsError extends StatelessWidget {
  const _AdminStatsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _red.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _red.withValues(alpha: .3)),
    ),
    child: Row(
      children: [
        Icon(Icons.cloud_off_rounded, color: _red),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ),
        TextButton(
          onPressed: onRetry,
          child: Text(abuText(context, 'RETRY', 'إعادة المحاولة')),
        ),
      ],
    ),
  );
}
