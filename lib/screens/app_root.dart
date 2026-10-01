import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth, User;
import 'package:flutter/material.dart';

import '../services/group_service.dart';
import '../theme/v_theme.dart';
import 'account_screen.dart';
import 'login_screen.dart';
import 'main_shell.dart';
import 'verify_email_screen.dart';

/// Racine de l'app : écoute l'état de connexion, vérifie l'email, puis
/// envoie vers l'accueil (MainShell si on a un groupe, sinon Mon compte).
///
/// Toutes les navigations « retour à l'accueil » (connexion, déconnexion,
/// groupe rejoint / créé / quitté…) font un pushAndRemoveUntil vers AppRoot :
/// on garde ainsi toujours l'écoute de la connexion.
class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Loading();
        }
        final user = snap.data;
        if (user == null) return const LoginScreen();
        // Vérifie l'email en rafraîchissant le statut APRÈS la restauration
        // de session (sinon l'ancien statut « non vérifié » en cache
        // renverrait sur l'écran de vérification à chaque ouverture).
        return _AuthGate(key: ValueKey(user.uid), user: user);
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VTheme.bgWarm,
      body: Center(child: CircularProgressIndicator(color: VTheme.orange)),
    );
  }
}

/// Décide, après restauration de session, si on affiche l'accueil ou l'écran
/// de vérification d'email. Rafraîchit le statut d'abord pour ne pas rester
/// bloqué sur « email non vérifié » alors qu'il l'a été.
class _AuthGate extends StatefulWidget {
  final User user;
  const _AuthGate({super.key, required this.user});

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _checking = true;
  bool _verified = false;
  bool _hasGroup = false;

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
    // Accueil : le fil (avec la barre de navigation) si on a un groupe.
    var hasGroup = false;
    try {
      hasGroup = await GroupService.getCurrentGroup() != null;
    } catch (_) {}
    if (mounted) {
      setState(() {
        _verified = verified;
        _hasGroup = hasGroup;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) return const _Loading();
    if (!_verified) return const VerifyEmailScreen();
    return _hasGroup ? const MainShell() : const AccountScreen();
  }
}
