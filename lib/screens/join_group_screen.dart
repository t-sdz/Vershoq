import 'package:flutter/material.dart';

import '../services/group_service.dart';
import '../theme/v_theme.dart';
import '../widgets/form_widgets.dart';
import 'feed_screen.dart';

class JoinGroupScreen extends StatefulWidget {
  const JoinGroupScreen({super.key});

  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  final _userCtrl  = TextEditingController();
  final _codeCtrl  = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _userCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() { _submitting = true; _error = null; });
    try {
      await GroupService.joinGroup(
        code: _codeCtrl.text,
        username: _userCtrl.text,
      );
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const FeedScreen()),
          (route) => route.isFirst,
        );
      }
    } on GroupException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Erreur inattendue : $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rejoindre un groupe')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('🔑', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          const Text('Rejoindre',
              style: TextStyle(
                  color: VTheme.warmDark,
                  fontSize: 24,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('Entre le code que ton ami t\'a partagé.',
              style: TextStyle(color: VTheme.warmMuted, fontSize: 14)),
          const SizedBox(height: 28),
          AppTextField(
            controller: _userCtrl,
            label: 'Nom d\'utilisateur',
            hint: 'Ton pseudo',
            icon: Icons.person_outline,
            capitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _codeCtrl,
            label: 'Code du groupe',
            hint: 'Ex : ABC123',
            icon: Icons.vpn_key_outlined,
            capitalization: TextCapitalization.characters,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: 28),
          GradientButton(
            label: 'Rejoindre le groupe',
            gradient: VTheme.skyGradient,
            shadows: [
              BoxShadow(
                  color: VTheme.sky.withOpacity(0.4),
                  blurRadius: 30,
                  offset: const Offset(0, 12))
            ],
            onPressed: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }
}
