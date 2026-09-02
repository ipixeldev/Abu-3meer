enum YouTubeMembershipCheckStatus {
  active,
  notInSnapshot,
  snapshotUnavailable,
  noYouTubeChannel,
}

/// Result of a one-time, server-verified YouTube membership check.
///
/// The Google access token used for the check is deliberately not represented
/// here: it is short-lived, sent directly to the API, and never persisted by
/// the app.
class YouTubeMembershipCheckResult {
  const YouTubeMembershipCheckResult({
    required this.status,
    required this.isYouTubeMember,
    required this.verifiedAt,
    this.youtubeChannelId,
    this.snapshotExpiresAt,
    this.membershipLevelId,
    this.memberSince,
  });

  final YouTubeMembershipCheckStatus status;
  final bool isYouTubeMember;
  final String? youtubeChannelId;
  final String? membershipLevelId;
  final DateTime? memberSince;
  final DateTime verifiedAt;
  final DateTime? snapshotExpiresAt;

  factory YouTubeMembershipCheckResult.fromJson(dynamic value) {
    if (value is! Map) {
      throw const FormatException('Invalid YouTube membership-check response.');
    }
    final map = Map<String, dynamic>.from(value);
    final status = switch (map['status']?.toString().trim()) {
      'active' => YouTubeMembershipCheckStatus.active,
      'not_in_snapshot' => YouTubeMembershipCheckStatus.notInSnapshot,
      'snapshot_unavailable' =>
        YouTubeMembershipCheckStatus.snapshotUnavailable,
      'no_youtube_channel' => YouTubeMembershipCheckStatus.noYouTubeChannel,
      _ => throw const FormatException(
        'Invalid YouTube membership-check status.',
      ),
    };
    final isMember = map['isMember'];
    final channelIdValue = map['youtubeChannelId'];
    final channelId = channelIdValue?.toString().trim();
    final verifiedAt = DateTime.tryParse(
      map['verifiedAt']?.toString().trim() ?? '',
    );
    final snapshotExpiresAtValue = map['snapshotExpiresAt'];
    final snapshotExpiresAt = snapshotExpiresAtValue == null
        ? null
        : DateTime.tryParse(snapshotExpiresAtValue.toString().trim());
    final statusMatchesFlag =
        (status == YouTubeMembershipCheckStatus.active && isMember == true) ||
        (status != YouTubeMembershipCheckStatus.active && isMember == false);
    final requiresChannel = status == YouTubeMembershipCheckStatus.active;
    final hasValidChannel =
        channelId != null &&
        RegExp(r'^UC[A-Za-z0-9_-]{22}$').hasMatch(channelId);
    if (isMember is! bool ||
        !statusMatchesFlag ||
        verifiedAt == null ||
        (requiresChannel && !hasValidChannel) ||
        (channelId != null && !hasValidChannel) ||
        (snapshotExpiresAtValue != null && snapshotExpiresAt == null) ||
        (status == YouTubeMembershipCheckStatus.active &&
            snapshotExpiresAt == null)) {
      throw const FormatException('Invalid YouTube membership-check response.');
    }

    final membershipLevel = map['membershipLevelId']?.toString().trim();
    final memberSinceValue = map['memberSince'];
    final memberSince = memberSinceValue == null
        ? null
        : DateTime.tryParse(memberSinceValue.toString().trim());
    if (memberSinceValue != null && memberSince == null) {
      throw const FormatException('Invalid YouTube membership-check response.');
    }

    return YouTubeMembershipCheckResult(
      status: status,
      isYouTubeMember: isMember,
      youtubeChannelId: channelId,
      membershipLevelId: membershipLevel == null || membershipLevel.isEmpty
          ? null
          : membershipLevel,
      memberSince: memberSince?.toLocal(),
      verifiedAt: verifiedAt.toLocal(),
      snapshotExpiresAt: snapshotExpiresAt?.toLocal(),
    );
  }
}

YouTubeMembershipCheckResult parseYouTubeMembershipCheckEnvelope(
  dynamic value,
) {
  if (value is! Map || value['membership'] is! Map) {
    throw const FormatException('Invalid YouTube membership-check response.');
  }
  return YouTubeMembershipCheckResult.fromJson(value['membership']);
}
