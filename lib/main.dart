import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'firebase_options.dart';
import 'screens/camera_screen.dart';
import 'screens/feed_screen.dart';
import 'screens/landing_screen.dart';
import 'services/notification_service.dart';
import 'services/theme_service.dart';
import 'theme/v_theme.dart';

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

    // Connexion anonyme : invisible pour l'utilisateur (aucun compte à créer),
    // mais elle donne à chaque appareil un identifiant Firebase. Cela permet
    // aux règles Firestore d'exiger `request.auth != null` et donc de bloquer
    // les accès depuis l'extérieur de l'app.
    //
    // ⚠️ Nécessite d'avoir activé le fournisseur « Anonyme » dans la console
    // Firebase (Authentication > Sign-in method > Anonymous > Activer).
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
  } catch (e) {
    debugPrint('Firebase init/auth échouée (groupes indisponibles) : $e');
  }

  // Charge le thème choisi par l'utilisateur (palette + polices).
  await ThemeService.load();

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
    // Se reconstruit dès que l'utilisateur change de palette ou de police.
    return ValueListenableBuilder<int>(
      valueListenable: ThemeService.revision,
      builder: (context, _, __) => MaterialApp(
        title: 'Vershoq',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: _buildTheme(),
        home: initialPersonName != null && initialPersonName!.isNotEmpty
            ? CameraScreen(personName: initialPersonName!)
            : const LandingScreen(),
      ),
    );
  }

  ThemeData _buildTheme() {
    final accent = VTheme.orange;

    // Texte et titres dans les polices choisies par l'utilisateur.
    final body = GoogleFonts.getTextTheme(VTheme.bodyFont)
        .apply(bodyColor: VTheme.warmDark, displayColor: VTheme.warmDark);
    final titles = GoogleFonts.getTextTheme(VTheme.titleFont)
        .apply(bodyColor: VTheme.warmDark, displayColor: VTheme.warmDark);
    final textTheme = body.copyWith(
      displayLarge: titles.displayLarge
          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.5),
      displayMedium: titles.displayMedium
          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
      displaySmall:
          titles.displaySmall?.copyWith(fontWeight: FontWeight.w700),
      headlineLarge:
          titles.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
      headlineMedium:
          titles.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
      headlineSmall:
          titles.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      titleLarge: titles.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: GoogleFonts.getFont(VTheme.bodyFont).fontFamily,
      textTheme: textTheme,
      colorScheme: ColorScheme.light(
        primary: accent,
        onPrimary: Colors.white,
        secondary: VTheme.coral,
        onSecondary: Colors.white,
        surface: VTheme.bgWarm,
        onSurface: VTheme.warmDark,
      ),
      scaffoldBackgroundColor: VTheme.bgWarm,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: VTheme.warmDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        thumbColor: accent,
        inactiveTrackColor: const Color(0xFFFFD9C2),
        valueIndicatorColor: accent,
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? accent
                : const Color(0xFFFFD9C2)),
        thumbColor: WidgetStateProperty.all(Colors.white),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: TextStyle(color: const Color(0xFF9A6B50).withOpacity(0.5)),
        prefixIconColor: accent,
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
          borderSide: BorderSide(color: accent, width: 2),
        ),
      ),
      cardColor: Colors.white,
    );
  }
}
