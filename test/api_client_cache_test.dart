import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:abu_3meer/production/api_client.dart';

void main() {
  test(
    'public GETs coalesce in flight and reuse the short local cache',
    () async {
      var calls = 0;
      final release = Completer<void>();
      final transport = MockClient((request) async {
        calls += 1;
        await release.future;
        return http.Response(
          '[{"id":"shared"}]',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = AbuApiClient(
        baseUrl: 'https://api.example.test/api/v1',
        httpClient: transport,
      );

      final first = api.get('/football/matches/week');
      final second = api.get('/football/matches/week');
      await Future<void>.delayed(Duration.zero);

      expect(calls, 1);
      release.complete();
      expect(await first, await second);

      await api.get('/football/matches/week');
      expect(calls, 1, reason: 'the immediate replay must not hit the network');
    },
  );
}
