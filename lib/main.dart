import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'firebase_options.dart';
import 'screens/app_root.dart';
import 'screens/camera_screen.dart';
import 'services/notification_service.dart';
import 'services/push_service.dart';
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
  } catch (e) {
    debugPrint('Firebase init échouée (groupes indisponibles) : $e');
  }

  // Charge le thème choisi par l'utilisateur (palette + polices).
  await ThemeService.load();

  // Tap sur une notif locale (app ouverte ou en arrière-plan).
  await NotificationService.init(
    onTap: (payload) {
      // Seules les notifs d'ALERTE ouvrent la caméra (une photo par
      // alerte). Les autres (notif de test, anciennes versions) ouvrent
      // simplement l'app.
      final alertId = NotificationService.alertIdFromPayload(payload);
      if (alertId != null) openCameraForAlert(alertId);
    },
  );

  // Notifications push (FCM via serveur externe).
  // Tap sur une notif push quand l'app est en arrière-plan -> ouvre la caméra.
  PushService.onOpenAlert = openCameraForAlert;
  await PushService.init();

  // Schedule random notifications on first launch
  await NotificationService.scheduleRandom();

  // Faut-il ouvrir la caméra au lancement ? Uniquement si l'app a été lancée
  // en TAPANT une notif (locale ou push). Aucun accès réseau ici : l'alerte
  // est armée à partir des données du push.
  String? pendingAlertId;
  final localPayload = await NotificationService.getLaunchPayload();
  if (localPayload != null) {
    pendingAlertId = NotificationService.alertIdFromPayload(localPayload);
  }
  pendingAlertId ??= await PushService.initialTapAlert();

  runApp(const VershoqApp());

  // La caméra s'ouvre PAR-DESSUS l'accueil (jamais comme écran racine) : le
  // retour ramène toujours au fil / au compte.
  if (pendingAlertId != null) {
    final id = pendingAlertId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (FirebaseAuth.instance.currentUser != null) openCameraForAlert(id);
    });
  }
}

/// Ouvre la caméra pour une alerte, par-dessus l'écran courant (sauf si une
/// caméra est déjà ouverte).
void openCameraForAlert(String alertId) {
  _pushCamera(CameraScreen(alertId: alertId));
}

void _pushCamera(CameraScreen screen) {
  if (CameraScreen.isOpen) return;
  navigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => screen),
  );
}

class VershoqApp extends StatelessWidget {
  const VershoqApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Se reconstruit dès que l'utilisateur change de palette ou de police.
    return ValueListenableBuilder<int>(
      valueListenable: ThemeService.revision,
      builder: (context, _, __) => MaterialApp(
        title: "Snap'It",
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: _buildTheme(),
        home: const AppRoot(),
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
      brightness: VTheme.isDark ? Brightness.dark : Brightness.light,
      fontFamily: GoogleFonts.getFont(VTheme.bodyFont).fontFamily,
      textTheme: textTheme,
      colorScheme: ColorScheme(
        brightness: VTheme.isDark ? Brightness.dark : Brightness.light,
        primary: accent,
        onPrimary: Colors.white,
        secondary: VTheme.coral,
        onSecondary: Colors.white,
        error: VTheme.coral,
        onError: Colors.white,
        surface: VTheme.surface,
        onSurface: VTheme.warmDark,
      ),
      scaffoldBackgroundColor: VTheme.bgWarm,
      appBarTheme: AppBarTheme(
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
        inactiveTrackColor: VTheme.hairline,
        valueIndicatorColor: accent,
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? accent : VTheme.hairline),
        thumbColor: WidgetStateProperty.all(Colors.white),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: VTheme.surface,
        hintStyle: TextStyle(color: VTheme.warmMuted.withOpacity(0.6)),
        prefixIconColor: accent,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: VTheme.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: VTheme.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: accent, width: 2),
        ),
      ),
      cardColor: VTheme.surface,
    );
  }
}
