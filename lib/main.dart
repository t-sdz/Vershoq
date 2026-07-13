import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth, User;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'firebase_options.dart';
import 'screens/account_screen.dart';
import 'screens/camera_screen.dart';
import 'screens/login_screen.dart';
import 'screens/verify_email_screen.dart';
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

  // Rafraîchit le statut de l'utilisateur (email vérifié, session). Sans ça,
  // l'app garde en cache l'ancien statut « non vérifié » et renvoie sur
  // l'écran de vérification / connexion à chaque ouverture.
  try {
    await FirebaseAuth.instance.currentUser?.reload();
  } catch (_) {}

  // Charge le thème choisi par l'utilisateur (palette + polices).
  await ThemeService.load();

  await NotificationService.init(
    onTap: (payload) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => CameraScreen(personName: payload),
        ),
      );
    },
  );

  // Notifications push (FCM via serveur externe).
  // Tap sur une notif push quand l'app est en arrière-plan -> ouvre la caméra.
  PushService.onOpen = (label) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => CameraScreen(personName: label),
      ),
    );
  };
  await PushService.init();

  // Schedule random notifications on first launch
  await NotificationService.scheduleRandom();

  // Faut-il ouvrir directement la caméra au lancement ?
  //  - notif locale tapée, OU
  //  - notif push tapée (app tuée), MÊME si les prénoms sont vides, OU
  //  - un moment photo est encore actif (ouverture juste après une alerte).
  String? initial;
  var openCamera = false;

  final localPayload = await NotificationService.getLaunchPayload();
  if (localPayload != null) {
    initial = localPayload;
    openCamera = true;
  }
  if (!openCamera) {
    // Renvoie null si la notif n'a PAS été tapée ; sinon le label (parfois vide).
    final tapped = await PushService.initialTapLabel();
    if (tapped != null) {
      initial = tapped;
      openCamera = true;
    }
  }
  if (!openCamera &&
      FirebaseAuth.instance.currentUser?.emailVerified == true) {
    final moment = await NotificationService.activeMomentLabel();
    if (moment != null) {
      initial = moment;
      openCamera = true;
    }
  }

  runApp(VershoqApp(initialPersonName: initial, openCamera: openCamera));
}

class VershoqApp extends StatelessWidget {
  final String? initialPersonName;
  final bool openCamera;

  const VershoqApp(
      {super.key, this.initialPersonName, this.openCamera = false});

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
        home: openCamera
            ? CameraScreen(personName: initialPersonName ?? '')
            : StreamBuilder<User?>(
                stream: FirebaseAuth.instance.authStateChanges(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return Scaffold(
                      backgroundColor: VTheme.bgWarm,
                      body: Center(
                          child: CircularProgressIndicator(color: VTheme.orange)),
                    );
                  }
                  final user = snap.data;
                  if (user == null) return const LoginScreen();
                  // Email non vérifié (sauf comptes Google déjà vérifiés).
                  if (!user.emailVerified) return const VerifyEmailScreen();
                  return const AccountScreen();
                },
              ),
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
