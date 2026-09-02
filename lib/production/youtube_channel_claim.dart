enum YouTubeChannelClaimStatus {
  pending,
  active,
  lapsed,
  rejected,
  revoked,
  superseded,
}

enum YouTubeChannelClaimDecision { approve, reject, revoke }

class YouTubeChannelClaim {
  const YouTubeChannelClaim({
    required this.id,
    required this.userId,
    required this.youtubeChannelId,
    required this.status,
    required this.submittedAt,
    this.reviewedAt,
    this.reviewedByUserId,
    this.reviewReason,
    this.displayName = '',
    this.username = '',
    this.email = '',
  });

  final String id;
  final String userId;
  final String youtubeChannelId;
  final YouTubeChannelClaimStatus status;
  final DateTime submittedAt;
  final DateTime? reviewedAt;
  final String? reviewedByUserId;
  final String? reviewReason;
  final String displayName;
  final String username;
  final String email;

  bool get isPending => status == YouTubeChannelClaimStatus.pending;
  bool get isActive => status == YouTubeChannelClaimStatus.active;

  factory YouTubeChannelClaim.fromJson(dynamic value) {
    if (value is! Map) {
      throw const FormatException('Invalid YouTube channel claim response.');
    }
    final map = Map<String, dynamic>.from(value);
    final rawStatus = map['status']?.toString().trim().toLowerCase();
    final status = switch (rawStatus) {
      'pending' => YouTubeChannelClaimStatus.pending,
      'active' => YouTubeChannelClaimStatus.active,
      'lapsed' => YouTubeChannelClaimStatus.lapsed,
      'rejected' => YouTubeChannelClaimStatus.rejected,
      'revoked' => YouTubeChannelClaimStatus.revoked,
      'superseded' => YouTubeChannelClaimStatus.superseded,
      _ => throw const FormatException('Invalid YouTube channel claim status.'),
    };
    final id = map['id']?.toString().trim() ?? '';
    final userId = map['userId']?.toString().trim() ?? '';
    final channelId = map['youtubeChannelId']?.toString().trim() ?? '';
    final submittedAt = DateTime.tryParse(map['submittedAt']?.toString() ?? '');
    if (id.isEmpty ||
        userId.isEmpty ||
        !RegExp(r'^UC[A-Za-z0-9_-]{22}$').hasMatch(channelId) ||
        submittedAt == null) {
      throw const FormatException('Invalid YouTube channel claim response.');
    }
    DateTime? optionalDate(dynamic item) =>
        item == null ? null : DateTime.tryParse(item.toString())?.toLocal();
    String optionalText(dynamic item) => item?.toString().trim() ?? '';
    return YouTubeChannelClaim(
      id: id,
      userId: userId,
      youtubeChannelId: channelId,
      status: status,
      submittedAt: submittedAt.toLocal(),
      reviewedAt: optionalDate(map['reviewedAt']),
      reviewedByUserId: optionalText(map['reviewedByUserId']).isEmpty
          ? null
          : optionalText(map['reviewedByUserId']),
      reviewReason: optionalText(map['reviewReason']).isEmpty
          ? null
          : optionalText(map['reviewReason']),
      displayName: optionalText(map['displayName']),
      username: optionalText(map['username']),
      email: optionalText(map['email']),
    );
  }
}

YouTubeChannelClaim? parseYouTubeChannelClaimEnvelope(dynamic value) {
  if (value is! Map || !value.containsKey('claim')) {
    throw const FormatException('Invalid YouTube channel claim response.');
  }
  return value['claim'] == null
      ? null
      : YouTubeChannelClaim.fromJson(value['claim']);
}
