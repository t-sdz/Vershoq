import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/user_profile_service.dart';
import '../theme/v_theme.dart';
import '../widgets/form_widgets.dart';
import 'account_screen.dart';
import 'signup_screen.dart';
import 'verify_email_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final user = await AuthService.signIn(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
      );
      if (mounted) _goAfterAuth(user.emailVerified);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Erreur inattendue : $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _google() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final user = await AuthService.signInWithGoogle();
      await UserProfileService.ensureProfile(
        uid: user.uid,
        email: user.email ?? '',
        displayName: user.displayName,
      );
      if (mounted) _goAfterAuth(user.emailVerified);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Connexion Google impossible : $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Entre ton email d\'abord.');
      return;
    }
    try {
      await AuthService.sendPasswordReset(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Email de réinitialisation envoyé !')),
        );
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    }
  }

  void _goAfterAuth(bool verified) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (_) =>
              verified ? const AccountScreen() : const VerifyEmailScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VTheme.bgWarm,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 40),
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: VTheme.glowSolar),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Image.asset('assets/icon/icon.png', fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 16),
            ShaderMask(
              shaderCallback: (b) => VTheme.solarGradient.createShader(b),
              child: Text("Snap'It",
                  style: VTheme.grotesk(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 28),
            AppTextField(
                controller: _emailCtrl,
                label: 'Email',
                hint: 'toi@exemple.com',
                icon: Icons.alternate_email,
                keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 16),
            AppTextField(
                controller: _passwordCtrl,
                label: 'Mot de passe',
                hint: 'Ton mot de passe',
                icon: Icons.lock_outline,
                obscureText: true),
            if (_error != null) ...[
              const SizedBox(height: 16),
              ErrorBanner(message: _error!),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _submitting ? null : _forgotPassword,
                child: Text('Mot de passe oublié ?',
                    style: TextStyle(color: VTheme.warmMuted, fontSize: 13)),
              ),
            ),
            const SizedBox(height: 8),
            GradientButton(
              label: 'Se connecter',
              gradient: VTheme.solarGradient,
              shadows: VTheme.glowSolar,
              onPressed: _submitting ? null : _submit,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Divider(color: VTheme.hairline)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('ou',
                      style: TextStyle(color: VTheme.warmMuted, fontSize: 13)),
                ),
                Expanded(child: Divider(color: VTheme.hairline)),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _submitting ? null : _google,
              icon: const Icon(Icons.g_mobiledata, size: 28),
              label: const Text('Continuer avec Google'),
              style: OutlinedButton.styleFrom(
                foregroundColor: VTheme.warmDark,
                side: BorderSide(color: VTheme.hairline),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const SignupScreen())),
              child: Text('Pas encore de compte ? Inscription',
                  style: TextStyle(color: VTheme.orange)),
            ),
          ],
        ),
      ),
    );
  }
}
