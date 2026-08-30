import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'demo/fan_league_app.dart';
import 'firebase_options.dart';
import 'production/app_check_config.dart';
import 'production/app_preferences.dart';
import 'production/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  NotificationService.registerBackgroundHandler();
  runApp(
    Abu3meerBootstrap(
      initializeFirebase: () async {
        try {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          ).timeout(const Duration(seconds: 4));
        } catch (_) {}

        try {
          await AbuAppCheckConfig.activate().timeout(
            const Duration(seconds: 2),
          );
        } catch (_) {}

        if (kIsWeb) {
          try {
            await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
          } catch (_) {}
        }

        try {
          await AbuAppPreferences.instance.load().timeout(
            const Duration(seconds: 2),
          );
        } catch (_) {}

        try {
          await NotificationService.instance.initialize().timeout(
            const Duration(seconds: 3),
          );
        } catch (_) {}
      },
    ),
  );
}
