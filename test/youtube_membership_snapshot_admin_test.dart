import 'dart:typed_data';

import 'package:abu_3meer/demo/fan_league_app.dart';
import 'package:abu_3meer/production/youtube_membership_snapshot.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

YouTubeMembershipSnapshotStatus snapshotStatus({
  YouTubeMembershipSnapshotState state =
      YouTubeMembershipSnapshotState.notImported,
  int members = 0,
  int matched = 0,
}) => YouTubeMembershipSnapshotStatus(
  state: state,
  importId: state == YouTubeMembershipSnapshotState.notImported
      ? null
      : '94f5ff5f-e5c7-4540-a557-609641631008',
  sourceFilename: state == YouTubeMembershipSnapshotState.notImported
      ? null
      : 'members.csv',
  sourceFormat: state == YouTubeMembershipSnapshotState.notImported
      ? null
      : 'csv',
  sourceSha256: state == YouTubeMembershipSnapshotState.notImported
      ? null
      : List.filled(64, 'a').join(),
  memberCount: members,
  matchedUserCount: matched,
  activatedAt: state == YouTubeMembershipSnapshotState.notImported
      ? null
      : DateTime(2026, 9, 1, 12),
  expiresAt: state == YouTubeMembershipSnapshotState.notImported
      ? null
      : DateTime(2026, 9, 8, 12),
  maxAgeHours: 168,
);

void main() {
  test('snapshot API model parses numeric strings and active status', () {
    final parsed = YouTubeMembershipSnapshotStatus.fromJson({
      'status': 'active',
      'importId': 'import-1',
      'sourceFilename': 'members.csv',
      'sourceFormat': 'csv',
      'sourceSha256': List.filled(64, 'a').join(),
      'memberCount': '12',
      'matchedUserCount': 4,
      'activatedAt': '2026-09-01T12:00:00Z',
      'expiresAt': '2026-09-08T12:00:00Z',
      'maxAgeHours': '168',
    });

    expect(parsed.isActive, isTrue);
    expect(parsed.memberCount, 12);
    expect(parsed.matchedUserCount, 4);
    expect(parsed.maxAgeHours, 168);
  });

  testWidgets('admin confirms and imports a CSV membership snapshot', (
    tester,
  ) async {
    Uint8List? uploadedBytes;
    String? uploadedName;
    var pickerCalled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminYouTubeMembershipSnapshotCard(
            loadStatus: () async => snapshotStatus(),
            pickFile: () async {
              pickerCalled = true;
              return XFile.fromData(
                Uint8List.fromList([1, 2, 3]),
                path: 'members.csv',
                mimeType: 'text/csv',
              );
            },
            importSnapshot: (bytes, fileName) async {
              uploadedBytes = bytes;
              uploadedName = fileName;
              return snapshotStatus(
                state: YouTubeMembershipSnapshotState.active,
                members: 25,
                matched: 7,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('IMPORT CSV'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'IMPORT CSV'));
    await tester.pumpAndSettle();
    expect(pickerCalled, isTrue);
    expect(find.text('Replace membership snapshot?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'IMPORT'));
    await tester.pumpAndSettle();

    expect(uploadedBytes, orderedEquals([1, 2, 3]));
    expect(uploadedName, 'members.csv');
    expect(find.textContaining('25 members'), findsWidgets);
    expect(find.text('REPLACE'), findsOneWidget);
  });
}
