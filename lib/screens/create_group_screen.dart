import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import '../models/group.dart';
import '../services/group_service.dart';
import '../services/user_profile_service.dart';
import '../theme/v_theme.dart';
import '../widgets/form_widgets.dart';
import 'feed_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameCtrl  = TextEditingController();

  bool _submitting = false;
  String? _error;
  Group? _created;
  String? _photoBase64;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final compressed = await FlutterImageCompress.compressWithFile(
      File(picked.path).absolute.path,
      minWidth: 400,
      minHeight: 400,
      quality: 70,
      keepExif: false,
    );
    if (compressed != null && mounted) {
      setState(() => _photoBase64 = base64Encode(compressed));
    }
  }

  Future<void> _submit() async {
    setState(() { _submitting = true; _error = null; });
    try {
      final profile = await UserProfileService.current();
      if (profile == null) throw GroupException('Profil introuvable, reconnecte-toi.');
      final group = await GroupService.createGroup(
        name: _nameCtrl.text,
        username: profile.username,
        email: profile.email,
        photoBase64: _photoBase64,
        memberPhotoBase64: profile.photoBase64,
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
      body: _created != null ? _SuccessView(group: _created!) : _buildForm(),
    );
  }

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Nouveau groupe',
            style: VTheme.grotesk(
                color: VTheme.warmDark, fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Un code sera généré automatiquement pour inviter tes amis.',
            style: TextStyle(color: VTheme.warmMuted, fontSize: 14)),
        const SizedBox(height: 24),
        Center(
          child: GestureDetector(
            onTap: _pickPhoto,
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: VTheme.solarGradient,
                image: _photoBase64 != null
                    ? DecorationImage(
                        image: MemoryImage(base64Decode(_photoBase64!)),
                        fit: BoxFit.cover)
                    : null,
              ),
              child: _photoBase64 == null
                  ? const Center(
                      child: Icon(Icons.add_a_photo_outlined,
                          color: Colors.white, size: 28))
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text('Photo du groupe (optionnel)',
              style: TextStyle(color: VTheme.warmMuted, fontSize: 12)),
        ),
        const SizedBox(height: 20),
        AppTextField(
          controller: _nameCtrl,
          label: 'Nom du groupe',
          hint: 'Les potes du lycée',
          icon: Icons.groups_outlined,
          capitalization: TextCapitalization.words,
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          ErrorBanner(message: _error!),
        ],
        const SizedBox(height: 28),
        GradientButton(
          label: 'Créer le groupe',
          gradient: VTheme.solarGradient,
          shadows: VTheme.glowSolar,
          onPressed: _submitting ? null : _submit,
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
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: VTheme.solarGradient,
              shape: BoxShape.circle,
              boxShadow: VTheme.glowSolar,
            ),
            child: const Center(child: Text('✅', style: TextStyle(fontSize: 36))),
          ),
          const SizedBox(height: 20),
          Text(group.name,
              style: TextStyle(
                  color: VTheme.warmDark, fontSize: 26, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text('Groupe créé ! Partage ce code :',
              style: TextStyle(color: VTheme.warmMuted)),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: group.code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Code copié !')),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
              decoration: BoxDecoration(
                gradient: VTheme.solarGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: VTheme.glowSolar,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(group.code,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 8)),
                  const SizedBox(width: 12),
                  const Icon(Icons.copy, color: Colors.white70, size: 22),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text('Touche le code pour le copier',
              style: TextStyle(color: VTheme.warmMuted, fontSize: 12)),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: GradientButton(
              label: 'Accéder au groupe',
              gradient: VTheme.sunriseGradient,
              shadows: VTheme.glowSolar,
              onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const FeedScreen()),
                (route) => route.isFirst,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
