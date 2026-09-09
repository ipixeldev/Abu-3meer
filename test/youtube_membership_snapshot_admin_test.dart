import 'dart:io';
import 'dart:typed_data';

import 'package:abu_3meer/demo/fan_league_app.dart';
import 'package:abu_3meer/production/api_client.dart';
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

    expect(find.text('IMPORT CSV / TSV'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'IMPORT CSV / TSV'));
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

  testWidgets('snapshot card and confirmation stay usable on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminYouTubeMembershipSnapshotCard(
            loadStatus: () async => snapshotStatus(),
            pickFile: () async => XFile.fromData(
              Uint8List.fromList([1, 2, 3]),
              path: 'members.csv',
              mimeType: 'text/csv',
            ),
            importSnapshot: (_, _) async => snapshotStatus(
              state: YouTubeMembershipSnapshotState.active,
              members: 25,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.byKey(const Key('membership-snapshot-upload-button'));
    final summary = find.byKey(const Key('membership-snapshot-summary'));
    expect(tester.getSize(button).width, greaterThan(270));
    expect(tester.getSize(summary).width, greaterThan(270));
    expect(tester.takeException(), isNull);

    await tester.tap(button);
    await tester.pumpAndSettle();

    final dialog = find.byKey(
      const Key('membership-snapshot-confirmation-dialog'),
    );
    expect(dialog, findsOneWidget);
    final dialogRect = tester.getRect(dialog);
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(320));
    expect(dialogRect.top, greaterThanOrEqualTo(0));
    expect(dialogRect.bottom, lessThanOrEqualTo(640));
    expect(
      tester.getSize(find.widgetWithText(FilledButton, 'IMPORT')).width,
      greaterThan(230),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('large membership decrease requires a second confirmation', (
    tester,
  ) async {
    var uploadAttempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminYouTubeMembershipSnapshotCard(
            loadStatus: () async => snapshotStatus(
              state: YouTubeMembershipSnapshotState.active,
              members: 100,
            ),
            pickFile: () async => XFile.fromData(
              Uint8List.fromList([1, 2, 3]),
              path: 'members.csv',
              mimeType: 'text/csv',
            ),
            importSnapshot: (bytes, fileName) async {
              uploadAttempts += 1;
              if (uploadAttempts == 1) {
                throw AbuApiException(
                  statusCode: 409,
                  message: 'The new export has 10 members while the current snapshot has 100.',
                  details: '{"error":"youtube_snapshot_large_decrease_confirmation_required"}',
                );
              }
              return snapshotStatus(
                state: YouTubeMembershipSnapshotState.active,
                members: 10,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'REPLACE'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'IMPORT'));
    // The upload spinner intentionally keeps animating while the destructive
    // confirmation is open, so advance the dialog transition directly.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Large membership decrease'), findsOneWidget);
    expect(uploadAttempts, 1);
    await tester.tap(
      find.widgetWithText(FilledButton, 'CONFIRM COMPLETE EXPORT'),
    );
    await tester.pumpAndSettle();

    expect(uploadAttempts, 2);
    expect(find.textContaining('10 members'), findsWidgets);
  });

  test(
    'admin mobile layout reserves nav paint and uses equal action columns',
    () {
      final source = File('lib/demo/production_ui.dart').readAsStringSync();
      final features = File('lib/demo/production_features.dart')
          .readAsStringSync();
      expect(source, contains("Key('primary-nav-paint-clearance')"));
      expect(source, contains('EdgeInsets.only(top: 28)'));
      expect(source, contains("Key('admin-primary-action-grid')"));
      expect(source, contains('minWidth: 230'));
      expect(features, contains("Key('admin-membership-snapshot-dialog')"));
      expect(features, contains("Key('admin-membership-user-list')"));
      expect(features, contains('EdgeInsets.only(bottom: 24)'));
    },
  );
}
