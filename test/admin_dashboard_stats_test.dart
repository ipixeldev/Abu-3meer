import 'package:abu_3meer/demo/fan_league_app.dart';
import 'package:abu_3meer/production/admin_dashboard_stats.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _stats = AdminDashboardStats(
  totalUsers: 240,
  activeUsers: 180,
  activeToday: 42,
  fans: 190,
  members: 37,
  moderators: 4,
  admins: 2,
  superAdmins: 1,
  suspendedUsers: 6,
  linkedYouTubeChannels: 90,
  activeMemberships: 35,
);

void main() {
  test('admin dashboard uses the registered version-relative endpoint', () {
    expect(adminDashboardStatsEndpoint, '/admin/dashboard/stats');
  });

  test('admin dashboard statistics parse canonical server response', () {
    final parsed = AdminDashboardStats.fromJson({
      'stats': {
        'totalUsers': '240',
        'activeUsers': 180,
        'activeToday': 42,
        'roleCounts': {
          'fan': 190,
          'member': 37,
          'moderator': 4,
          'admin': 2,
          'super_admin': 1,
        },
        'suspendedUsers': 6,
        'linkedYouTubeChannels': 90,
        'activeMemberships': 35,
        'generatedAt': '2026-09-02T09:30:00Z',
      },
    });

    expect(parsed.totalUsers, 240);
    expect(parsed.activeUsers, 180);
    expect(parsed.members, 37);
    expect(parsed.superAdmins, 1);
    expect(parsed.activeMemberships, 35);
    expect(parsed.generatedAt, isNotNull);
  });

  test('admin dashboard statistics accept flat snake-case aliases', () {
    final parsed = AdminDashboardStats.fromJson({
      'total_users': 12,
      'active_users': 8,
      'active_today': 3,
      'fans': 6,
      'members': 2,
      'moderators': 1,
      'admins': 1,
      'super_admins': 1,
      'suspended_users': 1,
      'linked_youtube_channels': 5,
      'active_memberships': 2,
    });

    expect(parsed.totalUsers, 12);
    expect(parsed.activeToday, 3);
    expect(parsed.superAdmins, 1);
    expect(parsed.linkedYouTubeChannels, 5);
  });

  testWidgets('admin dashboard renders server totals and can refresh', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminDashboardStatsPanel(
              loadStats: () async {
                calls += 1;
                return _stats;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin-dashboard-statistics')), findsOneWidget);
    expect(find.text('COMMUNITY STATISTICS'), findsOneWidget);
    expect(find.text('TOTAL USERS'), findsOneWidget);
    expect(find.text('240'), findsOneWidget);
    expect(find.text('ACTIVE USERS'), findsOneWidget);
    expect(find.text('180'), findsOneWidget);
    expect(find.text('ACTIVE MEMBERS'), findsOneWidget);
    expect(find.text('35'), findsOneWidget);
    expect(calls, 1);

    await tester.tap(
      find.byKey(const Key('refresh-admin-dashboard-statistics')),
    );
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
}
