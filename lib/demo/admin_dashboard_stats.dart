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
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _productionPrimary(context).withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
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
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .4,
                      ),
                    ),
                    Text(
                      abuText(
                        context,
                        'Live server totals · active users = last 30 days',
                        'إجماليات مباشرة من الخادم · النشطون خلال آخر 30 يوماً',
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
          const SizedBox(height: 16),
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
              final metrics = <_AdminStatMetric>[
                _AdminStatMetric(
                  label: abuText(context, 'TOTAL USERS', 'إجمالي المستخدمين'),
                  value: stats.totalUsers,
                  icon: Icons.groups_2_rounded,
                  color: _productionPrimary(context),
                ),
                _AdminStatMetric(
                  label: abuText(context, 'ACTIVE USERS', 'المستخدمون النشطون'),
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
                _AdminStatMetric(
                  label: abuText(context, 'ACTIVE MEMBERS', 'الأعضاء النشطون'),
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
                  label: abuText(context, 'MEMBER ROLE', 'دور العضو'),
                  value: stats.members,
                  icon: Icons.star_rounded,
                  color: _gold,
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
                  label: abuText(context, 'YOUTUBE LINKED', 'يوتيوب مرتبط'),
                  value: stats.linkedYouTubeChannels,
                  icon: Icons.link_rounded,
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
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 900
                          ? 5
                          : constraints.maxWidth >= 540
                          ? 3
                          : 2;
                      final gap = 10.0;
                      final width =
                          (constraints.maxWidth - gap * (columns - 1)) /
                          columns;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: metrics
                            .map(
                              (metric) => SizedBox(
                                width: width,
                                child: _AdminStatMetricTile(metric: metric),
                              ),
                            )
                            .toList(growable: false),
                      );
                    },
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
    height: 102,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _surface2,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(metric.icon, size: 18, color: metric.color),
        const Spacer(),
        Text(
          metric.value.toString(),
          style: TextStyle(
            color: metric.color,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          metric.label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _muted,
            fontSize: 9,
            fontWeight: FontWeight.w800,
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
