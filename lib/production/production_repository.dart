import 'point_rules.dart';

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';

import 'api_production_repository.dart';
import 'api_client.dart';
import 'external_content_service.dart';
import 'models.dart';

@visibleForTesting
String footballTeamKeyForMatching(String value) {
  var normalized = value.trim().toLowerCase();
  const replacements = <String, String>{
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'ã': 'a',
    'å': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'ö': 'o',
    'õ': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ñ': 'n',
    'ç': 'c',
  };
  for (final entry in replacements.entries) {
    normalized = normalized.replaceAll(entry.key, entry.value);
  }
  return normalized.replaceAll(RegExp(r'\s+'), ' ');
}

@visibleForTesting
bool sameFootballMatchForMatching(MatchEvent left, MatchEvent right) {
  if (left.id == right.id) return true;
  final sameHome =
      footballTeamKeyForMatching(left.homeTeam) ==
      footballTeamKeyForMatching(right.homeTeam);
  final sameAway =
      footballTeamKeyForMatching(left.awayTeam) ==
      footballTeamKeyForMatching(right.awayTeam);
  if (sameHome && sameAway) return true;

  // Provider and manually managed names can include suffixes or diacritics.
  // A matching side plus the same kickoff identifies the same real fixture
  // without collapsing unrelated matches between those clubs.
  final kickoffDifference = left.kickoffAt.difference(right.kickoffAt).abs();
  return (sameHome || sameAway) &&
      kickoffDifference <= const Duration(minutes: 5);
}

/// Applies Abu 3meer's prediction controls to a provider fixture without
/// discarding the provider identity needed by the match centre.
@visibleForTesting
MatchEvent mergeManagedFootballMatch(MatchEvent provider, MatchEvent managed) {
  final providerMatchId = provider.providerMatchId.trim().isNotEmpty
      ? provider.providerMatchId
      : provider.id;
  return provider.copyWith(
    id: managed.id,
    providerMatchId: providerMatchId,
    status: managed.status,
    homeScore: managed.homeScore ?? provider.homeScore,
    awayScore: managed.awayScore ?? provider.awayScore,
    firstScorer: managed.firstScorer.isNotEmpty
        ? managed.firstScorer
        : provider.firstScorer,
    firstScorerOptions: managed.firstScorerOptions.isNotEmpty
        ? managed.firstScorerOptions
        : provider.firstScorerOptions,
    predictionOpensAt: managed.predictionOpensAt,
    predictionClosesAt: managed.predictionClosesAt,
    kickoffAt: managed.kickoffAt,
  );
}

@visibleForTesting
String footballDetailsMatchId(MatchEvent event) =>
    event.providerMatchId.trim().isNotEmpty ? event.providerMatchId : event.id;

/// Parses a user-entered external URL without ever treating it as an in-app
/// relative path. Admins can enter either `example.com` or a complete URL.
Uri? externalHttpUri(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  // A value with an explicit scheme must already be HTTP(S). Without this
  // guard, `mailto:...` would be mistaken for a bare domain and prefixed with
  // https, producing a malformed but parseable URL.
  final explicitScheme = RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:');
  if (explicitScheme.hasMatch(value) &&
      !value.toLowerCase().startsWith('http://') &&
      !value.toLowerCase().startsWith('https://')) {
    return null;
  }
  final candidate = value.contains('://') ? value : 'https://$value';
  final uri = Uri.tryParse(candidate);
  if (uri == null ||
      !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
      uri.host.isEmpty) {
    return null;
  }
  return uri;
}

String _normalizedOptionalUrl(String raw, String field) {
  if (raw.trim().isEmpty) return '';
  final uri = externalHttpUri(raw);
  if (uri == null) {
    throw ArgumentError('$field must be a valid http or https URL.');
  }
  return uri.toString();
}

String? supportedAdminImageContentType({
  required String fileName,
  String? mimeType,
}) {
  const allowed = <String>{
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
  };
  final normalizedMime = mimeType?.trim().toLowerCase();
  if (normalizedMime != null && allowed.contains(normalizedMime)) {
    return normalizedMime;
  }
  final extension = fileName.toLowerCase().split('.').last;
  return switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    _ => null,
  };
}

/// A stable, last-good-value stream for API resources.
///
/// UI widgets call repository `watch*` methods from `build`. Returning the
/// same replaying stream prevents a parent rebuild (for example, a tab tap or
/// profile refresh) from disconnecting the old stream, showing a loading
/// skeleton, and starting another HTTP request. Concurrent refreshes are also
/// coalesced into one request.
class _ReplayResource<T> {
  _ReplayResource({
    required this.load,
    required this.maxAge,
    T? initialValue,
    bool hasInitialValue = false,
  }) : _value = initialValue,
       _hasValue = hasInitialValue;

  final Future<T> Function() load;
  final Duration maxAge;
  final StreamController<T> _updates = StreamController<T>.broadcast(
    sync: true,
  );

  T? _value;
  bool _hasValue;
  Object? _lastError;
  StackTrace? _lastStackTrace;
  DateTime? _loadedAt;
  Future<void>? _inFlight;
  Stream<T>? _stream;
  bool _disposed = false;

  bool get hasValue => _hasValue;
  T? get value => _hasValue ? _value : null;

  Stream<T> get stream => _stream ??= Stream<T>.multi((listener) {
    final subscription = _updates.stream.listen(
      listener.add,
      onError: listener.addError,
      onDone: listener.close,
    );
    if (_hasValue) {
      listener.add(_value as T);
    } else if (_lastError != null) {
      listener.addError(_lastError!, _lastStackTrace);
    }
    unawaited(refresh());
    listener.onCancel = subscription.cancel;
  }, isBroadcast: true);

  Future<void> refresh({bool force = false}) {
    if (_disposed) return Future<void>.value();
    final running = _inFlight;
    if (running != null) return running;
    final loadedAt = _loadedAt;
    if (!force &&
        _hasValue &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) < maxAge) {
      return Future<void>.value();
    }

    late final Future<void> operation;
    operation = () async {
      try {
        final result = await load();
        if (_disposed) return;
        _value = result;
        _hasValue = true;
        _lastError = null;
        _lastStackTrace = null;
        _loadedAt = DateTime.now();
        _updates.add(result);
      } catch (error, stackTrace) {
        if (_disposed) return;
        _lastError = error;
        _lastStackTrace = stackTrace;
        // A refresh failure must never erase a valid snapshot. Only an
        // initial failure is blocking; later failures retain the UI state.
        if (!_hasValue) _updates.addError(error, stackTrace);
      } finally {
        if (identical(_inFlight, operation)) _inFlight = null;
      }
    }();
    _inFlight = operation;
    return operation;
  }

  void emit(T value) {
    if (_disposed) return;
    _value = value;
    _hasValue = true;
    _lastError = null;
    _lastStackTrace = null;
    _loadedAt = DateTime.now();
    _updates.add(value);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _updates.close();
  }
}

class ProductionRepository {
  ProductionRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseStorage? storage,
    AbuExternalContentService? externalContent,
    ApiProductionRepository? apiRepo,
  }) : auth = auth ?? FirebaseAuth.instance,
       firestore = firestore ?? FirebaseFirestore.instance,
       functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1'),
       storage = storage ?? FirebaseStorage.instance,
       externalContent = externalContent ?? AbuExternalContentService(),
       apiRepo = apiRepo ?? ApiProductionRepository();

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;
  final FirebaseStorage storage;
  final AbuExternalContentService externalContent;
  final ApiProductionRepository apiRepo;
  bool _googleInitialized = false;
  final Map<String, Map<String, SavedPrediction>> _localPredictionsByUid = {};
  final Map<String, int> _predictionMutationRevision = {};
  final Map<String, AbuUserProfile> _localProfiles = {};
  final Map<String, _ReplayResource<AbuUserProfile?>> _profileResources = {};
  final Map<String, _ReplayResource<List<SavedPrediction>>>
  _predictionResources = {};
  _ReplayResource<List<MatchEvent>>? _matchesResource;
  _ReplayResource<List<MatchEvent>>? _managedMatchesResource;
  _ReplayResource<List<AbuChallenge>>? _challengesResource;
  _ReplayResource<List<ExclusiveVideo>>? _exclusiveVideosResource;
  final Map<bool, _ReplayResource<List<LeaderboardEntry>>>
  _leaderboardResources = {};
  final Map<String, _ReplayResource<LeaderboardSnapshot>>
  _leaderboardViewResources = {};
  final Map<String, _ReplayResource<List<PointLedgerEntry>>>
  _pointHistoryResources = {};
  final Map<String, _ReplayResource<List<AbuUserProfile>>> _adminUserResources =
      {};
  _ReplayResource<List<AdminPointAdjustment>>? _adminPointAdjustmentsResource;
  List<MatchEvent> _cachedMatches = const [];

  Stream<User?> get authChanges => auth.userChanges();

  Stream<AbuUserProfile?> watchProfile(String uid) {
    if (uid.isEmpty || uid == 'guest') {
      return Stream<AbuUserProfile?>.value(AbuUserProfile.guest());
    }
    final cached = _localProfiles[uid];
    return _profileResources
        .putIfAbsent(
          uid,
          () => _ReplayResource<AbuUserProfile?>(
            maxAge: const Duration(minutes: 5),
            initialValue: cached,
            hasInitialValue: cached != null,
            load: () async {
              final updated = await apiRepo.fetchProfile().timeout(
                const Duration(seconds: 8),
              );
              if (updated != null) _localProfiles[uid] = updated;
              return updated;
            },
          ),
        )
        .stream;
  }

  Future<void> refreshProfile(String uid, {bool force = false}) async {
    if (uid.isEmpty || uid == 'guest') return;
    watchProfile(uid);
    await _profileResources[uid]?.refresh(force: force);
  }

  /// Refreshes only resources that have already been opened in this app
  /// session. The shell calls this once when returning from the background;
  /// tab switches themselves never create network traffic.
  Future<void> refreshActiveResources({String? uid, bool force = false}) async {
    final tasks = <Future<void>>[];
    void add(_ReplayResource<dynamic>? resource) {
      if (resource != null) tasks.add(resource.refresh(force: force));
    }

    if (uid != null && uid.isNotEmpty && uid != 'guest') {
      add(_profileResources[uid]);
      add(_predictionResources[uid]);
      add(_pointHistoryResources[uid]);
    }
    add(_matchesResource);
    add(_managedMatchesResource);
    add(_challengesResource);
    add(_exclusiveVideosResource);
    for (final resource in _leaderboardResources.values) {
      add(resource);
    }
    for (final resource in _leaderboardViewResources.values) {
      add(resource);
    }
    for (final resource in _adminUserResources.values) {
      add(resource);
    }
    add(_adminPointAdjustmentsResource);
    await Future.wait(tasks);
  }

  Stream<List<MatchEvent>> watchManagedMatches() =>
      (_managedMatchesResource ??= _ReplayResource<List<MatchEvent>>(
        maxAge: const Duration(minutes: 2),
        load: () =>
            apiRepo.fetchUpcomingMatches().timeout(const Duration(seconds: 8)),
      )).stream;

  Stream<List<MatchEvent>> watchMatches() =>
      (_matchesResource ??= _ReplayResource<List<MatchEvent>>(
        maxAge: const Duration(minutes: 2),
        initialValue: _cachedMatches,
        hasInitialValue: _cachedMatches.isNotEmpty,
        load: _fetchCombinedMatches,
      )).stream;

  Future<List<MatchEvent>> _fetchCombinedMatches() async {
    List<MatchEvent>? managed;
    List<MatchEvent>? external;
    Object? firstError;
    StackTrace? firstStackTrace;

    await Future.wait([
      () async {
        try {
          managed = await apiRepo.fetchUpcomingMatches().timeout(
            const Duration(seconds: 8),
          );
        } catch (error, stackTrace) {
          firstError ??= error;
          firstStackTrace ??= stackTrace;
        }
      }(),
      () async {
        try {
          external = await apiRepo.fetchFootballWeekMatches().timeout(
            const Duration(seconds: 8),
          );
        } catch (error, stackTrace) {
          firstError ??= error;
          firstStackTrace ??= stackTrace;
        }
      }(),
    ]);

    if (managed == null && external == null) {
      Error.throwWithStackTrace(
        firstError ?? StateError('Match sources are unavailable.'),
        firstStackTrace ?? StackTrace.current,
      );
    }

    final managedMatches = managed ?? const <MatchEvent>[];
    final baseList = external ?? _cachedMatches;
    final result = <MatchEvent>[];
    for (final item in baseList) {
      final override = managedMatches
          .where((match) => sameFootballMatchForMatching(match, item))
          .firstOrNull;
      result.add(
        override == null ? item : mergeManagedFootballMatch(item, override),
      );
    }
    for (final match in managedMatches) {
      final included = result.any(
        (item) => sameFootballMatchForMatching(item, match),
      );
      if (!included) result.add(match);
    }
    result.sort((a, b) => a.kickoffAt.compareTo(b.kickoffAt));
    _cachedMatches = result;
    return result;
  }

  Future<LatestVideo> latestVideo({bool refresh = false}) async {
    try {
      final doc = await firestore
          .collection('platformSettings')
          .doc('latestVideo')
          .get()
          .timeout(const Duration(seconds: 3));
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final rawDate = data['publishedAt'];
        final DateTime publishedDate;
        if (rawDate is Timestamp) {
          publishedDate = rawDate.toDate();
        } else if (rawDate is int) {
          publishedDate = DateTime.fromMillisecondsSinceEpoch(rawDate);
        } else if (rawDate is String) {
          publishedDate = DateTime.tryParse(rawDate) ?? DateTime.now();
        } else {
          publishedDate = DateTime.now();
        }
        return LatestVideo(
          id: data['id'] as String? ?? '',
          title: data['title'] as String? ?? '',
          url: data['url'] as String? ?? '',
          thumbnailUrl: data['thumbnailUrl'] as String? ?? '',
          publishedAt: publishedDate,
        );
      }
    } catch (_) {}
    try {
      return await externalContent.latestVideo(refresh: refresh);
    } catch (_) {
      return LatestVideo(
        id: 'dQw4w9WgXcQ',
        title: 'Abu 3meer Official Channel',
        url: 'https://www.youtube.com/@Abu3meer',
        thumbnailUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        publishedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
    }
  }

  Future<FootballTeamAsset?> lookupTeam(String name) async {
    final teams = await apiRepo.searchFootballTeams(name);
    return teams.firstOrNull;
  }

  Future<List<String>> lookupMatchScorers(
    String homeTeam,
    String awayTeam, {
    String? homeTeamId,
    String? awayTeamId,
  }) async {
    try {
      var resolvedHomeId = homeTeamId?.trim() ?? '';
      var resolvedAwayId = awayTeamId?.trim() ?? '';
      if (resolvedHomeId.isEmpty || resolvedAwayId.isEmpty) {
        final teams = await Future.wait([
          resolvedHomeId.isEmpty
              ? apiRepo.searchFootballTeams(homeTeam)
              : Future.value(const <FootballTeamAsset>[]),
          resolvedAwayId.isEmpty
              ? apiRepo.searchFootballTeams(awayTeam)
              : Future.value(const <FootballTeamAsset>[]),
        ]);
        if (resolvedHomeId.isEmpty && teams[0].isNotEmpty) {
          resolvedHomeId = teams[0].first.teamId;
        }
        if (resolvedAwayId.isEmpty && teams[1].isNotEmpty) {
          resolvedAwayId = teams[1].first.teamId;
        }
      }

      final players = await Future.wait([
        apiRepo.fetchFootballTeamPlayers(resolvedHomeId),
        apiRepo.fetchFootballTeamPlayers(resolvedAwayId),
      ]);
      return <String>{...players[0], ...players[1]}.toList(growable: false);
    } catch (_) {
      // Existing match options remain usable if the self-hosted API is
      // temporarily unavailable. Never fall back to a provider request from
      // each device because that would multiply use of the paid allowance.
      return const <String>[];
    }
  }

  Future<MatchDetails> fetchMatchDetails(MatchEvent event) async {
    try {
      final detailsMatchId = footballDetailsMatchId(event);
      final details = await apiRepo
          .fetchMatchDetails(detailsMatchId)
          .timeout(const Duration(seconds: 12));
      return details.timeline.isEmpty && event.timeline.isNotEmpty
          ? details.copyWith(timeline: event.timeline)
          : details;
    } catch (_) {
      // A bundled timeline may still be shown, but provider calls always stay
      // behind the shared server cache.
      return MatchDetails(timeline: event.timeline);
    }
  }

  Future<List<MatchTimelineEvent>> fetchMatchTimeline(String eventId) async {
    try {
      final details = await apiRepo.fetchMatchDetails(eventId);
      return details.timeline;
    } catch (_) {
      return const <MatchTimelineEvent>[];
    }
  }

  Stream<List<PointLedgerEntry>> watchPointHistory(String uid) {
    if (uid.isEmpty || uid == 'guest') {
      return Stream.value(const <PointLedgerEntry>[]);
    }
    return _pointHistoryResources
        .putIfAbsent(
          uid,
          () => _ReplayResource<List<PointLedgerEntry>>(
            maxAge: const Duration(minutes: 5),
            load: apiRepo.fetchPointHistory,
          ),
        )
        .stream;
  }

  Future<AbuUserProfile?> fetchProfileByUid(String uid) async {
    if (uid.isEmpty || uid == 'guest') return null;
    try {
      final fromApi = await apiRepo.fetchPublicProfile(uid);
      if (fromApi != null) return fromApi;

      final doc = await firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        return AbuUserProfile.fromDocument(doc);
      }
    } catch (_) {}
    return null;
  }

  Future<int> fetchUserRank(String uid) async {
    if (uid.isEmpty || uid == 'guest') return 1;
    try {
      final snap = await firestore
          .collection('leaderboardEntries')
          .orderBy('totalPoints', descending: true)
          .limit(100)
          .get();
      for (var i = 0; i < snap.docs.length; i++) {
        if (snap.docs[i].id == uid) {
          return i + 1;
        }
      }
      final userSnap = await firestore
          .collection('users')
          .orderBy('totalPoints', descending: true)
          .limit(100)
          .get();
      for (var i = 0; i < userSnap.docs.length; i++) {
        if (userSnap.docs[i].id == uid) {
          return i + 1;
        }
      }
    } catch (_) {}
    return 1;
  }

  Future<double> fetchUserAccuracy(String uid) async {
    if (uid.isEmpty || uid == 'guest') return 100.0;
    try {
      final snap = await firestore
          .collection('predictions')
          .where('userId', isEqualTo: uid)
          .get();
      if (snap.docs.isEmpty) return 100.0;
      var correctCount = 0;
      var completedCount = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final points = (data['pointsAwarded'] as num?)?.toInt() ?? 0;
        final rewarded = data['rewarded'] == true;
        final seen = data['seenResult'] == true;
        if (rewarded || seen || points > 0) {
          completedCount++;
          if (points > 0) correctCount++;
        }
      }
      if (completedCount == 0) return 100.0;
      return (correctCount / completedCount) * 100.0;
    } catch (_) {}
    return 100.0;
  }

  Stream<List<LeaderboardEntry>> watchLeaderboard({required bool monthly}) =>
      _leaderboardResources
          .putIfAbsent(
            monthly,
            () => _ReplayResource<List<LeaderboardEntry>>(
              maxAge: const Duration(minutes: 2),
              load: () => apiRepo.fetchTopLeaderboard(
                period: monthly ? 'monthly' : 'season',
              ),
            ),
          )
          .stream;

  Stream<List<AbuChallenge>> watchChallenges() =>
      (_challengesResource ??= _ReplayResource<List<AbuChallenge>>(
        maxAge: const Duration(minutes: 2),
        load: apiRepo.fetchActiveChallenges,
      )).stream;

  Stream<List<AbuChallenge>> watchManagedChallenges() => watchChallenges();

  Stream<List<AbuPost>> watchPosts() => firestore
      .collection('posts')
      .orderBy('publishedAt', descending: true)
      .limit(40)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(AbuPost.fromDocument).toList())
      .handleError((_) => const <AbuPost>[]);

  Stream<List<AbuComment>> watchPostComments(String postId) => firestore
      .collection('posts')
      .doc(postId)
      .collection('comments')
      .orderBy('createdAt')
      .limit(200)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(AbuComment.fromDocument).toList())
      .handleError((_) => const <AbuComment>[]);

  Stream<LaunchAnnouncement?> watchLaunchAnnouncement() => firestore
      .collection('platformSettings')
      .doc('launchAnnouncement')
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.exists ? LaunchAnnouncement.fromDocument(snapshot) : null,
      )
      .handleError((_) => null);

  /// The self-hosted PostgreSQL database is the account source of truth.
  /// Firestore may not contain a document for Firebase users created after the
  /// migration, which previously made every admin picker look empty.
  Future<List<AbuUserProfile>> fetchAdminUsers({String search = ''}) =>
      apiRepo.fetchAdminUsers(search: search);

  Stream<List<AbuUserProfile>> watchUsers({String search = ''}) {
    final normalized = search.trim().toLowerCase();
    return _adminUserResources
        .putIfAbsent(
          normalized,
          () => _ReplayResource<List<AbuUserProfile>>(
            maxAge: const Duration(minutes: 2),
            load: () => fetchAdminUsers(search: normalized),
          ),
        )
        .stream;
  }

  Stream<FanDuel?> watchFanDuel(String code) => firestore
      .collection('duelRooms')
      .doc(code.toUpperCase())
      .snapshots()
      .map(
        (snapshot) => snapshot.exists ? FanDuel.fromDocument(snapshot) : null,
      )
      .handleError((_) => null);

  Stream<Map<String, DateTime>> watchDuelTaps(String code) => firestore
      .collection('duelRooms')
      .doc(code.toUpperCase())
      .collection('taps')
      .snapshots()
      .map(
        (snapshot) => {
          for (final doc in snapshot.docs)
            doc.id: (doc.data()['tappedAt'] as Timestamp).toDate(),
        },
      )
      .handleError((_) => const <String, DateTime>{});

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> createEmailAccount({
    required String email,
    required String password,
  }) async {
    final result = await auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await result.user?.sendEmailVerification();
  }

  Future<void> sendPasswordReset(String email) =>
      auth.sendPasswordResetEmail(email: email.trim());

  Future<void> resendVerification() =>
      auth.currentUser!.sendEmailVerification();

  Future<void> refreshUser() => auth.currentUser!.reload();

  Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      await auth.signInWithPopup(GoogleAuthProvider());
      return;
    }
    if (!_googleInitialized) {
      await GoogleSignIn.instance.initialize();
      _googleInitialized = true;
    }
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(
        code: 'missing-google-token',
        message: 'Google did not return a valid identity token.',
      );
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    await auth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    final uid = auth.currentUser?.uid;
    await auth.signOut();
    if (!kIsWeb && _googleInitialized) {
      await GoogleSignIn.instance.signOut();
    }
    if (uid != null) {
      _localProfiles.remove(uid);
      _localPredictionsByUid.remove(uid);
      _predictionMutationRevision.remove(uid);
      await _profileResources.remove(uid)?.dispose();
      await _predictionResources.remove(uid)?.dispose();
      await _pointHistoryResources.remove(uid)?.dispose();
    }
    for (final resource in _adminUserResources.values) {
      await resource.dispose();
    }
    _adminUserResources.clear();
    await _adminPointAdjustmentsResource?.dispose();
    _adminPointAdjustmentsResource = null;
  }

  Future<void> completeOnboarding({
    required String username,
    required String displayName,
    required String country,
    String countryCode = '',
    required String supportedTeam,
    String supportedTeamLogo = '',
    String avatarUrl = '',
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'unauthenticated',
        message: 'Sign in is required.',
      );
    }
    final normalizedUsername = username.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{3,24}$').hasMatch(normalizedUsername)) {
      throw ArgumentError(
        'Username must be 3–24 letters, numbers, or underscores.',
      );
    }
    final normalizedDisplayName = displayName.trim();
    final normalizedCountry = country.trim();
    if (normalizedDisplayName.isEmpty || normalizedDisplayName.length > 60) {
      throw ArgumentError('Enter a valid display name.');
    }
    if (normalizedCountry.isEmpty || normalizedCountry.length > 60) {
      throw ArgumentError('Enter a valid country.');
    }
    final normalizedSupportedTeam = supportedTeam.trim().isEmpty
        ? 'Barcelona'
        : supportedTeam.trim();

    // PostgreSQL is authoritative for onboarding as well as later edits. The
    // authenticated API provisions the account atomically on first access,
    // then applies these user-selected values in the same durable database.
    await updateProfile(
      username: normalizedUsername,
      displayName: normalizedDisplayName,
      country: normalizedCountry,
      countryCode: countryCode.trim(),
      supportedTeam: normalizedSupportedTeam,
      supportedTeamLogo: supportedTeamLogo.trim().isEmpty
          ? null
          : supportedTeamLogo.trim(),
      avatarUrl: avatarUrl.trim().isEmpty ? null : avatarUrl.trim(),
      markOnboardingComplete: true,
    );
  }

  Future<void> updateProfile({
    required String username,
    required String displayName,
    required String country,
    String countryCode = '',
    required String supportedTeam,
    String? avatarUrl,
    String? supportedTeamLogo,
    bool markOnboardingComplete = false,
  }) async {
    final user = auth.currentUser;
    if (user == null) throw StateError('Sign in is required.');
    final normalized = username.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{3,30}$').hasMatch(normalized)) {
      throw ArgumentError(
        'Username must be 3–30 letters, numbers, or underscores.',
      );
    }
    final normalizedDisplayName = displayName.trim();
    if (normalizedDisplayName.isEmpty) {
      throw ArgumentError('Enter a valid display name.');
    }

    // PostgreSQL is the source of truth. Do not show a successful save or
    // mutate local state until the self-hosted API has accepted the update.
    await apiRepo.updateProfile(
      displayName: normalizedDisplayName,
      username: normalized,
      country: country.trim(),
      countryCode: countryCode.trim().isEmpty ? null : countryCode.trim(),
      supportedTeam: supportedTeam.trim(),
      avatarUrl: avatarUrl?.trim(),
      supportedTeamLogo: supportedTeamLogo?.trim(),
      onboardingCompleted: markOnboardingComplete ? true : null,
    );

    // Firebase Auth only supplies identity tokens now. Keep its optional
    // display metadata aligned, but never let it decide whether the database
    // save succeeded.
    try {
      await user.updateDisplayName(normalizedDisplayName);
      if (avatarUrl != null && avatarUrl.isNotEmpty) {
        await user.updatePhotoURL(avatarUrl.trim());
      }
    } catch (_) {}

    // Update local state only after the API write has committed.
    final current = _localProfiles[user.uid];
    final updated =
        (current ??
                AbuUserProfile(
                  uid: user.uid,
                  email: user.email ?? '',
                  username: normalized,
                  displayName: normalizedDisplayName,
                  country: country.trim(),
                  countryCode: countryCode.trim(),
                  supportedTeam: supportedTeam.trim(),
                  avatarUrl: user.photoURL ?? '',
                  role: 'fan',
                  membershipMultiplier: 1,
                  totalPoints: 0,
                  monthlyPoints: 0,
                  seasonPoints: 0,
                  loyaltyPoints: 0,
                  suspended: false,
                  onboardingCompleted: markOnboardingComplete ? true : null,
                ))
            .copyWith(
              username: normalized,
              displayName: normalizedDisplayName,
              country: country.trim(),
              countryCode: countryCode.trim(),
              supportedTeam: supportedTeam.trim(),
              supportedTeamLogo: supportedTeamLogo?.trim().isNotEmpty == true
                  ? supportedTeamLogo!.trim()
                  : current?.supportedTeamLogo,
              avatarUrl: avatarUrl?.trim().isNotEmpty == true
                  ? avatarUrl!.trim()
                  : current?.avatarUrl,
              onboardingCompleted: markOnboardingComplete
                  ? true
                  : current?.onboardingCompleted,
            );
    _localProfiles[user.uid] = updated;
    _profileResources[user.uid]?.emit(updated);
  }

  Future<int> checkInDailyStreak(String uid) async {
    if (uid.isEmpty || uid == 'guest') return 0;
    try {
      final res = await apiRepo.checkInDailyStreak();
      final streak = (res['streakCount'] as num? ?? 1).toInt();
      final pointsAwarded = (res['pointsAwarded'] as num? ?? 0).toInt();
      if (_localProfiles.containsKey(uid)) {
        final current = _localProfiles[uid]!;
        final newStreak = streak > 0 ? streak : current.currentStreak;
        final newTotal = current.totalPoints + pointsAwarded;
        final updated = current.copyWith(
          currentStreak: newStreak,
          longestStreak: newStreak > current.longestStreak
              ? newStreak
              : current.longestStreak,
          totalPoints: newTotal,
          monthlyPoints: current.monthlyPoints + pointsAwarded,
          seasonPoints: current.seasonPoints + pointsAwarded,
          loyaltyPoints: current.loyaltyPoints + pointsAwarded,
          lastCheckInDate: DateTime.now()
              .toUtc()
              .toIso8601String()
              .split('T')
              .first,
        );
        _localProfiles[uid] = updated;
        _profileResources[uid]?.emit(updated);
      }
      return pointsAwarded;
    } catch (error, stackTrace) {
      debugPrint('[Streak] Daily check-in failed: $error\n$stackTrace');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> submitChallengeAnswer({
    required AbuChallenge challenge,
    required String answer,
  }) async {
    try {
      final res = await apiRepo.submitChallengeAnswer(
        challengeId: challenge.id,
        answer: answer.trim(),
      );
      return res;
    } catch (e) {
      return {'correct': false, 'pointsAwarded': 0, 'message': e.toString()};
    }
  }

  Future<void> createChallenge({
    required String kind,
    required String title,
    required String description,
    required String videoUrl,
    required String answer,
    required int rewardPoints,
    required DateTime availableFrom,
    required DateTime availableUntil,
    required String status,
    required int maximumAttempts,
    required bool memberOnly,
    required bool notifyOnLive,
  }) async {
    if (!availableFrom.isBefore(availableUntil)) {
      throw ArgumentError('The event end time must be after its start time.');
    }
    if (!const ['draft', 'scheduled', 'open', 'disabled'].contains(status)) {
      throw ArgumentError('Choose a supported event status.');
    }
    if (rewardPoints < 0 || maximumAttempts < 1) {
      throw ArgumentError('Points and attempts must be valid positive values.');
    }
    final collection = kind == 'playerCard' ? 'playerCards' : 'videoQuestions';
    final ref = firestore.collection(collection).doc();
    final batch = firestore.batch();
    batch.set(ref, {
      'title': title.trim(),
      'description': description.trim(),
      'videoUrl': videoUrl.trim(),
      'rewardPoints': rewardPoints,
      'kind': kind,
      'status': status,
      'maximumAttempts': maximumAttempts,
      'memberOnly': memberOnly,
      'notifyOnLive': notifyOnLive,
      'availableFrom': Timestamp.fromDate(availableFrom),
      'availableUntil': Timestamp.fromDate(availableUntil),
      'createdBy': auth.currentUser!.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(ref.collection('private').doc('answer'), {
      'normalizedAnswer': normalizeChallengeAnswer(answer),
    });
    await batch.commit();
  }

  Future<void> setChallengeStatus({
    required AbuChallenge challenge,
    required String status,
  }) => firestore
      .collection(
        challenge.kind == 'playerCard' ? 'playerCards' : 'videoQuestions',
      )
      .doc(challenge.id)
      .update({
        'status': status,
        'updatedBy': auth.currentUser!.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> createPost({
    required String title,
    required String body,
    required String imageUrl,
    required String linkUrl,
    required String authorName,
  }) {
    final normalizedImage = _normalizedOptionalUrl(imageUrl, 'Image URL');
    final normalizedLink = _normalizedOptionalUrl(linkUrl, 'Clickable link');
    return firestore.collection('posts').add({
      'title': title.trim(),
      'body': body.trim(),
      'imageUrl': normalizedImage,
      'linkUrl': normalizedLink,
      'authorName': authorName.trim(),
      'createdBy': auth.currentUser!.uid,
      'publishedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> togglePostLike(String postId) async {
    final uid = auth.currentUser?.uid;
    if (uid == null || uid.isEmpty || uid == 'guest') {
      throw StateError('Sign in to like posts.');
    }
    final reactionRef = firestore
        .collection('posts')
        .doc(postId)
        .collection('reactions')
        .doc(uid);

    final snap = await reactionRef.get();
    if (snap.exists) {
      await reactionRef.delete();
      return false;
    } else {
      await reactionRef.set({
        'userId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    }
  }

  Future<void> reactToPost(String postId) => togglePostLike(postId);

  Stream<bool> watchPostLiked(String postId) {
    final uid = auth.currentUser?.uid;
    if (uid == null || uid.isEmpty || uid == 'guest') {
      return Stream.value(false);
    }
    return firestore
        .collection('posts')
        .doc(postId)
        .collection('reactions')
        .doc(uid)
        .snapshots()
        .map((s) => s.exists)
        .handleError((_) => false);
  }

  Stream<int> watchPostLikeCount(String postId) {
    return firestore
        .collection('posts')
        .doc(postId)
        .collection('reactions')
        .snapshots()
        .map((s) => s.docs.length)
        .handleError((_) => 0);
  }

  Future<void> deletePost(String postId) async {
    await firestore.collection('posts').doc(postId).delete();
  }

  Future<void> deletePostComment({
    required String postId,
    required String commentId,
  }) async {
    await firestore
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .doc(commentId)
        .delete();
  }

  Future<void> setUserSuspension({
    required String uid,
    required bool suspended,
  }) => apiRepo.setAdminUserStatus(userId: uid, suspended: suspended);

  Future<void> addPostComment({
    required String postId,
    required String userName,
    required String body,
  }) => firestore.collection('posts').doc(postId).collection('comments').add({
    'userId': auth.currentUser?.uid ?? '',
    'userName': userName.trim(),
    'body': body.trim(),
    'createdAt': FieldValue.serverTimestamp(),
  });

  Future<void> saveAnnouncement({
    required bool enabled,
    required String title,
    required String body,
    required String imageUrl,
    required String linkUrl,
    required String buttonLabel,
    required String frequency,
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {
    if (!startsAt.isBefore(endsAt)) {
      throw ArgumentError('The popup end time must be after its start time.');
    }
    if (!const ['once', 'daily', 'session', 'always'].contains(frequency)) {
      throw ArgumentError('Choose a supported popup frequency.');
    }
    final normalizedImage = _normalizedOptionalUrl(imageUrl, 'Image URL');
    final normalizedLink = _normalizedOptionalUrl(linkUrl, 'Clickable link');
    await firestore
        .collection('platformSettings')
        .doc('launchAnnouncement')
        .set({
          'enabled': enabled,
          'title': title.trim(),
          'body': body.trim(),
          'imageUrl': normalizedImage,
          'linkUrl': normalizedLink,
          'buttonLabel': buttonLabel.trim(),
          'frequency': frequency,
          'startsAt': Timestamp.fromDate(startsAt),
          'endsAt': Timestamp.fromDate(endsAt),
          'revision': DateTime.now().millisecondsSinceEpoch,
          'updatedBy': auth.currentUser!.uid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> setUserRole({required String uid, required String role}) async {
    await apiRepo.setAdminUserRole(userId: uid, role: role);
  }

  Future<String> createFanDuel({required String hostName}) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw StateError('Sign in is required.');
    final generated = firestore.collection('duelRooms').doc().id;
    final code = generated.substring(0, 6).toUpperCase();
    await firestore.collection('duelRooms').doc(code).set({
      'hostUid': uid,
      'hostName': hostName.trim(),
      'guestUid': '',
      'guestName': '',
      'status': 'waiting',
      'startAt': null,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return code;
  }

  Future<void> joinFanDuel({
    required String code,
    required String guestName,
  }) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw StateError('Sign in is required.');
    final ref = firestore
        .collection('duelRooms')
        .doc(code.trim().toUpperCase());
    await firestore.runTransaction((transaction) async {
      final room = await transaction.get(ref);
      if (!room.exists) throw StateError('Duel code not found.');
      final data = room.data()!;
      if ((data['guestUid'] as String? ?? '').isNotEmpty) {
        throw StateError('This duel already has two players.');
      }
      if (data['hostUid'] == uid) {
        throw StateError('Share this code with another user.');
      }
      transaction.update(ref, {
        'guestUid': uid,
        'guestName': guestName.trim(),
        'status': 'ready',
        'startAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(seconds: 6)),
        ),
      });
    });
  }

  Future<void> tapFanDuel(String code) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw StateError('Sign in is required.');
    await firestore
        .collection('duelRooms')
        .doc(code.toUpperCase())
        .collection('taps')
        .doc(uid)
        .set({'userId': uid, 'tappedAt': FieldValue.serverTimestamp()});
  }

  Future<void> submitPrediction({
    required String matchId,
    required int homeScore,
    required int awayScore,
    required String firstScorer,
    String homeTeam = '',
    String awayTeam = '',
    String competition = '',
    DateTime? kickoffAt,
    String homeLogoUrl = '',
    String awayLogoUrl = '',
  }) async {
    final user = auth.currentUser;
    if (user == null) throw StateError('Must be signed in to predict.');

    // PostgreSQL is authoritative. Only advertise a locked prediction after
    // the API transaction has committed.
    await apiRepo.submitPrediction(
      matchId: matchId,
      homeScore: homeScore,
      awayScore: awayScore,
      firstScorer: firstScorer.trim(),
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      competition: competition,
      kickoffAt: kickoffAt,
      homeLogoUrl: homeLogoUrl,
      awayLogoUrl: awayLogoUrl,
    );

    final predictions = _localPredictionsByUid.putIfAbsent(
      user.uid,
      () => <String, SavedPrediction>{},
    );
    predictions[matchId] = SavedPrediction(
      id: '${matchId}_${user.uid}',
      userId: user.uid,
      matchId: matchId,
      homeScore: homeScore,
      awayScore: awayScore,
      firstScorer: firstScorer.trim(),
      submittedAt: DateTime.now(),
      updatedAt: DateTime.now(),
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      rewarded: false,
    );
    _predictionMutationRevision[user.uid] =
        (_predictionMutationRevision[user.uid] ?? 0) + 1;
    _predictionResources[user.uid]?.emit(_predictionSnapshot(user.uid));
  }

  Future<void> adminToggleMatchPredictions({
    required String matchId,
    required bool open,
    String homeTeam = '',
    String awayTeam = '',
    String competition = '',
    DateTime? kickoffAt,
    String homeLogoUrl = '',
    String awayLogoUrl = '',
  }) async {
    final matchRef = firestore.collection('matches').doc(matchId);
    final matchSnap = await matchRef.get();
    final timestamp = FieldValue.serverTimestamp();
    if (!matchSnap.exists) {
      final matchKickoff =
          kickoffAt ?? DateTime.now().add(const Duration(days: 1));
      await matchRef.set({
        'homeTeam': homeTeam.isNotEmpty ? homeTeam : 'Home',
        'awayTeam': awayTeam.isNotEmpty ? awayTeam : 'Away',
        'competition': competition.isNotEmpty ? competition : 'La Liga',
        'homeLogoUrl': homeLogoUrl,
        'awayLogoUrl': awayLogoUrl,
        'firstScorerOptions': const ['No scorer'],
        'kickoffAt': Timestamp.fromDate(matchKickoff),
        'predictionOpensAt': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(hours: 24)),
        ),
        'predictionClosesAt': open
            ? Timestamp.fromDate(DateTime.now().add(const Duration(days: 7)))
            : Timestamp.fromDate(DateTime.now()),
        'status': open ? 'open' : 'locked',
        'createdAt': timestamp,
        'updatedAt': timestamp,
      });
    } else {
      await matchRef.update({
        'status': open ? 'open' : 'locked',
        'predictionClosesAt': open
            ? Timestamp.fromDate(DateTime.now().add(const Duration(days: 7)))
            : Timestamp.fromDate(DateTime.now()),
        'updatedAt': timestamp,
      });
    }
  }

  Future<List<PredictionOutcomeResult>> checkUnseenCompletedPredictions(
    String uid, {
    bool isYouTubeMember = false,
  }) async {
    if (uid.isEmpty || uid == 'guest') return const [];

    try {
      final predSnap = await firestore
          .collection('predictions')
          .where('userId', isEqualTo: uid)
          .get();

      if (predSnap.docs.isEmpty) return const [];

      final predictions = predSnap.docs
          .map(SavedPrediction.fromDocument)
          .toList();
      final targetPreds = predictions
          .where((p) => !p.rewarded || !p.seenResult)
          .toList();
      if (targetPreds.isEmpty) return const [];

      final matchDocs = await firestore.collection('matches').get();
      final firestoreMatches = matchDocs.docs
          .map(MatchEvent.fromDocument)
          .toList();
      List<MatchEvent> recentExternalMatches = const [];
      try {
        recentExternalMatches = await apiRepo.fetchFootballRecentMatches();
      } catch (_) {}

      final allMatches = [...firestoreMatches, ...recentExternalMatches];

      final pointRules = await loadPointRules();
      final exactScorePoints = (pointRules['exactPrediction'] ?? 30).toInt();
      final firstScorerPoints = (pointRules['firstScorer'] ?? 20).toInt();
      final winnerPoints = (pointRules['winnerOutcome'] ?? 10).toInt();
      final multiplier = isYouTubeMember ? 2 : 1;

      final results = <PredictionOutcomeResult>[];

      for (final pred in targetPreds) {
        MatchEvent? match;
        for (final m in allMatches) {
          if (m.id == pred.matchId ||
              (pred.homeTeam.isNotEmpty &&
                  pred.awayTeam.isNotEmpty &&
                  m.homeTeam.trim().toLowerCase() ==
                      pred.homeTeam.trim().toLowerCase() &&
                  m.awayTeam.trim().toLowerCase() ==
                      pred.awayTeam.trim().toLowerCase())) {
            match = m;
            break;
          }
        }

        final foundMatch = match;
        if (foundMatch == null ||
            foundMatch.homeScore == null ||
            foundMatch.awayScore == null) {
          continue;
        }

        var activeMatch = foundMatch;

        // Fetch timeline if empty and from API
        List<MatchTimelineEvent> timeline = activeMatch.timeline;
        if (timeline.isEmpty && activeMatch.id.startsWith('external_')) {
          try {
            timeline = await apiRepo
                .fetchMatchDetails(activeMatch.id)
                .then((details) => details.timeline);
            if (timeline.isNotEmpty) {
              activeMatch = activeMatch.copyWith(timeline: timeline);
            }
          } catch (_) {}
        }

        // Determine effective first scorer
        String effectiveFirstScorer = activeMatch.firstScorer.trim();
        if (effectiveFirstScorer.isEmpty && timeline.isNotEmpty) {
          final firstGoal = timeline
              .where(
                (t) =>
                    t.type.toLowerCase().contains('goal') ||
                    t.type.toLowerCase().contains('penalty'),
              )
              .firstOrNull;
          if (firstGoal != null) {
            effectiveFirstScorer = firstGoal.player;
          }
        }
        if (effectiveFirstScorer.isEmpty &&
            activeMatch.homeScore == 0 &&
            activeMatch.awayScore == 0) {
          effectiveFirstScorer = 'No scorer';
        }

        final bool exactMatch =
            activeMatch.homeScore == pred.homeScore &&
            activeMatch.awayScore == pred.awayScore;

        final cleanEffScorer = effectiveFirstScorer
            .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
            .trim()
            .toLowerCase();
        final cleanPredScorer = pred.firstScorer
            .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
            .trim()
            .toLowerCase();
        final bool firstScorerMatch =
            (cleanEffScorer.isNotEmpty &&
                cleanPredScorer.isNotEmpty &&
                (cleanEffScorer == cleanPredScorer ||
                    cleanEffScorer.contains(cleanPredScorer) ||
                    cleanPredScorer.contains(cleanEffScorer))) ||
            (activeMatch.homeScore == 0 &&
                activeMatch.awayScore == 0 &&
                (cleanPredScorer == 'no scorer' || cleanPredScorer.isEmpty));

        final bool winnerMatch =
            ((pred.homeScore > pred.awayScore &&
                activeMatch.homeScore! > activeMatch.awayScore!) ||
            (pred.homeScore < pred.awayScore &&
                activeMatch.homeScore! < activeMatch.awayScore!) ||
            (pred.homeScore == pred.awayScore &&
                activeMatch.homeScore! == activeMatch.awayScore!));

        var pointsEarned = 0;
        if (exactMatch) pointsEarned += exactScorePoints;
        if (firstScorerMatch) pointsEarned += firstScorerPoints;
        if (winnerMatch) pointsEarned += winnerPoints;
        pointsEarned *= multiplier;

        final isPerfect = exactMatch && firstScorerMatch && winnerMatch;
        final hasSomeCorrect = pointsEarned > 0;

        // Reward user or reconcile points if rules adjusted
        final int pointDiff;
        if (!pred.rewarded) {
          pointDiff = pointsEarned;
        } else if (pred.pointsAwarded != pointsEarned) {
          pointDiff = pointsEarned - pred.pointsAwarded;
        } else {
          pointDiff = 0;
        }

        if (pointDiff != 0 || !pred.rewarded) {
          try {
            final userRef = firestore.collection('users').doc(uid);
            final leaderboardRef = firestore
                .collection('leaderboardEntries')
                .doc(uid);
            final txRef = firestore.collection('pointTransactions').doc();
            final timestamp = FieldValue.serverTimestamp();

            if (pointDiff != 0) {
              await userRef.update({
                'totalPoints': FieldValue.increment(pointDiff),
                'monthlyPoints': FieldValue.increment(pointDiff),
                'seasonPoints': FieldValue.increment(pointDiff),
                'loyaltyPoints': FieldValue.increment(pointDiff),
                'lastActivityAt': timestamp,
                'updatedAt': timestamp,
              });

              await leaderboardRef.set({
                'totalPoints': FieldValue.increment(pointDiff),
                'monthlyPoints': FieldValue.increment(pointDiff),
                'seasonPoints': FieldValue.increment(pointDiff),
                'updatedAt': timestamp,
              }, SetOptions(merge: true));

              if (pointDiff > 0) {
                await txRef.set({
                  'userId': uid,
                  'type': 'prediction_win',
                  'points': pointDiff,
                  'description':
                      'Prediction outcome: ${activeMatch.homeTeam} vs ${activeMatch.awayTeam} (+$pointDiff pts)',
                  'sourceId': activeMatch.id,
                  'createdAt': timestamp,
                });
              }
            }

            await firestore.collection('predictions').doc(pred.id).update({
              'rewarded': true,
              'pointsAwarded': pointsEarned,
              'seenResult': false,
              'updatedAt': timestamp,
            });
          } catch (_) {}
        }

        results.add(
          PredictionOutcomeResult(
            event: activeMatch,
            prediction: pred,
            exactMatch: exactMatch,
            firstScorerMatch: firstScorerMatch,
            winnerMatch: winnerMatch,
            pointsEarned: pointsEarned,
            isPerfect: isPerfect,
            hasSomeCorrect: hasSomeCorrect,
          ),
        );
      }

      return results;
    } catch (_) {
      return const [];
    }
  }

  Future<void> markPredictionResultSeen(String predictionId) async {
    try {
      await firestore.collection('predictions').doc(predictionId).update({
        'seenResult': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> createMatch({
    required String homeTeam,
    required String awayTeam,
    required String competition,
    required DateTime kickoffAt,
    required DateTime predictionOpensAt,
    required DateTime predictionClosesAt,
    String homeLogoUrl = '',
    String awayLogoUrl = '',
    List<String> firstScorerOptions = const <String>[],
  }) async {
    if (!(predictionOpensAt.isBefore(predictionClosesAt) &&
        !predictionClosesAt.isAfter(kickoffAt))) {
      throw ArgumentError('Prediction times must be ordered before kickoff.');
    }
    final scorerOptions = firstScorerOptions
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .take(59)
        .toList();
    if (scorerOptions.isNotEmpty &&
        !scorerOptions.any((value) => value.toLowerCase() == 'no scorer')) {
      scorerOptions.add('No scorer');
    }
    await firestore.collection('matches').add({
      'homeTeam': homeTeam.trim(),
      'awayTeam': awayTeam.trim(),
      'competition': competition.trim(),
      'kickoffAt': Timestamp.fromDate(kickoffAt),
      'predictionOpensAt': Timestamp.fromDate(predictionOpensAt),
      'predictionClosesAt': Timestamp.fromDate(predictionClosesAt),
      'homeLogoUrl': _normalizedOptionalUrl(homeLogoUrl, 'Home logo URL'),
      'awayLogoUrl': _normalizedOptionalUrl(awayLogoUrl, 'Away logo URL'),
      'firstScorerOptions': scorerOptions,
      'status': 'open',
      'createdBy': auth.currentUser!.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> publishMatchResult({
    required String matchId,
    required int homeScore,
    required int awayScore,
    required String firstScorer,
  }) async {
    try {
      await _call('adminPublishMatchResult', {
        'matchId': matchId,
        'homeScore': homeScore,
        'awayScore': awayScore,
        'firstScorer': firstScorer.trim(),
      });
    } catch (_) {}

    // Ensure Firestore match doc and ALL fan predictions for this match are settled immediately
    final timestamp = FieldValue.serverTimestamp();
    await firestore.collection('matches').doc(matchId).update({
      'homeScore': homeScore,
      'awayScore': awayScore,
      'firstScorer': firstScorer.trim(),
      'status': 'completed',
      'resultProcessed': true,
      'updatedAt': timestamp,
    });

    try {
      final pointRules = await loadPointRules();
      final exactScorePoints = (pointRules['exactPrediction'] ?? 50).toInt();
      final firstScorerPoints = (pointRules['firstScorer'] ?? 30).toInt();

      final predsSnap = await firestore
          .collection('predictions')
          .where('matchId', isEqualTo: matchId)
          .get();

      final normalizedOfficialScorer = firstScorer
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ');

      for (final doc in predsSnap.docs) {
        final data = doc.data();
        final rewarded = data['rewarded'] as bool? ?? false;
        if (rewarded) continue;

        final targetUid = data['userId'] as String? ?? '';
        if (targetUid.isEmpty) continue;

        final predHome = (data['homeScore'] as num? ?? -1).toInt();
        final predAway = (data['awayScore'] as num? ?? -1).toInt();
        final predScorer = (data['firstScorer'] as String? ?? '')
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), ' ');

        final exactMatch = predHome == homeScore && predAway == awayScore;
        final scorerMatch =
            (normalizedOfficialScorer.isNotEmpty &&
                predScorer.isNotEmpty &&
                normalizedOfficialScorer == predScorer) ||
            (homeScore == 0 &&
                awayScore == 0 &&
                (predScorer == 'no scorer' || predScorer.isEmpty));
        var points = 0;
        if (exactMatch) points += exactScorePoints;
        if (scorerMatch) points += firstScorerPoints;

        // Check if member for multiplier
        final userDoc = await firestore
            .collection('users')
            .doc(targetUid)
            .get();
        final isMember = userDoc.data()?['isYouTubeMember'] as bool? ?? false;
        if (isMember) points *= 2;

        if (points > 0) {
          await firestore.collection('users').doc(targetUid).update({
            'totalPoints': FieldValue.increment(points),
            'monthlyPoints': FieldValue.increment(points),
            'seasonPoints': FieldValue.increment(points),
            'loyaltyPoints': FieldValue.increment(points),
            'lastActivityAt': timestamp,
            'updatedAt': timestamp,
          });

          await firestore.collection('leaderboardEntries').doc(targetUid).set({
            'totalPoints': FieldValue.increment(points),
            'monthlyPoints': FieldValue.increment(points),
            'seasonPoints': FieldValue.increment(points),
            'updatedAt': timestamp,
          }, SetOptions(merge: true));

          await firestore.collection('pointTransactions').add({
            'userId': targetUid,
            'type': 'prediction_win',
            'points': points,
            'description': 'Prediction result: match $matchId (+$points pts)',
            'sourceId': matchId,
            'createdAt': timestamp,
          });
        }

        await doc.reference.update({
          'rewarded': true,
          'pointsAwarded': points,
          'seenResult': false,
          'updatedAt': timestamp,
        });
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>> autoFetchAndSettleMatch(String matchId) async {
    final matchDoc = await firestore.collection('matches').doc(matchId).get();
    if (!matchDoc.exists) throw StateError('Match not found.');
    final match = MatchEvent.fromDocument(matchDoc);

    final finished = await apiRepo.fetchFootballRecentMatches();
    MatchEvent? target;
    for (final m in finished) {
      if (m.id == match.id ||
          (m.homeTeam.toLowerCase().contains(match.homeTeam.toLowerCase()) &&
              m.awayTeam.toLowerCase().contains(
                match.awayTeam.toLowerCase(),
              ))) {
        target = m;
        break;
      }
    }

    if (target == null ||
        target.homeScore == null ||
        target.awayScore == null) {
      throw StateError(
        'API has not published the final score for this match yet.',
      );
    }

    List<MatchTimelineEvent> timeline = target.timeline;
    if (timeline.isEmpty && target.id.startsWith('external_')) {
      try {
        timeline = await apiRepo
            .fetchMatchDetails(target.id)
            .then((details) => details.timeline);
      } catch (_) {}
    }

    String firstScorer = target.firstScorer.trim();
    if (firstScorer.isEmpty && timeline.isNotEmpty) {
      final firstGoal = timeline
          .where(
            (t) =>
                t.type.toLowerCase().contains('goal') ||
                t.type.toLowerCase().contains('penalty'),
          )
          .firstOrNull;
      if (firstGoal != null) firstScorer = firstGoal.player;
    }
    if (firstScorer.isEmpty) {
      firstScorer = (target.homeScore == 0 && target.awayScore == 0)
          ? 'No scorer'
          : 'Unknown';
    }

    await publishMatchResult(
      matchId: matchId,
      homeScore: target.homeScore!,
      awayScore: target.awayScore!,
      firstScorer: firstScorer,
    );

    return {
      'homeScore': target.homeScore,
      'awayScore': target.awayScore,
      'firstScorer': firstScorer,
    };
  }

  Future<void> setMatchStatus({
    required String matchId,
    required String status,
  }) => firestore.collection('matches').doc(matchId).update({
    'status': status,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> updatePointRules({
    required int exactPrediction,
    required int firstScorer,
    required int winnerOutcome,
    required int videoQuestion,
    required int playerCard,
    required double memberMultiplier,
  }) => firestore.collection('platformSettings').doc('points').set({
    'exactPrediction': exactPrediction,
    'firstScorer': firstScorer,
    'winnerOutcome': winnerOutcome,
    'videoQuestion': videoQuestion,
    'playerCard': playerCard,
    'memberMultiplier': memberMultiplier,
    'updatedBy': auth.currentUser!.uid,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<String> uploadAnnouncementImage(XFile file) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Sign in before uploading an announcement image.');
    }
    final length = await file.length();
    if (length <= 0 || length > 8 * 1024 * 1024) {
      throw ArgumentError('Choose an image smaller than 8 MB.');
    }
    final contentType = supportedAdminImageContentType(
      fileName: file.name,
      mimeType: file.mimeType,
    );
    if (contentType == null) {
      throw ArgumentError('Use a JPG, PNG, WebP, or GIF image.');
    }
    return apiRepo.uploadAdminImage(
      purpose: 'announcement',
      bytes: await file.readAsBytes(),
      fileName: file.name,
    );
  }

  Future<void> _call(String name, Map<String, Object?> data) async {
    await functions.httpsCallable(name).call<Map<String, dynamic>>(data);
  }

  // ── Media upload helpers ──────────────────────────────────────────────

  Future<String> uploadAvatar(XFile file) async {
    return _uploadImageFile(file, 'avatar');
  }

  Future<String> uploadPostImage(XFile file) async {
    return _uploadImageFile(file, 'post');
  }

  Future<String> uploadChallengeImage(XFile file) async {
    return _uploadImageFile(file, 'challenge');
  }

  Future<String> uploadPlayerCardImage(XFile file) async {
    return _uploadImageFile(file, 'player_card');
  }

  Future<String> _uploadImageFile(XFile file, String purpose) async {
    final user = auth.currentUser;
    if (user == null) throw StateError('Sign in before uploading an image.');
    final length = await file.length();
    if (length <= 0 || length > 8 * 1024 * 1024) {
      throw ArgumentError('Choose an image smaller than 8 MB.');
    }
    final bytes = await file.readAsBytes();
    final contentType = _adminImageContentType(file.name, file.mimeType);
    if (contentType == null) {
      throw ArgumentError('Select a valid JPEG, PNG, WEBP, or GIF image.');
    }
    if (purpose == 'avatar') {
      return apiRepo.uploadAvatar(bytes: bytes, fileName: file.name);
    }
    return apiRepo.uploadAdminImage(
      purpose: purpose,
      bytes: bytes,
      fileName: file.name,
    );
  }

  static String? _adminImageContentType(String fileName, String? mimeType) {
    const allowed = <String>{
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/gif',
    };
    final m = mimeType?.trim().toLowerCase();
    if (m != null && allowed.contains(m)) return m;
    final ext = fileName.toLowerCase().split('.').last;
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => null,
    };
  }

  // ── Account management ────────────────────────────────────────────────

  Future<void> deleteAccount() async {
    final user = auth.currentUser;
    if (user == null) return;
    try {
      await _call('deleteAccountData', {});
    } catch (_) {}
    await user.delete();
  }

  // ── Achievements & Levels & Rewards CRUD stubs ────────────────────────

  Future<Map<String, num>> loadPointRules() async {
    final defaults = <String, num>{
      'exactPrediction': PointRuleDefaults.exactPrediction,
      'firstScorer': PointRuleDefaults.firstScorer,
      'winnerOutcome': PointRuleDefaults.winnerOutcome,
      'videoQuestion': PointRuleDefaults.videoQuestion,
      'playerCard': PointRuleDefaults.playerCard,
      'memberMultiplier': PointRuleDefaults.memberMultiplier,
    };

    try {
      final doc = await firestore
          .collection('platformSettings')
          .doc('points')
          .get();
      final data = doc.data();
      if (doc.exists && data != null) {
        return {
          'exactPrediction':
              (data['exactPrediction'] as num?) ?? defaults['exactPrediction']!,
          'firstScorer':
              (data['firstScorer'] as num?) ?? defaults['firstScorer']!,
          'winnerOutcome':
              (data['winnerOutcome'] as num?) ?? defaults['winnerOutcome']!,
          'videoQuestion':
              (data['videoQuestion'] as num?) ?? defaults['videoQuestion']!,
          'playerCard': (data['playerCard'] as num?) ?? defaults['playerCard']!,
          'memberMultiplier':
              (data['memberMultiplier'] as num?) ??
              defaults['memberMultiplier']!,
        };
      }
    } catch (error) {
      // The PostgreSQL API remains usable while a newly migrated Firebase
      // project is waiting for its Firestore database to be provisioned.
      // Point rules have safe product defaults, so this optional remote
      // override must never block sign-in, profile loading, or predictions.
      if (kDebugMode) {
        debugPrint('[PointRules] Using defaults: $error');
      }
    }
    return defaults;
  }

  Stream<List<SavedPrediction>> watchPredictionHistory(String uid) {
    if (uid.isEmpty || uid == 'guest') {
      return Stream.value(const <SavedPrediction>[]);
    }
    final local = _localPredictionsByUid.putIfAbsent(
      uid,
      () => <String, SavedPrediction>{},
    );
    return _predictionResources
        .putIfAbsent(
          uid,
          () => _ReplayResource<List<SavedPrediction>>(
            maxAge: const Duration(minutes: 5),
            initialValue: _predictionSnapshot(uid),
            hasInitialValue: local.isNotEmpty,
            load: () async {
              final revisionBefore = _predictionMutationRevision[uid] ?? 0;
              final saved = await apiRepo.fetchMyPredictions();
              final current = _localPredictionsByUid.putIfAbsent(
                uid,
                () => <String, SavedPrediction>{},
              );
              final fromServer = <String, SavedPrediction>{
                for (final item in saved) item.matchId: item,
              };
              if ((_predictionMutationRevision[uid] ?? 0) == revisionBefore) {
                current
                  ..clear()
                  ..addAll(fromServer);
              } else {
                // A POST committed while this GET was in flight. Merge the
                // response but let the newer local commit win so the card can
                // never flash back to MAKE PREDICTION.
                final newerLocal = Map<String, SavedPrediction>.from(current);
                current
                  ..clear()
                  ..addAll(fromServer)
                  ..addAll(newerLocal);
              }
              return _predictionSnapshot(uid);
            },
          ),
        )
        .stream;
  }

  List<SavedPrediction> _predictionSnapshot(String uid) =>
      (_localPredictionsByUid[uid]?.values.toList() ?? <SavedPrediction>[])
        ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));

  Stream<List<ExclusiveVideo>> watchExclusiveVideos() =>
      (_exclusiveVideosResource ??= _ReplayResource<List<ExclusiveVideo>>(
        maxAge: const Duration(minutes: 5),
        load: apiRepo.fetchExclusiveVideos,
      )).stream;

  Future<void> createExclusiveVideo({
    required String youtubeId,
    required String title,
    String? description,
    String? thumbnailUrl,
    DateTime? publishedAt,
    bool isUnlisted = true,
    bool memberOnly = false,
  }) => apiRepo.createExclusiveVideo(
    youtubeId: youtubeId,
    title: title,
    description: description,
    thumbnailUrl: thumbnailUrl,
    publishedAt: publishedAt,
    isUnlisted: isUnlisted,
    memberOnly: memberOnly,
  );

  Future<void> deleteExclusiveVideo(String id) =>
      apiRepo.deleteExclusiveVideo(id);

  Stream<LeaderboardSnapshot> watchLeaderboardView({
    required LeaderboardPeriod period,
    String? seasonId,
  }) {
    final key = '${period.name}:${seasonId ?? ''}';
    return _leaderboardViewResources
        .putIfAbsent(
          key,
          () => _ReplayResource<LeaderboardSnapshot>(
            maxAge: const Duration(minutes: 2),
            load: () => _fetchLeaderboardSnapshot(period),
          ),
        )
        .stream;
  }

  Future<LeaderboardSnapshot> _fetchLeaderboardSnapshot(
    LeaderboardPeriod period,
  ) async {
    final uid = auth.currentUser?.uid ?? '';
    final list = await apiRepo.fetchTopLeaderboard(
      period: period == LeaderboardPeriod.monthly ? 'monthly' : 'season',
    );
    final entries = <RankedLeaderboardEntry>[];
    for (var i = 0; i < list.length; i++) {
      final entry = list[i];
      entries.add(
        RankedLeaderboardEntry(
          entry: entry,
          rank: i + 1,
          points: period == LeaderboardPeriod.monthly
              ? entry.monthlyPoints
              : entry.seasonPoints,
        ),
      );
    }
    final currentUser = entries.where((e) => e.entry.uid == uid).firstOrNull;
    return LeaderboardSnapshot(
      entries: entries,
      currentUser: currentUser,
      totalPlayers: entries.length,
      seasons: const [],
      activeSeasonId: null,
    );
  }

  Stream<List<AbuAchievementProgress>> watchAchievements(String uid) =>
      firestore
          .collection('achievementDefinitions')
          .where('enabled', isEqualTo: true)
          .orderBy('sortOrder')
          .snapshots()
          .map(
            (s) => s.docs.map((doc) {
              final ach = AbuAchievement.fromDocument(doc);
              return AbuAchievementProgress(
                achievement: ach,
                achievementId: ach.id,
                current: 0,
                target: ach.requirementTarget,
                unlocked: false,
              );
            }).toList(),
          )
          .handleError((_) => const <AbuAchievementProgress>[]);

  Stream<List<AbuAchievement>> watchManagedAchievements() => firestore
      .collection('achievementDefinitions')
      .orderBy('sortOrder')
      .snapshots()
      .map((s) => s.docs.map(AbuAchievement.fromDocument).toList())
      .handleError((_) => const <AbuAchievement>[]);

  Future<void> setAchievementEnabled(String id, bool enabled) => firestore
      .collection('achievementDefinitions')
      .doc(id)
      .update({'enabled': enabled});

  Future<void> saveAchievement(AbuAchievement model) async {
    final data = model.toMap();
    if (model.id.isEmpty) {
      await firestore.collection('achievementDefinitions').add(data);
    } else {
      await firestore
          .collection('achievementDefinitions')
          .doc(model.id)
          .set(data, SetOptions(merge: true));
    }
  }

  Future<Map<String, dynamic>> claimAchievement(String id) async {
    final result = await functions
        .httpsCallable('claimAchievement')
        .call<Map<String, dynamic>>({'achievementId': id});
    return result.data;
  }

  Stream<List<AbuLevel>> watchLevels() => firestore
      .collection('levelDefinitions')
      .where('enabled', isEqualTo: true)
      .orderBy('sortOrder')
      .snapshots()
      .map((s) => s.docs.map(AbuLevel.fromDocument).toList())
      .handleError((_) => const <AbuLevel>[]);

  Stream<List<AbuLevel>> watchManagedLevels() => firestore
      .collection('levelDefinitions')
      .orderBy('sortOrder')
      .snapshots()
      .map((s) => s.docs.map(AbuLevel.fromDocument).toList())
      .handleError((_) => const <AbuLevel>[]);

  Future<void> setLevelEnabled(String id, bool enabled) => firestore
      .collection('levelDefinitions')
      .doc(id)
      .update({'enabled': enabled});

  Future<void> saveLevel(AbuLevel model) async {
    final data = model.toMap();
    if (model.id.isEmpty) {
      await firestore.collection('levelDefinitions').add(data);
    } else {
      await firestore
          .collection('levelDefinitions')
          .doc(model.id)
          .set(data, SetOptions(merge: true));
    }
  }

  Stream<List<AbuLoyaltyReward>> watchRewards() => firestore
      .collection('loyaltyRewards')
      .where('enabled', isEqualTo: true)
      .snapshots()
      .map((s) => s.docs.map(AbuLoyaltyReward.fromDocument).toList())
      .handleError((_) => const <AbuLoyaltyReward>[]);

  Stream<List<AbuLoyaltyReward>> watchManagedRewards() => firestore
      .collection('loyaltyRewards')
      .snapshots()
      .map((s) => s.docs.map(AbuLoyaltyReward.fromDocument).toList())
      .handleError((_) => const <AbuLoyaltyReward>[]);

  Future<void> setRewardEnabled(String id, bool enabled) => firestore
      .collection('loyaltyRewards')
      .doc(id)
      .update({'enabled': enabled});

  Future<void> saveReward(AbuLoyaltyReward model) async {
    final data = model.toMap();
    if (model.id.isEmpty) {
      await firestore.collection('loyaltyRewards').add(data);
    } else {
      await firestore
          .collection('loyaltyRewards')
          .doc(model.id)
          .set(data, SetOptions(merge: true));
    }
  }

  Stream<List<AbuRewardRedemption>> watchRedemptions(String uid) => firestore
      .collection('loyaltyRedemptions')
      .where('userId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(AbuRewardRedemption.fromDocument).toList())
      .handleError((_) => const <AbuRewardRedemption>[]);

  Future<void> redeemReward(String id) =>
      _call('redeemReward', {'rewardId': id});

  Future<void> updateRedemptionStatus(
    String id,
    String status, {
    String? note,
  }) => firestore.collection('loyaltyRedemptions').doc(id).update({
    'status': status,
    if (note != null && note.isNotEmpty) 'adminNote': note,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  // ── Player Cards ──────────────────────────────────────────────────────

  Stream<List<AbuPlayerCard>> watchPlayerCards(String uid) => firestore
      .collection('playerCards')
      .orderBy('availableFrom', descending: true)
      .limit(30)
      .snapshots()
      .map((s) => s.docs.map(AbuPlayerCard.fromDocument).toList())
      .handleError((_) => const <AbuPlayerCard>[]);

  Stream<List<AbuPlayerCard>> watchManagedPlayerCards() => firestore
      .collection('playerCards')
      .orderBy('availableFrom', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(AbuPlayerCard.fromDocument).toList())
      .handleError((_) => const <AbuPlayerCard>[]);

  Future<void> setPlayerCardEnabled(String id, bool enabled) =>
      firestore.collection('playerCards').doc(id).update({'enabled': enabled});

  Future<void> savePlayerCard(AbuPlayerCard model) async {
    final data = model.toMap();
    if (model.id.isEmpty) {
      await firestore.collection('playerCards').add(data);
    } else {
      await firestore
          .collection('playerCards')
          .doc(model.id)
          .set(data, SetOptions(merge: true));
    }
  }

  // ── Advanced Challenges ───────────────────────────────────────────────

  Future<Map<String, dynamic>> submitChallengeAnswers({
    required AbuChallenge challenge,
    required Map<String, String> answers,
  }) async {
    final result = await functions
        .httpsCallable('submitChallengeAnswers')
        .call<Map<String, dynamic>>({
          'challengeId': challenge.id,
          'kind': challenge.kind,
          'answers': answers,
        });
    return result.data;
  }

  Future<void> createAdvancedChallenge({
    required String kind,
    required String title,
    String description = '',
    String videoUrl = '',
    String imageUrl = '',
    int rewardPoints = 0,
    required DateTime availableFrom,
    required DateTime availableUntil,
    String status = 'open',
    int maximumAttempts = 1,
    bool memberOnly = false,
    bool notifyOnLive = false,
    List<dynamic> questions = const [],
  }) async {
    final collection = kind == 'playerCard' ? 'playerCards' : 'videoQuestions';
    final docRef = firestore.collection(collection).doc();
    final uid = auth.currentUser?.uid ?? 'admin';
    final primaryAnswer = questions.isNotEmpty
        ? (questions.first is Map
              ? (questions.first as Map)['answer']?.toString() ?? ''
              : (questions.first as dynamic).answer?.toString() ?? '')
        : '';
    final formattedQuestions = questions.map((q) {
      if (q is Map) return q;
      try {
        return (q as dynamic).toMap();
      } catch (_) {
        return <String, dynamic>{};
      }
    }).toList();

    final batch = firestore.batch();
    batch.set(docRef, {
      'kind': kind,
      'title': title.trim(),
      'description': description.trim(),
      'videoUrl': videoUrl.trim(),
      'imageUrl': imageUrl.trim(),
      'rewardPoints': rewardPoints,
      'availableFrom': Timestamp.fromDate(availableFrom),
      'availableUntil': Timestamp.fromDate(availableUntil),
      'status': status,
      'maximumAttempts': maximumAttempts,
      'memberOnly': memberOnly,
      'notifyOnLive': notifyOnLive,
      'questions': formattedQuestions,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(docRef.collection('private').doc('answer'), {
      'normalizedAnswer': normalizeChallengeAnswer(primaryAnswer),
      'answers': questions.map((q) {
        if (q is Map) {
          return normalizeChallengeAnswer(q['answer']?.toString() ?? '');
        }
        try {
          return normalizeChallengeAnswer(
            (q as dynamic).answer?.toString() ?? '',
          );
        } catch (_) {
          return '';
        }
      }).toList(),
    });
    await batch.commit();
  }

  String normalizeChallengeAnswer(String text) {
    return text
        .trim()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
  }

  // ── Admin Point Adjustments ───────────────────────────────────────────

  String newAdminPointAdjustmentKey() =>
      firestore.collection('adminPointAdjustments').doc().id;

  Stream<List<AdminPointAdjustment>> watchAdminPointAdjustments() =>
      (_adminPointAdjustmentsResource ??=
              _ReplayResource<List<AdminPointAdjustment>>(
                maxAge: const Duration(minutes: 2),
                load: apiRepo.fetchAdminPointAdjustments,
              ))
          .stream;

  Future<AdminPointAdjustmentResult> adjustUserPoints({
    required String targetUserId,
    required int delta,
    required String reason,
    required String idempotencyKey,
  }) async {
    final result = await apiRepo.adjustAdminUserPoints(
      userId: targetUserId,
      delta: delta,
      reason: reason,
      idempotencyKey: idempotencyKey,
    );
    await _adminPointAdjustmentsResource?.refresh(force: true);
    return result;
  }

  // ── YouTube Member Verification ─────────────────────────────────────────

  Future<bool> verifyYouTubeMembership(String uid) async {
    if (uid.isEmpty || uid == 'guest') return false;
    try {
      final doc = await firestore.collection('users').doc(uid).get();
      final currentMember = doc.data()?['isYouTubeMember'] == true;
      if (currentMember) return true;

      if (!kIsWeb) {
        if (!_googleInitialized) {
          await GoogleSignIn.instance.initialize();
          _googleInitialized = true;
        }
        final account = await GoogleSignIn.instance.authenticate();
        final idToken = account.authentication.idToken ?? '';
        bool verified = false;
        if (idToken.isNotEmpty) {
          verified = await externalContent.checkYouTubeMembership(idToken);
        }
        if (verified) {
          await setUserYouTubeMembership(uid: uid, isMember: true);
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> setUserYouTubeMembership({
    required String uid,
    required bool isMember,
  }) async {
    await firestore.collection('users').doc(uid).set({
      'isYouTubeMember': isMember,
      'youtubeMembershipVerifiedAt': isMember
          ? FieldValue.serverTimestamp()
          : null,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setAdminYouTubeMembership({
    required String uid,
    required bool isMember,
  }) => apiRepo.setAdminYouTubeMembership(userId: uid, isMember: isMember);

  // ── Games Arena Visibility Toggle ───────────────────────────────────────

  Stream<bool> watchGamesEnabled() => firestore
      .collection('system')
      .doc('config')
      .snapshots()
      .map((doc) => doc.data()?['gamesEnabled'] as bool? ?? false)
      .handleError((_) => false);

  Future<void> setGamesEnabled(bool enabled) async {
    await firestore.collection('system').doc('config').set({
      'gamesEnabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ── Dynamic Football Team Search ────────────────────────────────────────

  Future<List<FootballTeamAsset>> searchTeams(String query) =>
      apiRepo.searchFootballTeams(query);
}

String productionErrorMessage(Object error) {
  if (error is AbuApiException) {
    return switch (error.statusCode) {
      0 =>
        'Cannot reach the Abu 3meer server (${AbuApiClient.defaultBaseUrl}). Check the Cloudflare Tunnel and try again.',
      400 => error.message,
      401 => 'Your session expired. Sign in again and retry.',
      403 => 'Your account is not allowed to perform this action.',
      404 => error.message,
      409 => error.message,
      413 => 'That image is too large. Choose an image smaller than 8 MB.',
      429 => 'Too many requests. Wait a moment and try again.',
      _ => error.message,
    };
  }
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'invalid-credential' => 'The email or password is incorrect.',
      'email-already-in-use' => 'An account already uses this email.',
      'weak-password' => 'Use a stronger password with at least 8 characters.',
      'invalid-email' => 'Enter a valid email address.',
      'user-disabled' => 'This account has been suspended. Contact support.',
      'popup-closed-by-user' || 'canceled' => 'Google sign-in was cancelled.',
      'network-request-failed' =>
        'Check your internet connection and try again.',
      _ => error.message ?? 'Authentication failed. Please try again.',
    };
  }
  if (error is GoogleSignInException) {
    return switch (error.code) {
      GoogleSignInExceptionCode.canceled => 'Google sign-in was cancelled.',
      GoogleSignInExceptionCode.interrupted =>
        'Google sign-in was interrupted. Please try again.',
      GoogleSignInExceptionCode.clientConfigurationError ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        'Google sign-in is not configured correctly for this app build.',
      GoogleSignInExceptionCode.uiUnavailable =>
        'Google sign-in could not open. Close the app and try again.',
      GoogleSignInExceptionCode.userMismatch =>
        'The selected Google account does not match the current session.',
      _ => error.description ?? 'Google sign-in failed. Please try again.',
    };
  }
  if (error is FirebaseFunctionsException) {
    return error.message ?? 'The server could not complete this request.';
  }
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' =>
        'Firebase rejected this request. Refresh and try again.',
      'unavailable' => 'The service is temporarily unavailable. Try again.',
      _ => error.message ?? 'Firebase could not complete this request.',
    };
  }
  if (error is ArgumentError || error is StateError) {
    return error.toString().replaceFirst(
      RegExp(r'^(Invalid argument|Bad state): '),
      '',
    );
  }
  return 'Something went wrong. Please try again.';
}

Stream<List<T>> refreshAtScheduleBoundaries<T>(
  Stream<List<T>> source,
  Iterable<DateTime?> Function(T item) boundaries,
) {
  late StreamController<List<T>> controller;
  StreamSubscription<List<T>>? subscription;
  Timer? timer;
  List<T>? latest;
  var sourceDone = false;

  void closeIfFinished() {
    if (sourceDone && timer == null && !controller.isClosed) {
      controller.close();
    }
  }

  void scheduleNext() {
    timer?.cancel();
    timer = null;
    if (latest == null) {
      closeIfFinished();
      return;
    }
    final now = DateTime.now();
    DateTime? nextBoundary;
    for (final item in latest!) {
      for (final b in boundaries(item)) {
        if (b != null && b.isAfter(now)) {
          if (nextBoundary == null || b.isBefore(nextBoundary)) {
            nextBoundary = b;
          }
        }
      }
    }
    if (nextBoundary != null) {
      final delay = nextBoundary.difference(now);
      timer = Timer(
        delay <= Duration.zero ? const Duration(milliseconds: 1) : delay,
        () {
          timer = null;
          if (!controller.isClosed && latest != null) {
            controller.add(latest!);
            scheduleNext();
          }
        },
      );
    } else {
      closeIfFinished();
    }
  }

  controller = StreamController<List<T>>(
    onListen: () {
      subscription = source.listen(
        (items) {
          latest = items;
          controller.add(items);
          scheduleNext();
        },
        onError: controller.addError,
        onDone: () {
          sourceDone = true;
          closeIfFinished();
        },
      );
    },
    onCancel: () {
      timer?.cancel();
      subscription?.cancel();
    },
  );

  return controller.stream;
}
