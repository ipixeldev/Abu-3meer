import 'point_rules.dart';

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_production_repository.dart';
import 'api_client.dart';
import 'external_content_service.dart';
import 'models.dart';
import 'youtube_membership_check.dart';
import 'notification_service.dart';

const List<String> youtubeMembershipGoogleScopes = <String>[
  'https://www.googleapis.com/auth/youtube.readonly',
];

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
int leaderboardRankForProfile(
  Iterable<RankedLeaderboardEntry> entries,
  AbuUserProfile profile,
) {
  final identifiers = <String>{
    profile.uid.trim().toLowerCase(),
    profile.username.trim().toLowerCase(),
  }..removeWhere((value) => value.isEmpty);
  for (final ranked in entries) {
    final entryIdentifiers = <String>{
      ranked.entry.uid.trim().toLowerCase(),
      ranked.entry.username.trim().toLowerCase(),
    }..removeWhere((value) => value.isEmpty);
    if (entryIdentifiers.any(identifiers.contains)) return ranked.rank;
  }
  return 0;
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
  // Provider and manually managed names can include suffixes or diacritics,
  // but the same clubs can meet repeatedly. Team names alone must never merge
  // a later fixture with an earlier prediction/result.
  final kickoffDifference = left.kickoffAt.difference(right.kickoffAt).abs();
  return sameHome &&
      sameAway &&
      kickoffDifference <= const Duration(minutes: 5);
}

@visibleForTesting
bool footballTimelineEventIsScoredGoal(MatchTimelineEvent event) {
  final type = event.type
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return const {'goal', 'penalty_goal', 'own_goal'}.contains(type);
}

int _footballTimelineMinute(MatchTimelineEvent event) {
  final parts = event.minute.trim().split('+');
  final regulation =
      int.tryParse(parts.first.replaceAll(RegExp(r'\D'), '')) ?? 1 << 20;
  final added = parts.length > 1
      ? int.tryParse(parts[1].replaceAll(RegExp(r'\D'), '')) ?? 0
      : 0;
  return regulation * 100 + added;
}

@visibleForTesting
String firstScorerFromFootballTimeline(List<MatchTimelineEvent> timeline) {
  final goals = timeline.where(footballTimelineEventIsScoredGoal).toList()
    ..sort(
      (left, right) =>
          _footballTimelineMinute(left)
              .compareTo(_footballTimelineMinute(right)),
    );
  return goals.firstOrNull?.player.trim() ?? '';
}

String _providerFootballIdentity(MatchEvent event) {
  final providerId = event.providerMatchId.trim().toLowerCase();
  return providerId.isNotEmpty ? providerId : event.id.trim().toLowerCase();
}

/// Provider replicas can briefly regress a completed/live fixture to an
/// earlier `upcoming` envelope. Keep official result state monotonic while
/// still accepting a newer terminal correction from the provider.
@visibleForTesting
MatchEvent retainPublishedFootballResult(
  MatchEvent previous,
  MatchEvent incoming,
) {
  final previousStatus = previous.status.trim().toLowerCase();
  final incomingStatus = incoming.status.trim().toLowerCase();
  final previousCompleted = const {
    'completed',
    'finished',
  }.contains(previousStatus);
  final incomingCompleted = const {
    'completed',
    'finished',
  }.contains(incomingStatus);
  final regressedFromCompleted =
      previousCompleted &&
      !incomingCompleted &&
      !const {'cancelled', 'postponed'}.contains(incomingStatus);
  final regressedFromLive =
      previousStatus == 'live' && incomingStatus == 'upcoming';
  if (!regressedFromCompleted && !regressedFromLive) return incoming;

  return incoming.copyWith(
    status: previous.status,
    homeScore: previous.homeScore,
    awayScore: previous.awayScore,
    firstScorer: previous.firstScorer.isNotEmpty
        ? previous.firstScorer
        : incoming.firstScorer,
  );
}

/// Applies Abu 3meer's prediction controls to a provider fixture without
/// discarding the provider identity needed by the match centre.
@visibleForTesting
MatchEvent mergeManagedFootballMatch(MatchEvent provider, MatchEvent managed) {
  final providerMatchId = provider.providerMatchId.trim().isNotEmpty
      ? provider.providerMatchId
      : provider.id;
  final providerStatus = provider.status.toLowerCase();
  final providerHasResult =
      provider.homeScore != null ||
      provider.awayScore != null ||
      const {'live', 'completed', 'finished'}.contains(providerStatus);
  return provider.copyWith(
    id: managed.id,
    providerMatchId: providerMatchId,
    status: providerHasResult ? provider.status : managed.status,
    homeScore: provider.homeScore ?? managed.homeScore,
    awayScore: provider.awayScore ?? managed.awayScore,
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

/// Uses a small, provider-only replay window during a genuine network error.
/// A successful empty response remains authoritative, while stale managed
/// matches and months-old fixtures can never live forever in the app cache.
@visibleForTesting
List<MatchEvent> retainedProviderMatchesAfterFetchFailure(
  List<MatchEvent> cached, {
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final earliest = current.subtract(const Duration(days: 7));
  final latest = current.add(const Duration(days: 14));
  return cached.where((event) {
    final providerId = event.providerMatchId.trim().toLowerCase();
    final eventId = event.id.trim().toLowerCase();
    final providerBacked =
        providerId.startsWith('external_') || eventId.startsWith('external_');
    return providerBacked &&
        !event.kickoffAt.isBefore(earliest) &&
        !event.kickoffAt.isAfter(latest);
  }).toList()..sort((a, b) => a.kickoffAt.compareTo(b.kickoffAt));
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

String effectiveChallengePrompt({
  required String title,
  required String prompt,
}) {
  final explicitPrompt = prompt.trim();
  return explicitPrompt.isEmpty ? title.trim() : explicitPrompt;
}

/// Accepts a YouTube watch/share/embed/short URL or a canonical video ID.
/// YouTube video IDs are exactly 11 URL-safe characters; arbitrary hostnames
/// must never be stored as IDs (for example the old `iamr.dev` test row).
String? extractYoutubeVideoId(String raw) {
  final value = raw.trim();
  final idPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');
  if (idPattern.hasMatch(value)) return value;

  Uri? uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) {
    uri = Uri.tryParse('https://$value');
  }
  if (uri == null || uri.host.isEmpty) return null;
  final host = uri.host.toLowerCase();
  String? candidate;
  if (host == 'youtu.be' || host == 'www.youtu.be') {
    if (uri.pathSegments.isNotEmpty) candidate = uri.pathSegments.first;
  } else if (host == 'youtube.com' ||
      host == 'www.youtube.com' ||
      host == 'm.youtube.com' ||
      host == 'music.youtube.com' ||
      host == 'youtube-nocookie.com' ||
      host == 'www.youtube-nocookie.com') {
    candidate = uri.queryParameters['v'];
    if (candidate == null && uri.pathSegments.length >= 2) {
      if (const {'shorts', 'embed', 'live'}.contains(uri.pathSegments.first)) {
        candidate = uri.pathSegments[1];
      }
    }
  }
  final normalized = candidate?.trim() ?? '';
  return idPattern.hasMatch(normalized) ? normalized : null;
}

@visibleForTesting
Future<void> runMutationAndForceRefresh({
  required Future<void> Function() mutation,
  required Iterable<Future<void> Function()> refreshers,
}) async {
  await mutation();
  await Future.wait(refreshers.map((refresh) => refresh()));
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
  Completer<void>? _queuedForcedRefresh;
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
    // The stream receives the initial error through `_updates`. Consume the
    // returned Future here so propagating refresh failures to explicit admin
    // mutations does not also create an unhandled asynchronous exception.
    unawaited(refresh().catchError((Object _) {}));
    listener.onCancel = subscription.cancel;
  }, isBroadcast: true);

  Future<void> refresh({bool force = false}) {
    if (_disposed) return Future<void>.value();
    final running = _inFlight;
    if (running != null) {
      if (!force) return running;

      // A mutation may finish while an older GET is still in flight. Joining
      // that request would let its pre-mutation response overwrite the new
      // content and make a successful save appear to have vanished. Coalesce
      // concurrent forced refreshes, but always run one new load immediately
      // after the older request completes.
      final queued = _queuedForcedRefresh;
      if (queued != null) return queued.future;
      final completer = Completer<void>();
      _queuedForcedRefresh = completer;
      return completer.future;
    }
    final loadedAt = _loadedAt;
    if (!force &&
        _hasValue &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) < maxAge) {
      return Future<void>.value();
    }

    return _startLoad();
  }

  Future<void> _startLoad() {
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
        // Still propagate the failure to an explicit mutation/refresh caller
        // so Admin Studio cannot report "published" while showing stale data.
        if (!_hasValue) _updates.addError(error, stackTrace);
        Error.throwWithStackTrace(error, stackTrace);
      } finally {
        if (identical(_inFlight, operation)) _inFlight = null;
        _startQueuedForcedRefresh();
      }
    }();
    _inFlight = operation;
    return operation;
  }

  void _startQueuedForcedRefresh() {
    final queued = _queuedForcedRefresh;
    if (queued == null) return;

    // Detach this waiter before starting the next load. A third mutation that
    // arrives during that load gets a new waiter and therefore one more fresh
    // request; it can never accidentally await its own completer.
    _queuedForcedRefresh = null;
    if (_disposed) {
      if (!queued.isCompleted) queued.complete();
      return;
    }
    final next = _startLoad();
    unawaited(() async {
      try {
        await next;
        if (!queued.isCompleted) queued.complete();
      } catch (error, stackTrace) {
        if (!queued.isCompleted) queued.completeError(error, stackTrace);
      }
    }());
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
  static const String _pendingBroadcastKeyPreference =
      'admin_notification_pending_key_v1';
  static const String _pendingBroadcastSignaturePreference =
      'admin_notification_pending_signature_v1';
  static const String _pendingRewardRedemptionPreferencePrefix =
      'loyalty_redemption_pending_v1:';

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
  final Map<String, _ReplayResource<List<AbuChallenge>>> _challengeResources =
      {};
  _ReplayResource<List<AbuChallenge>>? _managedChallengesResource;
  final Map<String, _ReplayResource<List<AbuPlayerCard>>> _playerCardResources =
      {};
  _ReplayResource<List<AbuPlayerCard>>? _managedPlayerCardsResource;
  _ReplayResource<LaunchAnnouncement?>? _launchAnnouncementResource;
  _ReplayResource<List<AbuRewardRedemption>>? _adminRedemptionsResource;
  _ReplayResource<List<ExclusiveVideo>>? _exclusiveVideosResource;
  String? _exclusiveVideosResourceUserId;
  _ReplayResource<List<ExclusiveVideo>>? _managedExclusiveVideosResource;
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
  String? _pendingNotificationBroadcastKey;
  String? _pendingNotificationBroadcastSignature;
  final Map<String, String> _pendingRewardRedemptionKeys = {};
  Future<void> _notificationBroadcastMutationTail = Future<void>.value();

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
    if (uid != null && uid.isNotEmpty && uid != 'guest') {
      add(_challengeResources[uid]);
      add(_playerCardResources[uid]);
    }
    add(_managedChallengesResource);
    add(_managedPlayerCardsResource);
    add(_launchAnnouncementResource);
    add(_adminRedemptionsResource);
    add(_exclusiveVideosResource);
    add(_managedExclusiveVideosResource);
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
            apiRepo.fetchManagedMatches().timeout(const Duration(seconds: 8)),
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
    // Only an actual fetch error receives a bounded replay fallback. A
    // successful empty feed is authoritative and clears withdrawn fixtures.
    final fetchedBaseList = external == null
        ? retainedProviderMatchesAfterFetchFailure(_cachedMatches)
        : external!;
    final cachedByProviderId = <String, MatchEvent>{
      for (final cached in _cachedMatches)
        _providerFootballIdentity(cached): cached,
    };
    final baseList = fetchedBaseList
        .map((incoming) {
          final previous =
              cachedByProviderId[_providerFootballIdentity(incoming)];
          return previous == null
              ? incoming
              : retainPublishedFootballResult(previous, incoming);
        })
        .toList(growable: false);
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
      return await apiRepo.fetchLatestPublicVideo(forceRefresh: refresh);
    } catch (_) {
      try {
        // During a server rollout or a temporary API outage, fall back to the
        // public channel feed. The legacy Firestore override is intentionally
        // ignored because it could pin Home to an old hard-coded upload.
        return await externalContent.latestVideo(refresh: refresh);
      } catch (_) {
        // Never replace a failed live lookup with a fixed video. The Home UI
        // already has a retry state, which is more honest than showing stale
        // or unrelated content as the channel's latest upload.
        throw StateError('The latest public YouTube video is unavailable.');
      }
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

  Future<MatchDetails> fetchMatchDetails(
    MatchEvent event, {
    bool forceRefresh = false,
  }) async {
    try {
      final detailsMatchId = footballDetailsMatchId(event);
      final details = await apiRepo
          .fetchMatchDetails(detailsMatchId, forceRefresh: forceRefresh)
          .timeout(const Duration(seconds: 12));
      return details.timeline.isEmpty && event.timeline.isNotEmpty
          ? details.copyWith(timeline: event.timeline)
          : details;
    } catch (_) {
      // A bundled timeline may still be shown, but provider calls always stay
      // behind the shared server cache.
      if (event.timeline.isNotEmpty) {
        return MatchDetails(timeline: event.timeline);
      }
      rethrow;
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

  Future<UserLeaderboardRanks> fetchUserRanks(AbuUserProfile profile) async {
    if (profile.isGuest) return const UserLeaderboardRanks.unranked();

    if (auth.currentUser?.uid == profile.uid) {
      try {
        return await apiRepo.fetchMyLeaderboardRanks();
      } catch (_) {
        // Public snapshots below remain a useful fallback if the personalized
        // rank endpoint is briefly unavailable.
      }
    }

    try {
      final snapshots = await Future.wait<LeaderboardSnapshot>([
        apiRepo.fetchLeaderboardSnapshot(period: 'monthly'),
        apiRepo.fetchLeaderboardSnapshot(period: 'season'),
      ]);
      return UserLeaderboardRanks(
        currentMonth: leaderboardRankForProfile(snapshots[0].entries, profile),
        season: leaderboardRankForProfile(snapshots[1].entries, profile),
      );
    } catch (_) {
      return const UserLeaderboardRanks.unranked();
    }
  }

  Future<double> fetchUserAccuracy(String uid) async {
    if (uid.isEmpty || uid == 'guest') return 100.0;
    try {
      final predictions = await apiRepo.fetchMyPredictions();
      if (predictions.isEmpty) return 100.0;
      var correctCount = 0;
      var completedCount = 0;
      for (final prediction in predictions) {
        if (prediction.rewarded) {
          completedCount++;
          if (prediction.pointsAwarded > 0) correctCount++;
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

  Stream<List<AbuChallenge>> watchChallenges() {
    final uid = auth.currentUser?.uid ?? '';
    if (uid.isEmpty) return Stream.value(const <AbuChallenge>[]);
    return _challengeResources
        .putIfAbsent(
          uid,
          () => _ReplayResource<List<AbuChallenge>>(
            maxAge: const Duration(minutes: 2),
            load: apiRepo.fetchActiveChallenges,
          ),
        )
        .stream;
  }

  Future<void> refreshChallenges({bool force = true}) async {
    final uid = auth.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    watchChallenges();
    await _challengeResources[uid]?.refresh(force: force);
  }

  Stream<List<AbuChallenge>> watchManagedChallenges() =>
      (_managedChallengesResource ??= _ReplayResource<List<AbuChallenge>>(
        maxAge: const Duration(minutes: 2),
        load: apiRepo.fetchManagedChallenges,
      )).stream;

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

  _ReplayResource<LaunchAnnouncement?> get _launchAnnouncementFeed =>
      _launchAnnouncementResource ??= _ReplayResource<LaunchAnnouncement?>(
        maxAge: const Duration(minutes: 2),
        load: apiRepo.fetchLaunchAnnouncement,
      );

  Stream<LaunchAnnouncement?> watchLaunchAnnouncement() =>
      _launchAnnouncementFeed.stream;

  Future<void> refreshLaunchAnnouncement({bool force = false}) =>
      _launchAnnouncementFeed.refresh(force: force);

  /// The self-hosted PostgreSQL database is the account source of truth.
  /// Firestore may not contain a document for Firebase users created after the
  /// migration, which previously made every admin picker look empty.
  Future<List<AbuUserProfile>> fetchAdminUsers({String search = ''}) =>
      apiRepo.fetchAdminUsers(search: search);

  Future<List<LeaderboardSeason>> fetchAdminLeaderboardSeasons() =>
      apiRepo.fetchAdminLeaderboardSeasons();

  Future<LeaderboardSeason> saveAdminLeaderboardSeason({
    required String id,
    required String displayName,
    required DateTime startsAt,
    required DateTime endsAt,
    required String reason,
    required bool create,
  }) async {
    final season = await apiRepo.saveAdminLeaderboardSeason(
      id: id,
      displayName: displayName,
      startsAt: startsAt,
      endsAt: endsAt,
      reason: reason,
      create: create,
    );
    await Future.wait([
      for (final resource in _leaderboardResources.values)
        resource.refresh(force: true),
      for (final resource in _leaderboardViewResources.values)
        resource.refresh(force: true),
    ]);
    return season;
  }

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

  /// Links Google to the currently authenticated Firebase account instead of
  /// signing into (and potentially creating) a second account. This keeps the
  /// existing profile, points, predictions, and membership state intact.
  bool get canLinkGoogleAccount {
    final user = auth.currentUser;
    return user != null &&
        !user.providerData.any(
          (provider) => provider.providerId == GoogleAuthProvider.PROVIDER_ID,
        );
  }

  Future<void> linkGoogleAccount() async {
    final user = auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'unauthenticated',
        message: 'Sign in before linking Google.',
      );
    }
    if (!canLinkGoogleAccount) return;

    final provider = GoogleAuthProvider();
    if (kIsWeb) {
      await user.linkWithPopup(provider);
    } else {
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
      await user.linkWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
    }
    await user.reload();
    // Linking changes Firebase's provider identities. Force a new signed ID
    // token so the backend immediately recognizes the additional sign-in.
    await user.getIdToken(true);
    await refreshProfile(user.uid, force: true);
  }

  Future<void> signInWithApple() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      throw UnsupportedError('Sign in with Apple is available on iOS only.');
    }
    final provider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    await auth.signInWithProvider(provider);
  }

  Future<void> signOut() async {
    final uid = auth.currentUser?.uid;
    try {
      // The API call needs the current Firebase credential, so retire this
      // installation's active push token before ending the auth session.
      await NotificationService.instance.unregisterCurrentDevice();
    } catch (error) {
      // A network outage must not trap someone in their account. The stable
      // installation ID will retire the stale token on the next registration.
      debugPrint(
        '[Notifications] Device unregister before sign-out failed: $error',
      );
    }
    await auth.signOut();
    if (!kIsWeb && _googleInitialized) {
      await GoogleSignIn.instance.signOut();
    }
    await _clearSignedInAccountState(uid);
  }

  Future<void> _clearSignedInAccountState(String? uid) async {
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
    await _exclusiveVideosResource?.dispose();
    _exclusiveVideosResource = null;
    _exclusiveVideosResourceUserId = null;
    _pendingRewardRedemptionKeys.clear();
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
          lastCheckInDate: DateTime.now()
              .toUtc()
              .toIso8601String()
              .split('T')
              .first,
          lastActivityAt: DateTime.now().toUtc(),
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

  Future<void> _syncChallengeAward(Map<String, dynamic> result) async {
    if (result['correct'] != true) return;
    final uid = auth.currentUser?.uid;
    if (uid == null) return;

    final pointsAwarded = (result['pointsAwarded'] as num? ?? 0).toInt();
    // New servers explicitly distinguish a fresh award from an idempotent
    // replay. Optimistically update the header only for a confirmed fresh
    // award; older servers omit the flag and rely on the authoritative fetch.
    if (result['alreadyAwarded'] == false && pointsAwarded > 0) {
      final current = _localProfiles[uid];
      if (current != null) {
        final updated = current.copyWith(
          totalPoints: current.totalPoints + pointsAwarded,
          monthlyPoints: current.monthlyPoints + pointsAwarded,
          seasonPoints: current.seasonPoints + pointsAwarded,
          challengesCompleted: current.challengesCompleted + 1,
        );
        _localProfiles[uid] = updated;
        _profileResources[uid]?.emit(updated);
      }
    }

    try {
      await Future.wait([
        refreshProfile(uid, force: true),
        _pointHistoryResources[uid]?.refresh(force: true) ??
            Future<void>.value(),
        _playerCardResources[uid]?.refresh(force: true) ?? Future<void>.value(),
      ]);
    } catch (error) {
      // The atomic server transaction has already committed. Active resources
      // converge on the next refresh/resume if this follow-up request fails.
      debugPrint('[Challenges] Reward refresh deferred: $error');
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
      await _syncChallengeAward(res);
      await refreshChallenges(force: true);
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
    String playerCardId = '',
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
    await apiRepo.createAdminChallenge(
      kind: kind,
      title: title.trim(),
      description: description.trim(),
      videoUrl: videoUrl.trim(),
      imageUrl: '',
      rewardPoints: rewardPoints,
      availableFrom: availableFrom,
      availableUntil: availableUntil,
      status: status,
      maximumAttempts: maximumAttempts,
      memberOnly: memberOnly,
      notifyOnLive: notifyOnLive,
      playerCardId: playerCardId,
      questions: [
        {
          'id': 'main',
          'prompt': title.trim(),
          'type': 'text',
          'options': const <String>[],
          'correctAnswer': answer.trim(),
          'acceptedAnswers': const <String>[],
        },
      ],
    );
    await Future.wait([
      ..._challengeResources.values.map(
        (resource) => resource.refresh(force: true),
      ),
      _managedChallengesResource?.refresh(force: true) ?? Future<void>.value(),
    ]);
  }

  Future<void> setChallengeStatus({
    required AbuChallenge challenge,
    required String status,
  }) async {
    await apiRepo.setAdminChallengeStatus(
      challengeId: challenge.id,
      status: status,
    );
    await Future.wait([
      ..._challengeResources.values.map(
        (resource) => resource.refresh(force: true),
      ),
      _managedChallengesResource?.refresh(force: true) ?? Future<void>.value(),
    ]);
  }

  Future<void> deleteChallenge(AbuChallenge challenge) async {
    await apiRepo.deleteAdminChallenge(challenge.id);
    await Future.wait([
      ..._challengeResources.values.map(
        (resource) => resource.refresh(force: true),
      ),
      ..._playerCardResources.values.map(
        (resource) => resource.refresh(force: true),
      ),
      _managedChallengesResource?.refresh(force: true) ?? Future<void>.value(),
      _managedPlayerCardsResource?.refresh(force: true) ?? Future<void>.value(),
    ]);
  }

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
    final announcement = await apiRepo.saveAdminLaunchAnnouncement(
      enabled: enabled,
      title: title.trim(),
      body: body.trim(),
      imageUrl: normalizedImage,
      linkUrl: normalizedLink,
      buttonLabel: buttonLabel.trim(),
      frequency: frequency,
      startsAt: startsAt,
      endsAt: endsAt,
    );
    _launchAnnouncementResource?.emit(announcement);
  }

  Future<void> resetAnnouncement() async {
    await apiRepo.resetAdminLaunchAnnouncement();
    _launchAnnouncementResource?.emit(null);
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
    try {
      await apiRepo.fetchMatch(matchId);
    } on AbuApiException catch (error) {
      if (error.statusCode != 404) rethrow;
      final now = DateTime.now();
      final matchKickoff = kickoffAt ?? now.add(const Duration(days: 1));
      final closesAt = matchKickoff.subtract(const Duration(minutes: 5));
      if (open && !closesAt.isAfter(now)) {
        throw StateError('Predictions cannot open after the match has begun.');
      }
      await apiRepo.createAdminMatch(
        id: matchId,
        homeTeam: homeTeam.trim().isEmpty ? 'Home' : homeTeam.trim(),
        awayTeam: awayTeam.trim().isEmpty ? 'Away' : awayTeam.trim(),
        competition: competition.trim().isEmpty
            ? 'La Liga'
            : competition.trim(),
        kickoffAt: matchKickoff,
        predictionsOpenAt: now.subtract(const Duration(seconds: 1)),
        predictionsCloseAt: closesAt,
        firstScorerOptions: const <String>['No scorer'],
        homeLogoUrl: _normalizedOptionalUrl(homeLogoUrl, 'Home logo URL'),
        awayLogoUrl: _normalizedOptionalUrl(awayLogoUrl, 'Away logo URL'),
      );
    }
    await apiRepo.setAdminMatchStatus(
      matchId: matchId,
      status: open ? 'open' : 'locked',
    );
    await _refreshMatchMutationResources();
  }

  Future<List<PredictionOutcomeResult>> checkUnseenCompletedPredictions(
    String uid, {
    bool isYouTubeMember = false,
  }) async {
    if (uid.isEmpty || uid == 'guest') return const [];
    final predictions = await apiRepo.fetchMyPredictions();
    final results = <PredictionOutcomeResult>[];
    for (final prediction in predictions) {
      final match = prediction.match;
      if (!prediction.rewarded || prediction.seenResult || match == null) {
        continue;
      }
      if (match.homeScore == null || match.awayScore == null) continue;
      final exact = prediction.exactScoreCorrect;
      final scorer = prediction.firstScorerCorrect;
      final winner = prediction.winnerCorrect;
      results.add(
        PredictionOutcomeResult(
          event: match,
          prediction: prediction,
          exactMatch: exact,
          firstScorerMatch: scorer,
          winnerMatch: winner,
          pointsEarned: prediction.pointsAwarded,
          isPerfect: exact && scorer && winner,
          hasSomeCorrect: prediction.pointsAwarded > 0,
        ),
      );
    }
    return results;
  }

  Future<void> markPredictionResultSeen(String predictionId) async {
    await apiRepo.markPredictionResultSeen(predictionId);
    final uid = auth.currentUser?.uid;
    if (uid == null) return;
    final predictions = _localPredictionsByUid[uid];
    if (predictions == null) return;
    for (final entry in predictions.entries.toList()) {
      if (entry.value.id == predictionId) {
        predictions[entry.key] = entry.value.copyWith(seenResult: true);
      }
    }
    _predictionResources[uid]?.emit(_predictionSnapshot(uid));
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
    final id = 'admin_${DateTime.now().microsecondsSinceEpoch}';
    await apiRepo.createAdminMatch(
      id: id,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      competition: competition,
      kickoffAt: kickoffAt,
      predictionsOpenAt: predictionOpensAt,
      predictionsCloseAt: predictionClosesAt,
      firstScorerOptions: scorerOptions,
      homeLogoUrl: _normalizedOptionalUrl(homeLogoUrl, 'Home logo URL'),
      awayLogoUrl: _normalizedOptionalUrl(awayLogoUrl, 'Away logo URL'),
    );
    final now = DateTime.now();
    if (!now.isBefore(predictionOpensAt) && now.isBefore(predictionClosesAt)) {
      await apiRepo.setAdminMatchStatus(matchId: id, status: 'open');
    }
    await _refreshMatchMutationResources();
  }

  Future<void> publishMatchResult({
    required String matchId,
    required int homeScore,
    required int awayScore,
    required String firstScorer,
  }) async {
    final scorer = firstScorer.trim();
    if (scorer.isEmpty ||
        ((homeScore > 0 || awayScore > 0) &&
            scorer.toLowerCase() == 'no scorer')) {
      throw ArgumentError('First scorer is required for a match with goals.');
    }
    await apiRepo.settleAdminMatch(
      matchId: matchId,
      homeScore: homeScore,
      awayScore: awayScore,
      firstScorer: scorer,
    );
    await _refreshMatchMutationResources(refreshPredictions: true);
  }

  Future<Map<String, dynamic>> autoFetchAndSettleMatch(String matchId) async {
    final match = await apiRepo.fetchMatch(matchId);

    final finished = await apiRepo.fetchFootballRecentMatches();
    MatchEvent? target;
    for (final m in finished) {
      if (sameFootballMatchForMatching(m, match)) {
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
    final detailsMatchId = footballDetailsMatchId(target);
    if (timeline.isEmpty && detailsMatchId.startsWith('external_')) {
      try {
        timeline = await apiRepo
            .fetchMatchDetails(detailsMatchId)
            .then((details) => details.timeline);
      } catch (_) {}
    }

    String firstScorer = target.firstScorer.trim();
    if (firstScorer.isEmpty && timeline.isNotEmpty) {
      firstScorer = firstScorerFromFootballTimeline(timeline);
    }
    if (firstScorer.isEmpty) {
      if (target.homeScore == 0 && target.awayScore == 0) {
        firstScorer = 'No scorer';
      } else if (DateTime.now().difference(target.kickoffAt) >=
          const Duration(hours: 4)) {
        firstScorer = 'Unknown';
      } else {
        throw StateError(
          'API has not published the first scorer for this match yet.',
        );
      }
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
  }) async {
    await apiRepo.setAdminMatchStatus(matchId: matchId, status: status);
    await _refreshMatchMutationResources();
  }

  Future<void> _refreshMatchMutationResources({
    bool refreshPredictions = false,
  }) async {
    final tasks = <Future<void>>[];
    if (_managedMatchesResource != null) {
      tasks.add(_managedMatchesResource!.refresh(force: true));
    }
    if (_matchesResource != null) {
      tasks.add(_matchesResource!.refresh(force: true));
    }
    if (refreshPredictions) {
      final uid = auth.currentUser?.uid;
      final resource = uid == null ? null : _predictionResources[uid];
      if (resource != null) tasks.add(resource.refresh(force: true));
    }
    await Future.wait(tasks);
  }

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

  Future<Map<String, dynamic>> createNotificationBroadcast({
    required String title,
    required String body,
    String? imageUrl,
    DateTime? scheduledAt,
  }) {
    final previous = _notificationBroadcastMutationTail;
    final completer = Completer<Map<String, dynamic>>();
    _notificationBroadcastMutationTail = () async {
      try {
        await previous;
      } catch (_) {
        // A failed request retains its persisted key for a safe replay, but it
        // must not prevent a later admin action from entering the queue.
      }
      try {
        completer.complete(
          await _createNotificationBroadcastUnlocked(
            title: title,
            body: body,
            imageUrl: imageUrl,
            scheduledAt: scheduledAt,
          ),
        );
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }();
    return completer.future;
  }

  Future<Map<String, dynamic>> _createNotificationBroadcastUnlocked({
    required String title,
    required String body,
    String? imageUrl,
    DateTime? scheduledAt,
  }) async {
    final normalizedTitle = title.trim();
    final normalizedBody = body.trim();
    final normalizedImage = imageUrl?.trim() ?? '';
    final normalizedSchedule = scheduledAt?.toUtc().toIso8601String() ?? '';
    final signature = jsonEncode([
      normalizedTitle,
      normalizedBody,
      normalizedImage,
      normalizedSchedule,
    ]);
    final preferences = await SharedPreferences.getInstance();
    if (_pendingNotificationBroadcastKey == null &&
        preferences.getString(_pendingBroadcastSignaturePreference) ==
            signature) {
      final persistedKey = preferences
          .getString(_pendingBroadcastKeyPreference)
          ?.trim();
      if (persistedKey != null &&
          RegExp(r'^[A-Za-z0-9:_-]{16,128}$').hasMatch(persistedKey)) {
        _pendingNotificationBroadcastSignature = signature;
        _pendingNotificationBroadcastKey = persistedKey;
      }
    }
    if (_pendingNotificationBroadcastSignature != signature ||
        _pendingNotificationBroadcastKey == null) {
      _pendingNotificationBroadcastSignature = signature;
      _pendingNotificationBroadcastKey = firestore
          .collection('notificationBroadcastAttempts')
          .doc()
          .id;
      await preferences.setString(
        _pendingBroadcastSignaturePreference,
        signature,
      );
      await preferences.setString(
        _pendingBroadcastKeyPreference,
        _pendingNotificationBroadcastKey!,
      );
    }
    final idempotencyKey = _pendingNotificationBroadcastKey!;
    final result = await apiRepo.createNotificationBroadcast(
      title: normalizedTitle,
      body: normalizedBody,
      idempotencyKey: idempotencyKey,
      imageUrl: normalizedImage.isEmpty ? null : normalizedImage,
      scheduledAt: scheduledAt,
    );
    if (_pendingNotificationBroadcastKey == idempotencyKey) {
      _pendingNotificationBroadcastKey = null;
      _pendingNotificationBroadcastSignature = null;
      if (preferences.getString(_pendingBroadcastKeyPreference) ==
          idempotencyKey) {
        await preferences.remove(_pendingBroadcastKeyPreference);
        await preferences.remove(_pendingBroadcastSignaturePreference);
      }
    }
    return result;
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

  bool get accountDeletionNeedsPassword {
    final providers = auth.currentUser?.providerData ?? const <UserInfo>[];
    final canUseApple =
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        providers.any(
          (provider) => provider.providerId == AppleAuthProvider.PROVIDER_ID,
        );
    final canUseGoogle = providers.any(
      (provider) => provider.providerId == GoogleAuthProvider.PROVIDER_ID,
    );
    return !canUseApple &&
        !canUseGoogle &&
        providers.any(
          (provider) => provider.providerId == EmailAuthProvider.PROVIDER_ID,
        );
  }

  Future<void> deleteAccount({String? currentPassword}) async {
    final user = auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'unauthenticated',
        message: 'Sign in before deleting your account.',
      );
    }
    final uid = user.uid;
    final usesApple = user.providerData.any(
      (provider) => provider.providerId == AppleAuthProvider.PROVIDER_ID,
    );
    final usesGoogle = user.providerData.any(
      (provider) => provider.providerId == GoogleAuthProvider.PROVIDER_ID,
    );
    final usesPassword = accountDeletionNeedsPassword;

    // Verify ownership immediately before the destructive operation. This
    // avoids deleting PostgreSQL first and only then discovering that
    // Firebase requires a recent login to remove the authentication record.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS && usesApple) {
      final provider = AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');
      final credential = await user.reauthenticateWithProvider(provider);
      final authorizationCode =
          credential.additionalUserInfo?.authorizationCode;
      if (authorizationCode == null || authorizationCode.isEmpty) {
        throw StateError(
          'Apple did not return the authorization needed to delete this account.',
        );
      }
      await auth.revokeTokenWithAuthorizationCode(authorizationCode);
    } else if (usesGoogle) {
      if (kIsWeb) {
        await user.reauthenticateWithPopup(GoogleAuthProvider());
      } else {
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
        await user.reauthenticateWithCredential(
          GoogleAuthProvider.credential(idToken: idToken),
        );
      }
    } else if (usesPassword) {
      final password = currentPassword?.trim() ?? '';
      final email = user.email?.trim() ?? '';
      if (password.isEmpty || email.isEmpty) {
        throw FirebaseAuthException(
          code: 'account-deletion-password-required',
          message: 'Enter your current password to delete this account.',
        );
      }
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
    }

    // PostgreSQL is authoritative for profiles, points, predictions, content
    // activity, devices, and notification preferences. Do not delete the
    // Firebase identity when this request fails: the user must be able to
    // retry without leaving a hidden server-side account behind.
    await apiRepo.deleteAccount();
    await user.delete();
    if (!kIsWeb && _googleInitialized) {
      await GoogleSignIn.instance.signOut();
    }
    await _clearSignedInAccountState(uid);
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

  _ReplayResource<List<ExclusiveVideo>> get _exclusiveVideoFeed {
    final userId = auth.currentUser?.uid ?? 'guest';
    if (_exclusiveVideosResource != null &&
        _exclusiveVideosResourceUserId != userId) {
      final staleResource = _exclusiveVideosResource;
      _exclusiveVideosResource = null;
      _exclusiveVideosResourceUserId = null;
      unawaited(staleResource!.dispose());
    }
    _exclusiveVideosResourceUserId = userId;
    return _exclusiveVideosResource ??= _ReplayResource<List<ExclusiveVideo>>(
      maxAge: const Duration(seconds: 30),
      load: () => apiRepo.fetchExclusiveVideos(forceRefresh: true),
    );
  }

  _ReplayResource<List<ExclusiveVideo>> get _managedExclusiveVideoFeed =>
      _managedExclusiveVideosResource ??= _ReplayResource<List<ExclusiveVideo>>(
        maxAge: const Duration(seconds: 30),
        load: () => apiRepo.fetchExclusiveVideos(managed: true),
      );

  Stream<List<ExclusiveVideo>> watchExclusiveVideos() =>
      _exclusiveVideoFeed.stream;

  Stream<List<ExclusiveVideo>> watchManagedExclusiveVideos() =>
      _managedExclusiveVideoFeed.stream;

  Future<void> refreshExclusiveVideos({bool force = true}) =>
      _exclusiveVideoFeed.refresh(force: force);

  Future<void> createExclusiveVideo({
    required String youtubeId,
    required String title,
    String? description,
    String? thumbnailUrl,
    DateTime? publishedAt,
    bool isUnlisted = true,
    bool memberOnly = false,
  }) async {
    final normalizedYoutubeId = extractYoutubeVideoId(youtubeId);
    if (normalizedYoutubeId == null) {
      throw ArgumentError(
        'Enter a valid YouTube link or 11-character video ID.',
      );
    }
    await runMutationAndForceRefresh(
      mutation: () => apiRepo.createExclusiveVideo(
        youtubeId: normalizedYoutubeId,
        title: title.trim(),
        description: description?.trim(),
        thumbnailUrl: thumbnailUrl?.trim(),
        publishedAt: publishedAt,
        isUnlisted: isUnlisted,
        memberOnly: memberOnly,
      ),
      refreshers: <Future<void> Function()>[
        if (_exclusiveVideosResource != null)
          () => _exclusiveVideosResource!.refresh(force: true),
        if (_managedExclusiveVideosResource != null)
          () => _managedExclusiveVideosResource!.refresh(force: true),
      ],
    );
  }

  Future<void> deleteExclusiveVideo(String id) => runMutationAndForceRefresh(
    mutation: () => apiRepo.deleteExclusiveVideo(id),
    refreshers: <Future<void> Function()>[
      if (_exclusiveVideosResource != null)
        () => _exclusiveVideosResource!.refresh(force: true),
      if (_managedExclusiveVideosResource != null)
        () => _managedExclusiveVideosResource!.refresh(force: true),
    ],
  );

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
            load: () => _fetchLeaderboardSnapshot(period, seasonId: seasonId),
          ),
        )
        .stream;
  }

  Future<LeaderboardSnapshot> _fetchLeaderboardSnapshot(
    LeaderboardPeriod period, {
    String? seasonId,
  }) => apiRepo.fetchLeaderboardSnapshot(
    period: switch (period) {
      LeaderboardPeriod.currentMonth => 'monthly',
      LeaderboardPeriod.previousMonth => 'previous-month',
      LeaderboardPeriod.season => 'season',
    },
    seasonId: period == LeaderboardPeriod.season ? seasonId : null,
  );

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

  Future<void> setAchievementEnabled(String id, bool enabled) =>
      apiRepo.setAdminAchievementEnabled(achievementId: id, enabled: enabled);

  Future<void> saveAchievement(AbuAchievement model) =>
      apiRepo.saveAdminAchievement(model);

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

  Future<void> setLevelEnabled(String id, bool enabled) =>
      apiRepo.setAdminLevelEnabled(levelId: id, enabled: enabled);

  Future<void> saveLevel(AbuLevel model) => apiRepo.saveAdminLevel(model);

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

  Future<void> setRewardEnabled(String id, bool enabled) =>
      apiRepo.setAdminRewardEnabled(rewardId: id, enabled: enabled);

  Future<void> saveReward(AbuLoyaltyReward model) =>
      apiRepo.saveAdminReward(model);

  Stream<List<AbuRewardRedemption>> watchRedemptions(String uid) => firestore
      .collection('loyaltyRedemptions')
      .where('userId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(AbuRewardRedemption.fromDocument).toList())
      .handleError((_) => const <AbuRewardRedemption>[]);

  Future<void> redeemReward(String id) async {
    final user = auth.currentUser;
    if (user == null) {
      throw AbuApiException(
        statusCode: 401,
        message: 'Authentication required',
      );
    }
    final pendingKey = '${user.uid}:$id';
    final preferenceKey =
        '$_pendingRewardRedemptionPreferencePrefix${Uri.encodeComponent(pendingKey)}';
    final preferences = await SharedPreferences.getInstance();
    final persistedKey = preferences.getString(preferenceKey)?.trim();
    if (!_pendingRewardRedemptionKeys.containsKey(pendingKey) &&
        persistedKey != null &&
        RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(persistedKey)) {
      _pendingRewardRedemptionKeys[pendingKey] = persistedKey;
    }
    // Keep the same key after an ambiguous timeout. A second tap then replays
    // the original receipt instead of deducting points and stock twice. The
    // durable copy also survives an app termination after the server commits.
    final idempotencyKey = _pendingRewardRedemptionKeys.putIfAbsent(
      pendingKey,
      () => firestore.collection('loyaltyRedemptions').doc().id,
    );
    await preferences.setString(preferenceKey, idempotencyKey);
    final receipt = await apiRepo.redeemLoyaltyReward(
      rewardId: id,
      idempotencyKey: idempotencyKey,
    );
    if (_pendingRewardRedemptionKeys[pendingKey] == idempotencyKey) {
      _pendingRewardRedemptionKeys.remove(pendingKey);
    }
    if (preferences.getString(preferenceKey) == idempotencyKey) {
      await preferences.remove(preferenceKey);
    }

    final current = _localProfiles[user.uid];
    if (current != null) {
      final updated = current.copyWith(loyaltyPoints: receipt.remainingBalance);
      _localProfiles[user.uid] = updated;
      _profileResources[user.uid]?.emit(updated);
    }

    // Firestore listeners refresh the fan catalogue/history. Refresh the
    // PostgreSQL profile and an already-open Admin Studio list as well so all
    // current screens converge immediately after the cross-store commit.
    await Future.wait([
      refreshProfile(user.uid, force: true),
      if (_adminRedemptionsResource != null)
        _adminRedemptionsResource!.refresh(force: true),
    ]);
  }

  Future<void> updateRedemptionStatus(
    String id,
    String status, {
    String? note,
  }) async {
    await apiRepo.updateAdminRedemptionStatus(
      redemptionId: id,
      status: status,
      note: note ?? '',
    );
    await _adminRedemptionsResource?.refresh(force: true);
  }

  Stream<List<AbuRewardRedemption>> watchManagedRedemptions() =>
      (_adminRedemptionsResource ??= _ReplayResource<List<AbuRewardRedemption>>(
        maxAge: const Duration(minutes: 1),
        load: apiRepo.fetchAdminRedemptions,
      )).stream;

  // ── Player Cards ──────────────────────────────────────────────────────

  Stream<List<AbuPlayerCard>> watchPlayerCards(String uid) {
    if (uid.isEmpty || uid == 'guest') {
      return Stream.value(const <AbuPlayerCard>[]);
    }
    return _playerCardResources
        .putIfAbsent(
          uid,
          () => _ReplayResource<List<AbuPlayerCard>>(
            maxAge: const Duration(minutes: 2),
            load: () => apiRepo.fetchPlayerCards(),
          ),
        )
        .stream;
  }

  Future<void> refreshPlayerCards(String uid, {bool force = true}) async {
    if (uid.isEmpty || uid == 'guest') return;
    watchPlayerCards(uid);
    await _playerCardResources[uid]?.refresh(force: force);
  }

  Stream<List<AbuPlayerCard>> watchManagedPlayerCards() =>
      (_managedPlayerCardsResource ??= _ReplayResource<List<AbuPlayerCard>>(
        maxAge: const Duration(minutes: 2),
        load: () => apiRepo.fetchPlayerCards(managed: true),
      )).stream;

  Future<List<AbuPlayerCard>> fetchManagedPlayerCards() =>
      apiRepo.fetchPlayerCards(managed: true);

  Future<void> setPlayerCardEnabled(String id, bool enabled) async {
    await apiRepo.setAdminPlayerCardEnabled(cardId: id, enabled: enabled);
    await Future.wait([
      ..._playerCardResources.values.map(
        (resource) => resource.refresh(force: true),
      ),
      _managedPlayerCardsResource?.refresh(force: true) ?? Future<void>.value(),
    ]);
  }

  Future<void> savePlayerCard(AbuPlayerCard model) async {
    await apiRepo.saveAdminPlayerCard(model);
    await Future.wait([
      ..._playerCardResources.values.map(
        (resource) => resource.refresh(force: true),
      ),
      _managedPlayerCardsResource?.refresh(force: true) ?? Future<void>.value(),
    ]);
  }

  Future<void> deletePlayerCard(String id) async {
    await apiRepo.deleteAdminPlayerCard(id);
    await Future.wait([
      ..._playerCardResources.values.map(
        (resource) => resource.refresh(force: true),
      ),
      _managedPlayerCardsResource?.refresh(force: true) ?? Future<void>.value(),
    ]);
  }

  // ── Advanced Challenges ───────────────────────────────────────────────

  Future<Map<String, dynamic>> submitChallengeAnswers({
    required AbuChallenge challenge,
    required Map<String, String> answers,
  }) async {
    final answer = answers.values
        .map((value) => value.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (answer.isEmpty) throw ArgumentError('Enter an answer first.');
    final result = await apiRepo.submitChallengeAnswer(
      challengeId: challenge.id,
      answer: answer,
    );
    await _syncChallengeAward(result);
    await refreshChallenges(force: true);
    return {
      ...result,
      'points': result['points'] ?? result['pointsAwarded'] ?? 0,
    };
  }

  Future<String> createAdvancedChallenge({
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
    String playerCardId = '',
    List<dynamic> questions = const [],
  }) async {
    final formattedQuestions = questions
        .map<Map<String, dynamic>>((q) {
          Map<String, dynamic> data;
          if (q is AbuChallengeQuestion) {
            data = <String, dynamic>{
              ...q.toPublicMap(),
              'correctAnswer': q.correctAnswer,
              'acceptedAnswers': q.acceptedAnswers,
            };
          } else if (q is Map) {
            data = Map<String, dynamic>.from(q);
          } else {
            try {
              data = Map<String, dynamic>.from((q as dynamic).toMap() as Map);
            } catch (_) {
              data = <String, dynamic>{};
            }
          }
          final answer = (data['correctAnswer'] ?? data['answer'] ?? '')
              .toString();
          return <String, dynamic>{
            'id': (data['id'] ?? 'main').toString(),
            'prompt': effectiveChallengePrompt(
              title: title,
              prompt: (data['prompt'] ?? '').toString(),
            ),
            'type': (data['type'] ?? 'text').toString(),
            'options': data['options'] is List
                ? List<String>.from(
                    (data['options'] as List).map((value) => value.toString()),
                  )
                : const <String>[],
            'correctAnswer': answer,
            'acceptedAnswers': data['acceptedAnswers'] is List
                ? List<String>.from(
                    (data['acceptedAnswers'] as List).map(
                      (value) => value.toString(),
                    ),
                  )
                : const <String>[],
          };
        })
        .toList(growable: false);
    if (formattedQuestions.isEmpty) {
      throw ArgumentError('Add at least one challenge question.');
    }
    final challengeId = await apiRepo.createAdminChallenge(
      kind: kind,
      title: title.trim(),
      description: description.trim(),
      videoUrl: videoUrl.trim(),
      imageUrl: imageUrl.trim(),
      rewardPoints: rewardPoints,
      availableFrom: availableFrom,
      availableUntil: availableUntil,
      status: status,
      maximumAttempts: maximumAttempts,
      memberOnly: memberOnly,
      notifyOnLive: notifyOnLive,
      playerCardId: playerCardId,
      questions: formattedQuestions,
    );
    await Future.wait([
      ..._challengeResources.values.map(
        (resource) => resource.refresh(force: true),
      ),
      _managedChallengesResource?.refresh(force: true) ?? Future<void>.value(),
      _managedPlayerCardsResource?.refresh(force: true) ?? Future<void>.value(),
    ]);
    return challengeId;
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

  // ── YouTube membership check ────────────────────────────────────────────

  /// Verifies the selected Google account's own YouTube channel against the
  /// current server-side membership CSV. The Google access token is used for
  /// this request only and is never stored by the client.
  Future<YouTubeMembershipCheckResult> checkYouTubeMembership() async {
    final user = auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'unauthenticated',
        message: 'Sign in before checking YouTube membership.',
      );
    }
    if (kIsWeb) {
      throw UnsupportedError(
        'YouTube membership checking is currently available in the mobile app.',
      );
    }
    if (!_googleInitialized) {
      await GoogleSignIn.instance.initialize();
      _googleInitialized = true;
    }

    final googleAccount = await GoogleSignIn.instance.authenticate(
      scopeHint: youtubeMembershipGoogleScopes,
    );
    final linkedGoogleProviders = user.providerData.where(
      (provider) => provider.providerId == GoogleAuthProvider.PROVIDER_ID,
    );
    var linkedGoogleForThisCheck = false;
    if (linkedGoogleProviders.isEmpty) {
      final idToken = googleAccount.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw FirebaseAuthException(
          code: 'missing-google-token',
          message: 'Google did not return a valid identity token.',
        );
      }
      await user.linkWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
      linkedGoogleForThisCheck = true;
    } else if (linkedGoogleProviders.first.uid != googleAccount.id) {
      // Clear only the transient Google Sign-In selection. The Firebase
      // account stays signed in and its linked identity is unchanged.
      await GoogleSignIn.instance.signOut();
      throw FirebaseAuthException(
        code: 'youtube-google-account-mismatch',
        message: 'Choose the Google account already linked to this Abu 3meer account.',
      );
    }

    var authorization = await googleAccount.authorizationClient
        .authorizationForScopes(youtubeMembershipGoogleScopes);
    authorization ??= await googleAccount.authorizationClient.authorizeScopes(
      youtubeMembershipGoogleScopes,
    );
    final accessToken = authorization.accessToken.trim();
    if (accessToken.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-youtube-access-token',
        message: 'Google did not authorize YouTube membership checking.',
      );
    }

    await user.reload();
    if (linkedGoogleForThisCheck) {
      // Refresh once so the authenticated API can bind the Google access-token
      // subject to the newly linked Firebase identity. Already-linked accounts
      // keep their cached token and stable server rate-limit bucket.
      await user.getIdToken(true);
    }
    final result = await apiRepo.checkYouTubeMembership(accessToken);
    await refreshProfile(user.uid, force: true);
    return result;
  }

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
      401 =>
        RegExp(
              r'google|youtube|access token',
              caseSensitive: false,
            ).hasMatch(error.message)
            ? error.message
            : 'Your session expired. Sign in again and retry.',
      403 =>
        RegExp(
              r'google|youtube|scope|identity',
              caseSensitive: false,
            ).hasMatch(error.message)
            ? error.message
            : 'Your account is not allowed to perform this action.',
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
      'popup-closed-by-user' || 'canceled' => 'Sign-in was cancelled.',
      'account-exists-with-different-credential' => 'An account already uses this email. Sign in with the method you used before.',
      'credential-already-in-use' => 'That Google account is linked to another Abu 3meer account. Sign out of that account first, then link Google here.',
      'provider-already-linked' => 'Google is already linked to this account.',
      'youtube-google-account-mismatch' =>
        'Choose the Google account already linked to this Abu 3meer account.',
      'missing-youtube-access-token' =>
        'Allow read-only YouTube access so membership can be checked.',
      'operation-not-allowed' =>
        'This sign-in method is not enabled yet. Contact support.',
      'account-deletion-password-required' =>
        'Enter your current password to delete this account.',
      'requires-recent-login' => 'For your security, sign out and sign in again before changing account security details or deleting your account.',
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
      RegExp(r'^(Invalid argument(?:\(s\))?|Bad state): '),
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
