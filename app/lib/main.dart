import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'router/app_router.dart';
import 'services/auth_service.dart';
import 'theme/app_accent.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Debug builds only — talks to `firebase emulators:start --only auth`
  // instead of the live project, so local sign-up/sign-in isn't blocked by
  // Play Integrity/reCAPTCHA checks that emulators can't satisfy. Release
  // builds (kDebugMode == false) always hit real Firebase Auth.
  if (kDebugMode == false) {
    final host = kIsWeb || !Platform.isAndroid ? 'localhost' : '10.0.2.2';
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
  }

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = buildAppRouter(AuthService());
    return ValueListenableBuilder<Color>(
      valueListenable: AppAccent.notifier,
      builder: (context, accent, _) => MaterialApp.router(
        theme: AppTheme.build(accent),
        routerConfig: router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
