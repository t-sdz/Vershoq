import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/camera_screen.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

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
          : const HomeScreen(),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFFF6B6B),
        secondary: Color(0xFFFFE66D),
        surface: Color(0xFF1A1A2E),
        onSurface: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFF0F0F1A),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0F0F1A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: -1,
        ),
        titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        bodyMedium: TextStyle(color: Colors.white70),
      ),
    );
  }
}
