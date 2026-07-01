import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/user_profile_service.dart';
import '../theme/v_theme.dart';
import '../widgets/form_widgets.dart';
import 'account_screen.dart';
import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
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
      final user = await AuthService.signUp(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
      );
      await UserProfileService.createProfile(
        uid: user.uid,
        name: _nameCtrl.text,
        username: _usernameCtrl.text,
        email: _emailCtrl.text,
      );
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AccountScreen()),
          (_) => false,
        );
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Erreur inattendue : $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VTheme.bgWarm,
      appBar: AppBar(title: const Text('Créer un compte')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text("Bienvenue sur Snap'It",
              style: VTheme.grotesk(
                  color: VTheme.warmDark,
                  fontSize: 26,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Crée ton compte pour commencer.',
              style: TextStyle(color: VTheme.warmMuted, fontSize: 14)),
          const SizedBox(height: 28),
          AppTextField(
              controller: _nameCtrl,
              label: 'Nom',
              hint: 'Ton nom',
              icon: Icons.badge_outlined,
              capitalization: TextCapitalization.words),
          const SizedBox(height: 16),
          AppTextField(
              controller: _usernameCtrl,
              label: 'Pseudo',
              hint: 'Ton pseudo',
              icon: Icons.person_outline,
              capitalization: TextCapitalization.words),
          const SizedBox(height: 16),
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
              hint: '6 caractères minimum',
              icon: Icons.lock_outline,
              obscureText: true),
          if (_error != null) ...[
            const SizedBox(height: 16),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: 28),
          GradientButton(
            label: 'Créer mon compte',
            gradient: VTheme.solarGradient,
            shadows: VTheme.glowSolar,
            onPressed: _submitting ? null : _submit,
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen())),
            child: Text('Déjà un compte ? Se connecter',
                style: TextStyle(color: VTheme.orange)),
          ),
        ],
      ),
    );
  }
}
