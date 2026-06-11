import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/group.dart';
import '../services/group_service.dart';
import '../widgets/form_widgets.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  bool _submitting = false;
  String? _error;
  Group? _created;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _userCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final group = await GroupService.createGroup(
        name: _nameCtrl.text,
        username: _userCtrl.text,
        email: _emailCtrl.text,
      );
      if (mounted) setState(() => _created = group);
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
      appBar: AppBar(title: const Text('Créer un groupe')),
      body: _created != null
          ? _SuccessView(group: _created!)
          : _buildForm(),
    );
  }

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('🎉', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        const Text(
          'Nouveau groupe',
          style: TextStyle(
              color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        const Text(
          'Un code sera généré automatiquement pour inviter tes amis.',
          style: TextStyle(color: Colors.white54, fontSize: 14),
        ),
        const SizedBox(height: 28),
        AppTextField(
          controller: _nameCtrl,
          label: 'Nom du groupe',
          hint: 'Les potes du lycée',
          icon: Icons.groups_outlined,
          capitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 16),
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
              : const Text('Créer le groupe'),
        ),
      ],
    );
  }
}

class _SuccessView extends StatelessWidget {
  final Group group;
  const _SuccessView({required this.group});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('✅', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          Text(
            group.name,
            style: const TextStyle(
                color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text('Groupe créé ! Partage ce code :',
              style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: group.code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Code copié !')),
              );
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    group.code,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 8,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.copy, color: Colors.black54, size: 22),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Touche le code pour le copier',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Terminé'),
            ),
          ),
        ],
      ),
    );
  }
}

