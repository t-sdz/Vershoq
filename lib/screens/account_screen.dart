import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/group_service.dart';
import '../services/user_profile_service.dart';
import '../theme/v_theme.dart';
import 'account_info_screen.dart';
import 'create_group_screen.dart';
import 'feed_screen.dart';
import 'gallery_screen.dart';
import 'join_group_screen.dart';
import 'login_screen.dart';
import 'settings_screen.dart';

/// Page 2 — Compte : mes groupes, rejoindre/créer, paramètres, galerie
/// perso globale, gestion du compte.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  UserProfile? _profile;
  List<JoinedGroup> _groups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await UserProfileService.current();
    final groups = await GroupService.getJoinedGroups();
    if (mounted) {
      setState(() {
        _profile = profile;
        _groups = groups;
        _loading = false;
      });
    }
  }

  Future<void> _openGroup(String groupId) async {
    await GroupService.setActiveGroup(groupId);
    if (mounted) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const FeedScreen()))
          .then((_) => _load());
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _load();
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
    return Scaffold(
      backgroundColor: VTheme.bgWarm,
      appBar: AppBar(title: const Text('Mon compte')),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: VTheme.orange))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildProfileCard(),
                const SizedBox(height: 28),
                Text('MES GROUPES',
                    style: TextStyle(
                        color: VTheme.warmMuted,
                        fontSize: 11,
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                if (_groups.isEmpty)
                  Text('Tu n\'as encore rejoint aucun groupe.',
                      style: TextStyle(color: VTheme.warmMuted, fontSize: 13))
                else
                  ..._groups.map((j) => Card(
                        color: VTheme.surface,
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                                gradient: VTheme.solarGradient,
                                shape: BoxShape.circle),
                            child: Center(
                              child: Text(
                                  j.group.name.isNotEmpty
                                      ? j.group.name[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                          title: Text(j.group.name,
                              style: TextStyle(
                                  color: VTheme.warmDark,
                                  fontWeight: FontWeight.w700)),
                          trailing: Icon(Icons.chevron_right_rounded,
                              color: VTheme.warmMuted),
                          onTap: () => _openGroup(j.group.id),
                        ),
                      )),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _open(const JoinGroupScreen()),
                        icon: const Icon(Icons.group_add_outlined),
                        label: const Text('Rejoindre'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _open(const CreateGroupScreen()),
                        icon: const Icon(Icons.add),
                        label: const Text('Créer'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                _tile(
                  icon: Icons.settings_outlined,
                  label: 'Paramètres',
                  onTap: () => _open(const SettingsScreen()),
                ),
                _tile(
                  icon: Icons.photo_library_outlined,
                  label: 'Galerie perso',
                  onTap: () => _open(
                      const GalleryScreen(personalOnly: true, allGroups: true)),
                ),
                _tile(
                  icon: Icons.manage_accounts_outlined,
                  label: 'Gestion du compte',
                  onTap: () => _open(const AccountInfoScreen()),
                ),
                const SizedBox(height: 12),
                _tile(
                  icon: Icons.logout_rounded,
                  label: 'Déconnexion',
                  color: VTheme.coral,
                  onTap: _signOut,
                ),
              ],
            ),
    );
  }

  Widget _buildProfileCard() {
    final p = _profile;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: VTheme.solarGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: VTheme.glowSolar,
      ),
      child: Row(
        children: [
          _avatar(p),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p?.name ?? '...',
                    style: VTheme.grotesk(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('@${p?.username ?? ''}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(UserProfile? p) {
    final photo = p?.photoBase64;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white24,
        border: Border.all(color: Colors.white38, width: 2),
        image: photo != null
            ? DecorationImage(
                image: MemoryImage(base64Decode(photo)), fit: BoxFit.cover)
            : null,
      ),
      child: photo == null
          ? Center(
              child: Text(
                p?.username.isNotEmpty == true
                    ? p!.username[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
              ),
            )
          : null,
    );
  }

  Widget _tile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final c = color ?? VTheme.warmDark;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 38,
        height: 38,
        decoration:
            BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: c, size: 20),
      ),
      title: Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }
}
