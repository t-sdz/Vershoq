import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/user_profile_service.dart';
import '../theme/v_theme.dart';
import '../widgets/form_widgets.dart';

/// Page 3 — Infos du compte : nom, photo de profil, pseudo, email, mot de
/// passe.
class AccountInfoScreen extends StatefulWidget {
  const AccountInfoScreen({super.key});

  @override
  State<AccountInfoScreen> createState() => _AccountInfoScreenState();
}

class _AccountInfoScreenState extends State<AccountInfoScreen> {
  UserProfile? _profile;
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _currentPasswordCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await UserProfileService.current();
    if (mounted) {
      setState(() {
        _profile = profile;
        _nameCtrl.text = profile?.name ?? '';
        _usernameCtrl.text = profile?.username ?? '';
        _loading = false;
      });
    }
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 85);
    if (picked == null || _profile == null) return;
    setState(() => _saving = true);
    try {
      final updated =
          await UserProfileService.updatePhoto(_profile!, File(picked.path));
      if (mounted) setState(() => _profile = updated);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveInfo() async {
    if (_profile == null) return;
    setState(() {
      _saving = true;
      _error = null;
      _info = null;
    });
    try {
      final updated = _profile!.copyWith(
        name: _nameCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
      );
      await UserProfileService.updateProfile(updated);
      if (mounted) {
        setState(() {
          _profile = updated;
          _info = 'Informations enregistrées !';
        });
      }
    } catch (e) {
      setState(() => _error = 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    if (_currentPasswordCtrl.text.isEmpty) {
      setState(() => _error = 'Entre ton mot de passe actuel.');
      return;
    }
    if (_passwordCtrl.text.trim().length < 6) {
      setState(() => _error = 'Mot de passe trop court (6 caractères minimum).');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _info = null;
    });
    try {
      await AuthService.updatePassword(
        currentPassword: _currentPasswordCtrl.text,
        newPassword: _passwordCtrl.text.trim(),
      );
      _currentPasswordCtrl.clear();
      _passwordCtrl.clear();
      if (mounted) setState(() => _info = 'Mot de passe mis à jour !');
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _viewPhoto() {
    final photo = _profile?.photoBase64;
    if (photo == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.transparent, foregroundColor: Colors.white),
        body: Center(child: InteractiveViewer(child: Image.memory(base64Decode(photo)))),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
          backgroundColor: VTheme.bgWarm,
          body: Center(child: CircularProgressIndicator(color: VTheme.orange)));
    }
    final photo = _profile?.photoBase64;
    return Scaffold(
      backgroundColor: VTheme.bgWarm,
      appBar: AppBar(title: const Text('Gestion du compte')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Stack(
              children: [
                GestureDetector(
                  onTap: photo != null ? _viewPhoto : (_saving ? null : _pickPhoto),
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: VTheme.solarGradient,
                      image: photo != null
                          ? DecorationImage(
                              image: MemoryImage(base64Decode(photo)),
                              fit: BoxFit.cover)
                          : null,
                    ),
                    child: photo == null
                        ? Center(
                            child: Text(
                              _profile?.username.isNotEmpty == true
                                  ? _profile!.username[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold),
                            ),
                          )
                        : null,
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _saving ? null : _pickPhoto,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                          color: VTheme.warmDark, shape: BoxShape.circle),
                      child: const Icon(Icons.camera_alt,
                          color: Colors.white, size: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
          Text('Email',
              style:
                  TextStyle(color: VTheme.warmDark, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(_profile?.email ?? '',
              style: TextStyle(color: VTheme.warmMuted, fontSize: 15)),
          const SizedBox(height: 24),
          GradientButton(
            label: 'Enregistrer',
            gradient: VTheme.solarGradient,
            shadows: VTheme.glowSolar,
            onPressed: _saving ? null : _saveInfo,
          ),
          const SizedBox(height: 32),
          Divider(color: VTheme.hairline),
          const SizedBox(height: 16),
          Text('Changer le mot de passe',
              style:
                  TextStyle(color: VTheme.warmDark, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          AppTextField(
              controller: _currentPasswordCtrl,
              label: 'Mot de passe actuel',
              hint: 'Ton mot de passe actuel',
              icon: Icons.lock_person_outlined,
              obscureText: true),
          const SizedBox(height: 12),
          AppTextField(
              controller: _passwordCtrl,
              label: 'Nouveau mot de passe',
              hint: '6 caractères minimum',
              icon: Icons.lock_outline,
              obscureText: true),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _saving ? null : _changePassword,
            child: const Text('Mettre à jour le mot de passe'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            ErrorBanner(message: _error!),
          ],
          if (_info != null) ...[
            const SizedBox(height: 16),
            Text(_info!, style: TextStyle(color: VTheme.orange, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}
