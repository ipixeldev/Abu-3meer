import 'production_repository.dart';

const String adminDashboardStatsEndpoint = '/admin/dashboard/stats';

/// Server-computed account totals shown to administrators.
///
/// The backend remains authoritative: the client never derives active-user or
/// role counts from a paginated user-directory response.
class AdminDashboardStats {
  const AdminDashboardStats({
    required this.totalUsers,
    required this.activeUsers,
    required this.activeToday,
    required this.fans,
    required this.members,
    required this.moderators,
    required this.admins,
    required this.superAdmins,
    required this.suspendedUsers,
    required this.linkedYouTubeChannels,
    required this.activeMemberships,
    this.generatedAt,
  });

  final int totalUsers;
  final int activeUsers;
  final int activeToday;
  final int fans;
  final int members;
  final int moderators;
  final int admins;
  final int superAdmins;
  final int suspendedUsers;
  final int linkedYouTubeChannels;
  final int activeMemberships;
  final DateTime? generatedAt;

  factory AdminDashboardStats.fromJson(dynamic value) {
    if (value is! Map) {
      throw const FormatException('Invalid admin dashboard statistics.');
    }
    final envelope = Map<String, dynamic>.from(value);
    final rawStats = envelope['stats'] ?? envelope['data'] ?? envelope;
    if (rawStats is! Map) {
      throw const FormatException('Invalid admin dashboard statistics.');
    }
    final stats = Map<String, dynamic>.from(rawStats);
    final rawRoles = stats['roleCounts'] ?? stats['roles'];
    final roles = rawRoles is Map
        ? Map<String, dynamic>.from(rawRoles)
        : const <String, dynamic>{};
    final rawMembership = stats['membership'] ?? stats['memberships'];
    final membership = rawMembership is Map
        ? Map<String, dynamic>.from(rawMembership)
        : const <String, dynamic>{};

    int integer(List<dynamic> candidates) {
      for (final candidate in candidates) {
        if (candidate is int) return candidate;
        if (candidate is num) return candidate.toInt();
        final parsed = int.tryParse(candidate?.toString() ?? '');
        if (parsed != null) return parsed;
      }
      return 0;
    }

    DateTime? date(dynamic item) =>
        item == null ? null : DateTime.tryParse(item.toString())?.toLocal();

    return AdminDashboardStats(
      totalUsers: integer([stats['totalUsers'], stats['total_users']]),
      activeUsers: integer([
        stats['activeUsers'],
        stats['active_users'],
        stats['activeUsers30d'],
      ]),
      activeToday: integer([
        stats['activeToday'],
        stats['activeUsersToday'],
        stats['active_today'],
      ]),
      fans: integer([stats['fans'], roles['fan'], roles['fans']]),
      members: integer([stats['members'], roles['member'], roles['members']]),
      moderators: integer([
        stats['moderators'],
        roles['moderator'],
        roles['moderators'],
      ]),
      admins: integer([stats['admins'], roles['admin'], roles['admins']]),
      superAdmins: integer([
        stats['superAdmins'],
        stats['super_admins'],
        roles['superAdmin'],
        roles['super_admin'],
      ]),
      suspendedUsers: integer([
        stats['suspendedUsers'],
        stats['suspended_users'],
      ]),
      linkedYouTubeChannels: integer([
        stats['linkedYouTubeChannels'],
        stats['linked_youtube_channels'],
        membership['linkedChannels'],
      ]),
      activeMemberships: integer([
        stats['activeMemberships'],
        stats['active_memberships'],
        membership['active'],
      ]),
      generatedAt: date(stats['generatedAt'] ?? stats['generated_at']),
    );
  }
}

extension AdminDashboardStatsRepository on ProductionRepository {
  Future<AdminDashboardStats> fetchAdminDashboardStats() async {
    final response = await apiRepo.api.get(
      adminDashboardStatsEndpoint,
      requireAuth: true,
      bypassCache: true,
    );
    return AdminDashboardStats.fromJson(response);
  }
}
