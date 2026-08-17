import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'models.dart';

class ProductionRepository {
  ProductionRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : auth = auth ?? FirebaseAuth.instance,
       firestore = firestore ?? FirebaseFirestore.instance,
       functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;
  bool _googleInitialized = false;

  Stream<User?> get authChanges => auth.userChanges();

  Stream<AbuUserProfile?> watchProfile(String uid) => firestore
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((doc) => doc.exists ? AbuUserProfile.fromDocument(doc) : null);

  Stream<List<MatchEvent>> watchMatches() => firestore
      .collection('matches')
      .where('status', whereIn: const ['open', 'locked', 'completed'])
      .orderBy('kickoffAt')
      .limit(30)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(MatchEvent.fromDocument).toList());

  Stream<List<PointLedgerEntry>> watchPointHistory(String uid) => firestore
      .collection('pointTransactions')
      .where('userId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.map(PointLedgerEntry.fromDocument).toList(),
      );

  Stream<List<LeaderboardEntry>> watchLeaderboard({required bool monthly}) =>
      firestore
          .collection('leaderboardEntries')
          .orderBy(monthly ? 'monthlyPoints' : 'seasonPoints', descending: true)
          .limit(100)
          .snapshots()
          .map(
            (snapshot) =>
                snapshot.docs.map(LeaderboardEntry.fromDocument).toList(),
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

  Future<void> submitPrediction({
    required String matchId,
    required int homeScore,
    required int awayScore,
  }) => _call('submitPrediction', {
    'matchId': matchId,
    'homeScore': homeScore,
    'awayScore': awayScore,
  });

  Future<void> createMatch({
    required String homeTeam,
    required String awayTeam,
    required String competition,
    required DateTime kickoffAt,
    required DateTime predictionOpensAt,
    required DateTime predictionClosesAt,
    String homeLogoUrl = '',
    String awayLogoUrl = '',
  }) => _call('adminCreateMatch', {
    'homeTeam': homeTeam.trim(),
    'awayTeam': awayTeam.trim(),
    'competition': competition.trim(),
    'kickoffAt': kickoffAt.millisecondsSinceEpoch,
    'predictionOpensAt': predictionOpensAt.millisecondsSinceEpoch,
    'predictionClosesAt': predictionClosesAt.millisecondsSinceEpoch,
    'homeLogoUrl': homeLogoUrl.trim(),
    'awayLogoUrl': awayLogoUrl.trim(),
  });

  Future<void> publishMatchResult({
    required String matchId,
    required int homeScore,
    required int awayScore,
  }) => _call('adminPublishMatchResult', {
    'matchId': matchId,
    'homeScore': homeScore,
    'awayScore': awayScore,
  });

  Future<void> updatePointRules({
    required int exactPrediction,
    required int videoQuestion,
    required int playerCard,
    required double memberMultiplier,
  }) => _call('adminUpdatePointRules', {
    'exactPrediction': exactPrediction,
    'videoQuestion': videoQuestion,
    'playerCard': playerCard,
    'memberMultiplier': memberMultiplier,
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
