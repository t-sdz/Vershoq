import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'screens/camera_screen.dart';
import 'screens/landing_screen.dart';
import 'services/notification_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialise Firebase (Firestore pour les groupes).
  // Utilise les fichiers natifs google-services.json / GoogleService-Info.plist.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init échouée (groupes indisponibles) : $e');
  }

  await NotificationService.init(
    onTap: (personName) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => CameraScreen(personName: personName),
        ),
      );
    },
  );

  // Schedule random notifications on first launch
  await NotificationService.scheduleRandom();

  // Check if app was launched by tapping a notification
  final launchPayload = await NotificationService.getLaunchPayload();

  runApp(VershoqApp(initialPersonName: launchPayload));
}

class VershoqApp extends StatelessWidget {
  final String? initialPersonName;

  const VershoqApp({super.key, this.initialPersonName});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vershoq',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: _buildTheme(),
      home: initialPersonName != null && initialPersonName!.isNotEmpty
          ? CameraScreen(personName: initialPersonName!)
          : const LandingScreen(),
    );
  }

  ThemeData _buildTheme() {
    // BeReal-style: pur noir, blanc, typographie franche
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: Colors.white,
        onPrimary: Colors.black,
        secondary: Colors.white,
        surface: Color(0xFF111111),
        onSurface: Colors.white,
      ),
      scaffoldBackgroundColor: Colors.black,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: Colors.white,
        thumbColor: Colors.white,
        inactiveTrackColor: Colors.white24,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontWeight: FontWeight.w900,
          color: Colors.white,
          letterSpacing: -1.5,
        ),
        titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        bodyMedium: TextStyle(color: Colors.white70),
      ),
    );
  }
}
