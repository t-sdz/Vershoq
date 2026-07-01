import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/v_theme.dart';
import '../widgets/form_widgets.dart';
import 'account_screen.dart';
import 'signup_screen.dart';

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
      await AuthService.signIn(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
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
            const SizedBox(height: 24),
            GradientButton(
              label: 'Se connecter',
              gradient: VTheme.solarGradient,
              shadows: VTheme.glowSolar,
              onPressed: _submitting ? null : _submit,
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
