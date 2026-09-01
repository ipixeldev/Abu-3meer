import 'dart:typed_data';

import 'production_repository.dart';

enum YouTubeMembershipSnapshotState { active, expired, notImported }

class YouTubeMembershipSnapshotStatus {
  const YouTubeMembershipSnapshotStatus({
    required this.state,
    required this.importId,
    required this.sourceFilename,
    required this.sourceFormat,
    required this.sourceSha256,
    required this.memberCount,
    required this.matchedUserCount,
    required this.activatedAt,
    required this.expiresAt,
    required this.maxAgeHours,
  });

  final YouTubeMembershipSnapshotState state;
  final String? importId;
  final String? sourceFilename;
  final String? sourceFormat;
  final String? sourceSha256;
  final int memberCount;
  final int matchedUserCount;
  final DateTime? activatedAt;
  final DateTime? expiresAt;
  final int maxAgeHours;

  bool get isActive => state == YouTubeMembershipSnapshotState.active;

  factory YouTubeMembershipSnapshotStatus.fromJson(dynamic value) {
    if (value is! Map) {
      throw const FormatException('Invalid membership snapshot response.');
    }
    final map = Map<String, dynamic>.from(value);
    final rawState = map['status']?.toString();
    final state = switch (rawState) {
      'active' => YouTubeMembershipSnapshotState.active,
      'expired' => YouTubeMembershipSnapshotState.expired,
      _ => YouTubeMembershipSnapshotState.notImported,
    };
    int integer(dynamic item) => switch (item) {
      int number => number,
      num number => number.toInt(),
      _ => int.tryParse(item?.toString() ?? '') ?? 0,
    };
    DateTime? date(dynamic item) =>
        item == null ? null : DateTime.tryParse(item.toString())?.toLocal();
    String? optionalString(dynamic item) {
      final text = item?.toString().trim() ?? '';
      return text.isEmpty ? null : text;
    }

    return YouTubeMembershipSnapshotStatus(
      state: state,
      importId: optionalString(map['importId']),
      sourceFilename: optionalString(map['sourceFilename']),
      sourceFormat: optionalString(map['sourceFormat']),
      sourceSha256: optionalString(map['sourceSha256']),
      memberCount: integer(map['memberCount']),
      matchedUserCount: integer(map['matchedUserCount']),
      activatedAt: date(map['activatedAt']),
      expiresAt: date(map['expiresAt']),
      maxAgeHours: integer(map['maxAgeHours']),
    );
  }
}

extension YouTubeMembershipSnapshotRepository on ProductionRepository {
  Future<YouTubeMembershipSnapshotStatus>
  fetchYouTubeMembershipSnapshotStatus() async {
    final response = await apiRepo.api.get(
      '/admin/youtube/membership/snapshot',
      requireAuth: true,
      bypassCache: true,
    );
    return YouTubeMembershipSnapshotStatus.fromJson(response);
  }

  Future<YouTubeMembershipSnapshotStatus> importYouTubeMembershipSnapshot({
    required Uint8List bytes,
    required String fileName,
    bool confirmLargeDecrease = false,
  }) async {
    final response = await apiRepo.api.postMultipart(
      '/admin/youtube/membership/snapshot${confirmLargeDecrease ? '?confirmLargeDecrease=true' : ''}',
      bytes: bytes,
      fileName: fileName,
      requireAuth: true,
    );
    return YouTubeMembershipSnapshotStatus.fromJson(response);
  }
}
