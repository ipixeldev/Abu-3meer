import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'external_content_service.dart';
import 'models.dart';
import 'temporary_mock_data.dart';

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

class ProductionRepository {
  ProductionRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    AbuExternalContentService? externalContent,
  }) : auth = auth ?? FirebaseAuth.instance,
       firestore = firestore ?? FirebaseFirestore.instance,
       functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1'),
       externalContent = externalContent ?? AbuExternalContentService();

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;
  final AbuExternalContentService externalContent;
  bool _googleInitialized = false;

  Stream<User?> get authChanges => auth.userChanges();

  Stream<AbuUserProfile?> watchProfile(String uid) => firestore
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((doc) => doc.exists ? AbuUserProfile.fromDocument(doc) : null);

  Stream<List<MatchEvent>> watchManagedMatches() => firestore
      .collection('matches')
      .orderBy('kickoffAt')
      .limit(100)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(MatchEvent.fromDocument).toList());

  Stream<List<MatchEvent>> _watchPublishedMatches() => firestore
      .collection('matches')
      .where('status', whereIn: const ['open', 'locked', 'completed'])
      .orderBy('kickoffAt')
      .limit(30)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(MatchEvent.fromDocument).toList());

  Stream<List<MatchEvent>> watchMatches() async* {
    if (TemporaryMockData.instance.enabled) {
      yield TemporaryMockData.instance.matches;
      return;
    }
    await for (final managed in _watchPublishedMatches()) {
      if (managed.isNotEmpty) {
        yield managed;
        continue;
      }
      final externalMatch = await externalContent.nextMatch(refresh: true);
      yield externalMatch == null ? const [] : [externalMatch];
    }
  }

  Future<LatestVideo> latestVideo({bool refresh = false}) {
    if (TemporaryMockData.instance.enabled) {
      return Future.value(TemporaryMockData.instance.video);
    }
    return externalContent.latestVideo(refresh: refresh);
  }

  Future<FootballTeamAsset?> lookupTeam(String name) =>
      externalContent.lookupTeam(name);

  Stream<List<PointLedgerEntry>> watchPointHistory(String uid) {
    if (TemporaryMockData.instance.enabled) {
      return Stream.value(TemporaryMockData.instance.pointHistory);
    }
    return firestore
        .collection('pointTransactions')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(PointLedgerEntry.fromDocument).toList(),
        );
  }

  Stream<List<LeaderboardEntry>> watchLeaderboard({required bool monthly}) {
    if (TemporaryMockData.instance.enabled) {
      return Stream.value(
        TemporaryMockData.instance.leaderboard(
          auth.currentUser?.uid ?? 'mock_current',
        ),
      );
    }
    return firestore
        .collection('leaderboardEntries')
        .orderBy(monthly ? 'monthlyPoints' : 'seasonPoints', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(LeaderboardEntry.fromDocument).toList(),
        );
  }

  Stream<List<AbuChallenge>> watchChallenges() {
    if (TemporaryMockData.instance.enabled) {
      return Stream.value(TemporaryMockData.instance.challenges);
    }
    return _watchChallengeDocuments().map(
      (events) => events.where((event) => event.isOpen).toList(),
    );
  }

  Stream<List<AbuChallenge>> watchManagedChallenges() {
    if (TemporaryMockData.instance.enabled) {
      return Stream.value(TemporaryMockData.instance.challenges);
    }
    return _watchChallengeDocuments();
  }

  Stream<List<AbuChallenge>> _watchChallengeDocuments() => firestore
      .collection('videoQuestions')
      .orderBy('availableFrom', descending: true)
      .limit(30)
      .snapshots()
      .asyncMap((questions) async {
        final cards = await firestore
            .collection('playerCards')
            .orderBy('availableFrom', descending: true)
            .limit(30)
            .get();
        final result = <AbuChallenge>[
          ...questions.docs.map(
            (doc) => AbuChallenge.fromDocument(
              doc,
              doc.data()['kind'] as String? ?? 'videoQuestion',
            ),
          ),
          ...cards.docs.map(
            (doc) => AbuChallenge.fromDocument(doc, 'playerCard'),
          ),
        ]..sort((a, b) => b.availableFrom.compareTo(a.availableFrom));
        return result;
      });

  Stream<List<AbuPost>> watchPosts() {
    if (TemporaryMockData.instance.enabled) {
      return Stream.value(TemporaryMockData.instance.posts);
    }
    return firestore
        .collection('posts')
        .orderBy('publishedAt', descending: true)
        .limit(40)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(AbuPost.fromDocument).toList());
  }

  Stream<List<AbuComment>> watchPostComments(String postId) => firestore
      .collection('posts')
      .doc(postId)
      .collection('comments')
      .orderBy('createdAt')
      .limit(200)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(AbuComment.fromDocument).toList());

  Stream<LaunchAnnouncement?> watchLaunchAnnouncement() => firestore
      .collection('platformSettings')
      .doc('launchAnnouncement')
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.exists ? LaunchAnnouncement.fromDocument(snapshot) : null,
      );

  Stream<List<AbuUserProfile>> watchUsers() => firestore
      .collection('users')
      .orderBy('createdAt', descending: true)
      .limit(200)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.map(AbuUserProfile.fromDocument).toList(),
      );

  Stream<FanDuel?> watchFanDuel(String code) => firestore
      .collection('duelRooms')
      .doc(code.toUpperCase())
      .snapshots()
      .map(
        (snapshot) => snapshot.exists ? FanDuel.fromDocument(snapshot) : null,
      );

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
      );

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
    await auth.signOut();
    if (!kIsWeb && _googleInitialized) {
      await GoogleSignIn.instance.signOut();
    }
  }

  Future<void> completeOnboarding({
    required String username,
    required String displayName,
    required String country,
    required String supportedTeam,
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
    if (supportedTeam != 'Barcelona' && supportedTeam != 'Real Madrid') {
      throw ArgumentError('Choose Barcelona or Real Madrid.');
    }

    final userRef = firestore.collection('users').doc(user.uid);
    final usernameRef = firestore
        .collection('usernames')
        .doc(normalizedUsername);
    final leaderboardRef = firestore
        .collection('leaderboardEntries')
        .doc(user.uid);
    final now = DateTime.now().toUtc();
    final monthlyPeriod = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    await firestore.runTransaction((transaction) async {
      final claimed = await transaction.get(usernameRef);
      final existing = await transaction.get(userRef);
      if (claimed.exists && claimed.data()?['uid'] != user.uid) {
        throw StateError('That username is already taken.');
      }
      if (existing.exists) {
        throw StateError('Your profile already exists. Refresh the page.');
      }
      final timestamp = FieldValue.serverTimestamp();
      transaction.set(usernameRef, {'uid': user.uid, 'createdAt': timestamp});
      transaction.set(userRef, {
        'email': user.email ?? '',
        'username': normalizedUsername,
        'displayName': normalizedDisplayName,
        'country': normalizedCountry,
        'supportedTeam': supportedTeam,
        'avatarUrl': avatarUrl.trim(),
        'role': 'user',
        'membershipMultiplier': 1,
        'suspended': false,
        'totalPoints': 0,
        'monthlyPoints': 0,
        'seasonPoints': 0,
        'currentStreak': 0,
        'longestStreak': 0,
        'lastActivityAt': null,
        'monthlyPeriod': monthlyPeriod,
        'onboardingComplete': true,
        'createdAt': timestamp,
        'updatedAt': timestamp,
      });
      transaction.set(leaderboardRef, {
        'username': normalizedUsername,
        'avatarUrl': avatarUrl.trim(),
        'supportedTeam': supportedTeam,
        'monthlyPoints': 0,
        'seasonPoints': 0,
        'isMember': false,
        'monthlyPeriod': monthlyPeriod,
        'updatedAt': timestamp,
      });
    });
  }

  Future<void> updateProfile({
    required String username,
    required String displayName,
    required String country,
    required String supportedTeam,
  }) async {
    final user = auth.currentUser;
    if (user == null) throw StateError('Sign in is required.');
    final normalized = username.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{3,24}$').hasMatch(normalized)) {
      throw ArgumentError(
        'Username must be 3–24 letters, numbers, or underscores.',
      );
    }
    final userRef = firestore.collection('users').doc(user.uid);
    final leaderboardRef = firestore
        .collection('leaderboardEntries')
        .doc(user.uid);
    await firestore.runTransaction((transaction) async {
      final current = await transaction.get(userRef);
      if (!current.exists) throw StateError('Profile not found.');
      final oldUsername = current.data()?['username'] as String? ?? '';
      final nextUsernameRef = firestore.collection('usernames').doc(normalized);
      final claimed = await transaction.get(nextUsernameRef);
      if (claimed.exists && claimed.data()?['uid'] != user.uid) {
        throw StateError('That username is already taken.');
      }
      final timestamp = FieldValue.serverTimestamp();
      transaction.set(nextUsernameRef, {
        'uid': user.uid,
        'createdAt': timestamp,
      });
      if (oldUsername.isNotEmpty && oldUsername != normalized) {
        transaction.delete(firestore.collection('usernames').doc(oldUsername));
      }
      transaction.update(userRef, {
        'username': normalized,
        'displayName': displayName.trim(),
        'country': country.trim(),
        'supportedTeam': supportedTeam,
        'updatedAt': timestamp,
      });
      transaction.update(leaderboardRef, {
        'username': normalized,
        'supportedTeam': supportedTeam,
        'updatedAt': timestamp,
      });
    });
  }

  Future<Map<String, dynamic>> submitChallengeAnswer({
    required AbuChallenge challenge,
    required String answer,
  }) async {
    if (TemporaryMockData.instance.enabled) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final correct = answer.trim().isNotEmpty;
      return {
        'correct': correct,
        'points': correct ? challenge.rewardPoints : 0,
      };
    }
    final name = challenge.kind == 'playerCard'
        ? 'claimPlayerCard'
        : 'submitVideoAnswer';
    final idKey = challenge.kind == 'playerCard' ? 'cardId' : 'questionId';
    final result = await functions
        .httpsCallable(name)
        .call<Map<String, dynamic>>({
          idKey: challenge.id,
          'answer': answer.trim(),
        });
    return result.data;
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
      'normalizedAnswer': answer.trim().toLowerCase(),
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

  Future<void> reactToPost(String postId) => firestore
      .collection('posts')
      .doc(postId)
      .collection('reactions')
      .doc(auth.currentUser!.uid)
      .set({
        'userId': auth.currentUser!.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<void> addPostComment({
    required String postId,
    required String userName,
    required String body,
  }) => firestore.collection('posts').doc(postId).collection('comments').add({
    'userId': auth.currentUser!.uid,
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
    if (!const ['user', 'moderator', 'editor', 'admin'].contains(role)) {
      throw ArgumentError('Unsupported role.');
    }
    final batch = firestore.batch();
    batch.update(firestore.collection('users').doc(uid), {
      'role': role,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(firestore.collection('adminAuditLogs').doc(), {
      'adminId': auth.currentUser!.uid,
      'action': 'SET_ROLE',
      'targetId': uid,
      'role': role,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
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
  }) async {
    if (TemporaryMockData.instance.enabled && matchId.startsWith('mock_')) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      return;
    }
    await _call('submitPrediction', {
      'matchId': matchId,
      'homeScore': homeScore,
      'awayScore': awayScore,
    });
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
  }) async {
    if (!(predictionOpensAt.isBefore(predictionClosesAt) &&
        !predictionClosesAt.isAfter(kickoffAt))) {
      throw ArgumentError('Prediction times must be ordered before kickoff.');
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
  }) => _call('adminPublishMatchResult', {
    'matchId': matchId,
    'homeScore': homeScore,
    'awayScore': awayScore,
  });

  Future<void> setMatchStatus({
    required String matchId,
    required String status,
  }) => firestore.collection('matches').doc(matchId).update({
    'status': status,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> updatePointRules({
    required int exactPrediction,
    required int videoQuestion,
    required int playerCard,
    required double memberMultiplier,
  }) => firestore.collection('platformSettings').doc('points').set({
    'exactPrediction': exactPrediction,
    'videoQuestion': videoQuestion,
    'playerCard': playerCard,
    'memberMultiplier': memberMultiplier,
    'updatedBy': auth.currentUser!.uid,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> _call(String name, Map<String, Object?> data) async {
    await functions.httpsCallable(name).call<Map<String, dynamic>>(data);
  }
}

String productionErrorMessage(Object error) {
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
