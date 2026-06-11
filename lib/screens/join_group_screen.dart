import 'package:flutter/material.dart';

import '../services/group_service.dart';
import '../widgets/form_widgets.dart';

class JoinGroupScreen extends StatefulWidget {
  const JoinGroupScreen({super.key});

  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  final _userCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _userCtrl.dispose();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final group = await GroupService.joinGroup(
        code: _codeCtrl.text,
        username: _userCtrl.text,
        email: _emailCtrl.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tu as rejoint « ${group.name} » !')),
        );
        Navigator.of(context).pop();
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
          const Text(
            'Rejoindre',
            style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text(
            'Entre le code que ton ami t\'a partagé.',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
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
            controller: _emailCtrl,
            label: 'Email',
            hint: 'toi@exemple.com',
            icon: Icons.alternate_email,
            keyboardType: TextInputType.emailAddress,
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
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black),
                  )
                : const Text('Rejoindre le groupe'),
          ),
        ],
      ),
    );
  }
}
