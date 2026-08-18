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

  AbuUserProfile profile(AbuUserProfile source) => source.copyWith(
    totalPoints: 8420,
    monthlyPoints: 1840,
    seasonPoints: 8420,
  );

  List<MatchEvent> get matches {
    final kickoff = DateTime.now().add(const Duration(days: 2));
    return [
      MatchEvent(
        id: 'mock_el_clasico',
        homeTeam: 'Barcelona',
        awayTeam: 'Real Madrid',
        competition: 'La Liga · Matchday 3',
        kickoffAt: kickoff,
        predictionOpensAt: DateTime.now().subtract(const Duration(hours: 1)),
        predictionClosesAt: kickoff.subtract(const Duration(minutes: 30)),
        status: 'open',
        homeLogoUrl: 'assets/images/fcb.png',
        awayLogoUrl: 'assets/images/rma.png',
        firstScorerOptions: const [
          'Lamine Yamal',
          'Robert Lewandowski',
          'Raphinha',
          'Kylian Mbappé',
          'Vinícius Júnior',
          'Jude Bellingham',
          'No scorer',
        ],
      ),
      MatchEvent(
        id: 'mock_previous_match',
        homeTeam: 'Real Madrid',
        awayTeam: 'Barcelona',
        competition: 'Spanish Super Cup · Final',
        kickoffAt: DateTime.now().subtract(const Duration(days: 12)),
        predictionOpensAt: DateTime.now().subtract(const Duration(days: 15)),
        predictionClosesAt: DateTime.now().subtract(const Duration(days: 12)),
        status: 'completed',
        homeLogoUrl: 'assets/images/rma.png',
        awayLogoUrl: 'assets/images/fcb.png',
        homeScore: 2,
        awayScore: 3,
        firstScorerOptions: const [
          'Kylian Mbappé',
          'Vinícius Júnior',
          'Lamine Yamal',
          'Robert Lewandowski',
          'No scorer',
        ],
        firstScorer: 'Kylian Mbappé',
      ),
    ];
  }

  MatchEvent get match => matches.first;

  LatestVideo get video => LatestVideo(
    id: 'u_pHQ5jAoWk',
    title: 'Temporary latest-video test card',
    url: 'https://www.youtube.com/watch?v=u_pHQ5jAoWk',
    thumbnailUrl: 'assets/images/latest_abu3meer.jpg',
    publishedAt: DateTime.now(),
  );

  List<AbuChallenge> get challenges {
    final now = DateTime.now();
    return [
      AbuChallenge(
        id: 'mock_secret_phrase',
        kind: 'videoQuestion',
        title: 'Spot the secret phrase',
        description:
            'Watch the latest Abu 3meer episode and submit the hidden phrase.',
        rewardPoints: 40,
        status: 'open',
        videoUrl: video.url,
        availableFrom: now.subtract(const Duration(hours: 3)),
        availableUntil: now.add(const Duration(days: 3)),
      ),
      AbuChallenge(
        id: 'mock_player_card',
        kind: 'playerCard',
        title: 'Find today\'s Player Card',
        description: 'Which Player Card appeared in today\'s video?',
        rewardPoints: 20,
        status: 'open',
        videoUrl: video.url,
        availableFrom: now.subtract(const Duration(hours: 2)),
        availableUntil: now.add(const Duration(days: 2)),
      ),
      AbuChallenge(
        id: 'mock_quiz',
        kind: 'videoQuestion',
        title: 'El Clasico IQ',
        description: 'A ten-question football knowledge challenge.',
        rewardPoints: 400,
        status: 'open',
        videoUrl: '',
        availableFrom: now.subtract(const Duration(days: 1)),
        availableUntil: now.add(const Duration(days: 6)),
      ),
    ];
  }

  List<LeaderboardEntry> leaderboard(String uid) => [
    const LeaderboardEntry(
      uid: 'mock_1',
      username: 'NoraGOAT',
      avatarUrl: '',
      supportedTeam: 'Real Madrid',
      monthlyPoints: 2940,
      seasonPoints: 12940,
      isMember: true,
    ),
    const LeaderboardEntry(
      uid: 'mock_2',
      username: 'CuleKing',
      avatarUrl: '',
      supportedTeam: 'Barcelona',
      monthlyPoints: 2610,
      seasonPoints: 12610,
      isMember: false,
    ),
    const LeaderboardEntry(
      uid: 'mock_3',
      username: 'Yousef10',
      avatarUrl: '',
      supportedTeam: 'Barcelona',
      monthlyPoints: 2184,
      seasonPoints: 11884,
      isMember: true,
    ),
    const LeaderboardEntry(
      uid: 'mock_4',
      username: 'Madridista',
      avatarUrl: '',
      supportedTeam: 'Real Madrid',
      monthlyPoints: 1970,
      seasonPoints: 11720,
      isMember: false,
    ),
    LeaderboardEntry(
      uid: uid,
      username: 'dev',
      avatarUrl: '',
      supportedTeam: 'Barcelona',
      monthlyPoints: 1840,
      seasonPoints: 8420,
      isMember: false,
    ),
    const LeaderboardEntry(
      uid: 'mock_6',
      username: 'LeoFan',
      avatarUrl: '',
      supportedTeam: 'Barcelona',
      monthlyPoints: 1660,
      seasonPoints: 8260,
      isMember: false,
    ),
  ];

  List<PointLedgerEntry> get pointHistory {
    final now = DateTime.now();
    return [
      PointLedgerEntry(
        id: 'mock_tx_1',
        sourceType: 'prediction',
        sourceId: 'mock_previous_match',
        basePoints: 100,
        multiplier: 1,
        finalPoints: 100,
        reason: 'Exact score · Real Madrid vs Barcelona',
        createdAt: now.subtract(const Duration(days: 12)),
      ),
      PointLedgerEntry(
        id: 'mock_tx_2',
        sourceType: 'videoQuestion',
        sourceId: 'mock_video_1',
        basePoints: 40,
        multiplier: 2,
        finalPoints: 80,
        reason: 'Latest video question · Member bonus',
        createdAt: now.subtract(const Duration(days: 4)),
      ),
      PointLedgerEntry(
        id: 'mock_tx_3',
        sourceType: 'playerCard',
        sourceId: 'mock_card_1',
        basePoints: 20,
        multiplier: 1,
        finalPoints: 20,
        reason: 'Player Card discovered · Lamine Yamal',
        createdAt: now.subtract(const Duration(days: 2)),
      ),
    ];
  }

  List<AbuPost> get posts {
    final now = DateTime.now();
    return [
      AbuPost(
        id: 'mock_post_1',
        title: 'El Clasico prediction room is open',
        body: 'Lock your exact score before kickoff and join the Barcelona vs Real Madrid Fan War.',
        imageUrl: '',
        linkUrl: '',
        authorName: 'Abu 3meer',
        publishedAt: now.subtract(const Duration(hours: 2)),
      ),
      AbuPost(
        id: 'mock_post_2',
        title: 'New Player Card hidden in today\'s video',
        body: 'Watch carefully, identify the card, and claim the 20 point discovery reward.',
        imageUrl: 'assets/images/lamine_yamal_2025.jpg',
        linkUrl: video.url,
        authorName: 'Abu 3meer',
        publishedAt: now.subtract(const Duration(days: 1)),
      ),
    ];
  }
}
