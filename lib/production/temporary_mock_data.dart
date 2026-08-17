// TEMPORARY TEST SUPPORT.
// Remove this file and its three imports/references after the production data
// pipeline has been signed off. Real APIs remain the default at all times.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'external_content_service.dart';
import 'models.dart';

class TemporaryMockData extends ChangeNotifier {
  TemporaryMockData._();

  static final TemporaryMockData instance = TemporaryMockData._();
  static const _preferenceKey = 'temporary_mock_data_enabled';

  bool enabled = false;
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final preferences = await SharedPreferences.getInstance();
    enabled = preferences.getBool(_preferenceKey) ?? false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (enabled == value) return;
    enabled = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_preferenceKey, value);
  }

  MatchEvent get match {
    final kickoff = DateTime.now().add(const Duration(days: 2));
    return MatchEvent(
      id: 'mock_el_clasico',
      homeTeam: 'Barcelona',
      awayTeam: 'Real Madrid',
      competition: 'Temporary test event',
      kickoffAt: kickoff,
      predictionOpensAt: DateTime.now().subtract(const Duration(hours: 1)),
      predictionClosesAt: kickoff.subtract(const Duration(minutes: 30)),
      status: 'open',
      homeLogoUrl: 'assets/images/fcb.png',
      awayLogoUrl: 'assets/images/rma.png',
    );
  }

  LatestVideo get video => LatestVideo(
    id: 'u_pHQ5jAoWk',
    title: 'Temporary latest-video test card',
    url: 'https://www.youtube.com/watch?v=u_pHQ5jAoWk',
    thumbnailUrl: 'assets/images/latest_abu3meer.jpg',
    publishedAt: DateTime.now(),
  );
}
