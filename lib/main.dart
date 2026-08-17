import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'demo/fan_league_app.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    Abu3meerBootstrap(
      initializeFirebase: () async {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        ).timeout(const Duration(seconds: 6));
        if (kIsWeb) {
          await FirebaseAuth.instance.setPersistence(Persistence.SESSION);
        }
      },
    ),
  );
}
