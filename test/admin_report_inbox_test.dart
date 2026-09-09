import 'package:abu_3meer/demo/fan_league_app.dart';
import 'package:abu_3meer/production/api_client.dart';
import 'package:abu_3meer/production/api_production_repository.dart';
import 'package:abu_3meer/production/models.dart';
import 'package:abu_3meer/production/production_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth extends Fake implements FirebaseAuth {}

class _ReportApiClient extends AbuApiClient {
  String? method;
  String? path;
  Map<String, String>? query;
  dynamic body;
  bool? requireAuth;
  bool? bypassCache;
  dynamic response;

  @override
  Future<dynamic> get(
    String path, {
    Map<String, String>? queryParams,
    bool requireAuth = false,
    bool bypassCache = false,
  }) async {
    method = 'GET';
    this.path = path;
    query = queryParams;
    this.requireAuth = requireAuth;
    this.bypassCache = bypassCache;
    return response;
  }

  @override
  Future<dynamic> post(
    String path, {
    dynamic body,
    bool requireAuth = true,
  }) async {
    method = 'POST';
    this.path = path;
    this.body = body;
    this.requireAuth = requireAuth;
    return response;
  }
}

class _RepositoryFake extends Fake implements ProductionRepository {}

Map<String, dynamic> _reportJson({
  String status = 'open',
  String? resolutionNote,
}) => <String, dynamic>{
  'id': '33333333-3333-4333-8333-333333333333',
  'reporterUserId': '11111111-1111-4111-8111-111111111111',
  'reportedUserId': '22222222-2222-4222-8222-222222222222',
  'reporter': <String, dynamic>{
    'publicId': 'reporter_7',
    'username': 'reporter_7',
    'displayName': 'Reporter Seven',
    'avatarUrl': null,
  },
  'target': <String, dynamic>{
    'publicId': 'target_8',
    'username': 'target_8',
    'displayName': 'Target Eight',
    'avatarUrl': null,
  },
  'reason': 'harassment',
  'details': 'Repeated unwanted messages.',
  'status': status,
  'createdAt': '2026-09-09T08:30:00.000Z',
  'updatedAt': '2026-09-09T08:31:00.000Z',
  'resolvedAt': status == 'open' ? null : '2026-09-09T08:35:00.000Z',
  'resolvedBy': status == 'open'
      ? null
      : <String, dynamic>{
          'publicId': 'moderator',
          'username': 'moderator',
          'displayName': 'Moderator',
          'avatarUrl': null,
        },
  'resolutionNote': resolutionNote,
};

void main() {
  test('admin report parser preserves moderation evidence and identities', () {
    final report = parseAdminUserReport(_reportJson());

    expect(report.id, '33333333-3333-4333-8333-333333333333');
    expect(report.reporter.label, 'Reporter Seven');
    expect(report.target.username, 'target_8');
    expect(report.reason, 'harassment');
    expect(report.details, 'Repeated unwanted messages.');
    expect(report.isOpen, isTrue);
    expect(report.createdAt.toUtc(), DateTime.utc(2026, 9, 9, 8, 30));
  });

  group('admin report API', () {
    late _ReportApiClient client;
    late ApiProductionRepository repository;

    setUp(() {
      client = _ReportApiClient();
      repository = ApiProductionRepository(apiClient: client, auth: _Auth());
    });

    test('loads the authenticated status-filtered report queue', () async {
      client.response = <String, dynamic>{
        'reports': <dynamic>[_reportJson()],
        'total': 1,
        'limit': 50,
        'offset': 0,
        'hasMore': false,
      };

      final page = await repository.fetchAdminUserReports();

      expect(client.method, 'GET');
      expect(client.path, '/admin/reports');
      expect(client.query, <String, String>{
        'status': 'open',
        'limit': '50',
        'offset': '0',
      });
      expect(client.requireAuth, isTrue);
      expect(client.bypassCache, isTrue);
      expect(page.reports.single.target.displayName, 'Target Eight');
    });

    test('resolves a report with the required audit note', () async {
      client.response = <String, dynamic>{
        'success': true,
        'report': _reportJson(
          status: 'resolved',
          resolutionNote: 'Reviewed and warned the account.',
        ),
      };

      final report = await repository.resolveAdminUserReport(
        reportId: '33333333-3333-4333-8333-333333333333',
        status: 'resolved',
        resolutionNote: ' Reviewed and warned the account. ',
      );

      expect(client.method, 'POST');
      expect(
        client.path,
        '/admin/reports/33333333-3333-4333-8333-333333333333/resolve',
      );
      expect(client.requireAuth, isTrue);
      expect(client.body, <String, dynamic>{
        'status': 'resolved',
        'resolutionNote': 'Reviewed and warned the account.',
      });
      expect(report.status, 'resolved');
      expect(report.resolvedBy?.label, 'Moderator');
    });

    test('rejects an empty resolution note before network mutation', () async {
      await expectLater(
        repository.resolveAdminUserReport(
          reportId: '33333333-3333-4333-8333-333333333333',
          status: 'dismissed',
          resolutionNote: '  ',
        ),
        throwsArgumentError,
      );
      expect(client.method, isNull);
    });
  });

  testWidgets('inbox shows evidence and records a resolution note', (
    tester,
  ) async {
    final report = parseAdminUserReport(_reportJson());
    String? savedStatus;
    String? savedNote;

    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: const <Locale>[Locale('en'), Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: AdminReportInbox(
            repository: _RepositoryFake(),
            loadPage:
                ({required status, required limit, required offset}) async =>
                    AdminUserReportPage(
                      reports: <AdminUserReport>[report],
                      total: 1,
                      limit: limit,
                      offset: offset,
                      hasMore: false,
                    ),
            resolveReport:
                ({
                  required reportId,
                  required status,
                  required resolutionNote,
                }) async {
                  savedStatus = status;
                  savedNote = resolutionNote;
                  return parseAdminUserReport(
                    _reportJson(status: status, resolutionNote: resolutionNote),
                  );
                },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('User report inbox'), findsOneWidget);
    expect(find.text('Reporter Seven'), findsOneWidget);
    expect(find.text('Target Eight'), findsOneWidget);
    expect(find.text('Repeated unwanted messages.'), findsOneWidget);

    await tester.tap(find.text('RESOLVE').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField),
      'Profile reviewed and warning issued.',
    );
    await tester.tap(find.text('RESOLVE').last);
    await tester.pumpAndSettle();

    expect(savedStatus, 'resolved');
    expect(savedNote, 'Profile reviewed and warning issued.');
  });
}
