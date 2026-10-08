import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app_sound.dart';
import 'firebase_options.dart';
import 'splashscreen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Must finish BEFORE runApp - anything touching FirebaseAuth or Firestore
  // before this throws "No Firebase App '[DEFAULT]' has been created".
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await AppSound.instance.init();
  runApp(const PlantGuardApp());
}

/// Plays the transition whoosh on every screen change, anywhere in the app.
///
/// Doing it here rather than inside each route helper means any navigation
/// gets the sound automatically - including pops and back-gesture pops - and
/// no call site can forget it.
class SoundNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // previousRoute is null for the very first route, i.e. app launch. The
    // splash shouldn't whoosh itself into existence.
    if (previousRoute != null) AppSound.instance.whoosh(variant: 2, volumeScale: 0.4);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AppSound.instance.whoosh(variant: 2, volumeScale: 0.4);
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    AppSound.instance.whoosh(variant: 2, volumeScale: 0.4);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

class PlantGuardApp extends StatefulWidget {
  const PlantGuardApp({super.key});

  @override
  State<PlantGuardApp> createState() => _PlantGuardAppState();
}

class _PlantGuardAppState extends State<PlantGuardApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppSound.instance.dispose();
    super.dispose();
  }

  /// Ambient shouldn't keep playing once the app is backgrounded, and should
  /// pick back up on return. Both calls no-op unless it was actually running,
  /// so this is harmless while the user is still on splash/login/signup.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        AppSound.instance.resumeAmbient();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        AppSound.instance.pauseAmbient();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PlantGuard',
      debugShowCheckedModeBanner: false,
      navigatorObservers: <NavigatorObserver>[SoundNavigatorObserver()],
      theme: ThemeData(
        // Inter is bundled (see the fonts: block in pubspec.yaml), so it is
        // the app-wide default rather than being set widget by widget.
        fontFamily: 'Inter',
        primaryColor: const Color(0xFF6BA342),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6BA342),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}