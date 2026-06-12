import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/v_theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl  = TextEditingController();

  bool _isLogin   = true;
  bool _loading   = false;
  bool _obscure   = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email    = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirm  = _confirmCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Remplis tous les champs.');
      return;
    }
    if (!_isLogin && password != confirm) {
      setState(() => _error = 'Les mots de passe ne correspondent pas.');
      return;
    }
    if (!_isLogin && password.length < 6) {
      setState(() => _error = 'Le mot de passe doit faire au moins 6 caractères.');
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      if (_isLogin) {
        await AuthService.signIn(email: email, password: password);
      } else {
        await AuthService.register(email: email, password: password);
      }
      // Navigation gérée par le StreamBuilder dans main.dart
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = AuthService.friendlyError(e.code));
    } catch (e) {
      if (mounted) setState(() => _error = 'Erreur inattendue.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 60),

                // Logo
                ShaderMask(
                  shaderCallback: (b) => VTheme.solarGradient.createShader(b),
                  child: const Text(
                    'Vershoq',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 56,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -2),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _isLogin ? 'Bon retour ☀️' : 'Crée ton compte ✨',
                  style: const TextStyle(color: VTheme.warmMuted, fontSize: 16),
                ),
                const SizedBox(height: 40),

                // Email
                _Label('Email'),
                const SizedBox(height: 6),
                _Field(
                  controller: _emailCtrl,
                  hint: 'toi@exemple.com',
                  icon: Icons.alternate_email,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),

                // Mot de passe
                _Label('Mot de passe'),
                const SizedBox(height: 6),
                _Field(
                  controller: _passwordCtrl,
                  hint: '••••••••',
                  icon: Icons.lock_outline,
                  obscure: _obscure,
                  suffix: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: VTheme.warmMuted, size: 20),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),

                // Confirmer mot de passe (register only)
                if (!_isLogin) ...[
                  const SizedBox(height: 16),
                  _Label('Confirmer le mot de passe'),
                  const SizedBox(height: 6),
                  _Field(
                    controller: _confirmCtrl,
                    hint: '••••••••',
                    icon: Icons.lock_outline,
                    obscure: true,
                  ),
                ],

                // Erreur
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: VTheme.coral.withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: VTheme.coral, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: VTheme.coral, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 28),

                // Bouton principal
                SizedBox(
                  width: double.infinity,
                  child: GradientButton(
                    label: _isLogin ? 'Se connecter' : 'Créer un compte',
                    gradient: VTheme.solarGradient,
                    shadows: VTheme.glowSolar,
                    onPressed: _loading ? null : _submit,
                  ),
                ),

                const SizedBox(height: 20),

                // Toggle login / register
                Center(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _isLogin = !_isLogin;
                      _error = null;
                    }),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(color: VTheme.warmMuted, fontSize: 14),
                        children: [
                          TextSpan(
                              text: _isLogin
                                  ? 'Pas encore de compte ? '
                                  : 'Déjà un compte ? '),
                          TextSpan(
                            text: _isLogin ? 'S\'inscrire' : 'Se connecter',
                            style: const TextStyle(
                                color: VTheme.orange,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: VTheme.warmDark, fontSize: 13, fontWeight: FontWeight.w700));
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final Widget? suffix;

  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.keyboardType,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: VTheme.warmDark),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: VTheme.orange),
        suffixIcon: suffix,
      ),
    );
  }
}
