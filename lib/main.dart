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
                  // Vérifie l'email en rafraîchissant le statut APRÈS la
                  // restauration de session (sinon l'ancien statut « non
                  // vérifié » en cache renverrait sur l'écran de vérification à
                  // chaque ouverture).
                  return _AuthGate(user: user);
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

/// Décide, après restauration de session, si on affiche le compte ou l'écran
/// de vérification d'email. Rafraîchit le statut d'abord pour ne pas rester
/// bloqué sur « email non vérifié » alors qu'il l'a été.
class _AuthGate extends StatefulWidget {
  final User user;
  const _AuthGate({required this.user});

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _checking = true;
  bool _verified = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    var verified = widget.user.emailVerified;
    if (!verified) {
      try {
        await widget.user.reload();
        verified =
            FirebaseAuth.instance.currentUser?.emailVerified ?? verified;
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _verified = verified;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return Scaffold(
        backgroundColor: VTheme.bgWarm,
        body: Center(child: CircularProgressIndicator(color: VTheme.orange)),
      );
    }
    return _verified ? const AccountScreen() : const VerifyEmailScreen();
  }
}
