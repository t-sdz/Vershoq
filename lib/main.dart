import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';

import 'screens/camera_screen.dart';
import 'screens/feed_screen.dart';
import 'screens/landing_screen.dart';
import 'services/auth_service.dart';
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
    await AuthService.signInAnonymously();
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
    const warmDark = Color(0xFF3D1A08);
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: Color(0xFFFF8A3D),
        onPrimary: Colors.white,
        secondary: Color(0xFFFF6B6B),
        onSecondary: Colors.white,
        surface: Color(0xFFFFF1D6),
        onSurface: warmDark,
      ),
      scaffoldBackgroundColor: const Color(0xFFFFF1D6),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: warmDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFFF8A3D),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: Color(0xFFFF8A3D),
        thumbColor: Color(0xFFFF8A3D),
        inactiveTrackColor: Color(0xFFFFD9C2),
        valueIndicatorColor: Color(0xFFFF8A3D),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? const Color(0xFFFF8A3D)
                : const Color(0xFFFFD9C2)),
        thumbColor: WidgetStateProperty.all(Colors.white),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: TextStyle(color: const Color(0xFF9A6B50).withOpacity(0.5)),
        prefixIconColor: const Color(0xFFFF8A3D),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFFFD9C2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFFFD9C2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFFF8A3D), width: 2),
        ),
      ),
      cardColor: Colors.white,
      textTheme: const TextTheme(
        displayLarge: TextStyle(
            fontWeight: FontWeight.w900,
            color: warmDark,
            letterSpacing: -1.5),
        titleLarge:
            TextStyle(color: warmDark, fontWeight: FontWeight.w700),
        bodyMedium: TextStyle(color: warmDark),
      ),
    );
  }
}
