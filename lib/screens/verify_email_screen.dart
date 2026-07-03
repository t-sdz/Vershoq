import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/v_theme.dart';
import '../widgets/form_widgets.dart';
import 'account_screen.dart';
import 'login_screen.dart';

/// Écran affiché tant que l'email n'est pas vérifié.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _busy = false;
  String? _info;

  @override
  void initState() {
    super.initState();
    // Envoie automatiquement un premier email de vérification.
    AuthService.sendEmailVerification();
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _info = null;
    });
    final verified = await AuthService.reloadAndCheckVerified();
    if (!mounted) return;
    if (verified) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AccountScreen()),
        (_) => false,
      );
    } else {
      setState(() {
        _busy = false;
        _info = 'Pas encore vérifié. Clique sur le lien dans l\'email.';
      });
    }
  }

  Future<void> _resend() async {
    setState(() => _busy = true);
    await AuthService.sendEmailVerification();
    if (mounted) {
      setState(() {
        _busy = false;
        _info = 'Email de vérification renvoyé !';
      });
    }
  }

  Future<void> _signOut() async {
    await AuthService.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = AuthService.currentUser?.email ?? '';
    return Scaffold(
      backgroundColor: VTheme.bgWarm,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mark_email_unread_outlined,
                  size: 72, color: VTheme.orange),
              const SizedBox(height: 20),
              Text('Vérifie ton email',
                  style: VTheme.grotesk(
                      color: VTheme.warmDark,
                      fontSize: 24,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Text(
                'On a envoyé un lien de vérification à\n$email.\nOuvre-le, puis reviens ici.',
                textAlign: TextAlign.center,
                style: TextStyle(color: VTheme.warmMuted, fontSize: 14, height: 1.4),
              ),
              if (_info != null) ...[
                const SizedBox(height: 16),
                Text(_info!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: VTheme.orange, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 28),
              GradientButton(
                label: 'J\'ai vérifié mon email',
                gradient: VTheme.solarGradient,
                shadows: VTheme.glowSolar,
                onPressed: _busy ? null : _check,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _busy ? null : _resend,
                child: Text('Renvoyer l\'email',
                    style: TextStyle(color: VTheme.orange)),
              ),
              TextButton(
                onPressed: _signOut,
                child: Text('Se déconnecter',
                    style: TextStyle(color: VTheme.warmMuted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
