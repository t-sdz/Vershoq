import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import '../models/group.dart';
import '../services/group_service.dart';
import '../services/theme_service.dart';
import '../theme/v_theme.dart';
import 'create_group_screen.dart';
import 'join_group_screen.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  Group? _current;
  GroupMember? _user;
  List<GroupMember> _members = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // refreshCurrentGroup recharge nom + admins depuis Firestore.
    final group = await GroupService.refreshCurrentGroup();
    final user = await GroupService.getCurrentUser();
    List<GroupMember> members = [];
    if (group != null) {
      try {
        members = await GroupService.getMembers(group.id);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _current = group;
        _user = user;
        _members = members;
        _loading = false;
      });
    }
  }

  Future<void> _leave() async {
    await GroupService.leaveGroup();
    await _load();
  }

  Future<void> _removeMember(GroupMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Supprimer le membre',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Supprimer ${member.username} du groupe ?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Annuler', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true && _current != null) {
      await GroupService.removeMember(_current!.id, member.email);
      await _load();
    }
  }

  Future<void> _rename() async {
    if (_current == null) return;
    final controller = TextEditingController(text: _current!.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renommer le groupe'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Nom du groupe'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Renommer')),
        ],
      ),
    );
    if (newName != null && newName.trim().isNotEmpty) {
      try {
        await GroupService.renameGroup(_current!.id, newName);
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }
  }

  Future<void> _changeGroupPhoto() async {
    if (_current == null) return;
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
    if (compressed == null) return;
    try {
      await GroupService.updateGroupPhoto(_current!.id, base64Encode(compressed));
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  void _showProfile(GroupMember m, bool isMe) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isMe ? 'Ton profil' : 'Profil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: VTheme.solarGradient,
                image: m.photoBase64 != null
                    ? DecorationImage(
                        image: MemoryImage(base64Decode(m.photoBase64!)),
                        fit: BoxFit.cover)
                    : null,
              ),
              child: m.photoBase64 == null
                  ? Center(
                      child: Text(
                        m.username.isNotEmpty ? m.username[0].toUpperCase() : '?',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 14),
            Text(m.username,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text(m.email, style: TextStyle(color: VTheme.warmMuted, fontSize: 13)),
            if (isMe) ...[
              const SizedBox(height: 8),
              Text('C\'est toi !',
                  style: TextStyle(color: VTheme.orange, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
        ],
      ),
    );
  }

  Future<void> _setAdmin(GroupMember member, bool makeAdmin) async {
    if (_current == null) return;
    try {
      if (makeAdmin) {
        await GroupService.addAdmin(_current!.id, member.email);
      } else {
        await GroupService.removeAdmin(_current!.id, member.email);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThemedScope(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Groupe')),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: VTheme.orange))
            : _current != null
                ? _buildCurrentGroup()
                : _buildChoice(),
      ),
    );
  }

  Widget _buildChoice() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('👥', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          Text(
            'Rejoins tes amis',
            style: TextStyle(
              color: VTheme.warmDark,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Crée un groupe ou rejoins-en un avec un code\npour partager vos moments spontanés.',
            textAlign: TextAlign.center,
            style: TextStyle(color: VTheme.warmMuted, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _open(const CreateGroupScreen()),
              child: const Text('Créer un groupe'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: VTheme.orange,
                side: BorderSide(color: VTheme.orange.withOpacity(0.5)),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              onPressed: () => _open(const JoinGroupScreen()),
              child: const Text('Rejoindre un groupe',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentGroup() {
    final group = _current!;
    final isAdmin = group.isAdmin(_user?.email);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: VTheme.solarGradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: VTheme.glowSolar,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('TON GROUPE',
                      style: TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          letterSpacing: 2,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (isAdmin)
                    GestureDetector(
                      onTap: _changeGroupPhoto,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white24,
                          border: Border.all(color: Colors.white54, width: 1.5),
                          image: group.photoBase64 != null
                              ? DecorationImage(
                                  image: MemoryImage(base64Decode(group.photoBase64!)),
                                  fit: BoxFit.cover)
                              : null,
                        ),
                        child: group.photoBase64 == null
                            ? const Icon(Icons.add_a_photo_outlined,
                                color: Colors.white, size: 18)
                            : null,
                      ),
                    )
                  else if (group.photoBase64 != null)
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        image: DecorationImage(
                            image: MemoryImage(base64Decode(group.photoBase64!)),
                            fit: BoxFit.cover),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(group.name,
                        style: VTheme.grotesk(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w800)),
                  ),
                  if (isAdmin)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined,
                          color: Colors.white, size: 22),
                      tooltip: 'Renommer le groupe',
                      onPressed: _rename,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Code : ',
                      style: TextStyle(color: Colors.white54)),
                  Text(
                    group.code,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Text('MEMBRES (${_members.length})',
                style: TextStyle(
                    color: VTheme.warmMuted,
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold)),
            if (isAdmin) ...[
              const SizedBox(width: 8),
              const Text('· ADMIN',
                  style: TextStyle(
                      color: Color(0xFFBB8860),
                      fontSize: 11,
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold)),
            ],
          ],
        ),
        const SizedBox(height: 8),
        ..._members.map((m) {
          final mIsAdmin = group.isAdmin(m.email);
          final mIsCreator = m.email == group.createdByEmail;
          final mIsMe = m.email == _user?.email;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: () => _showProfile(m, mIsMe),
            leading: CircleAvatar(
              backgroundColor: mIsAdmin
                  ? VTheme.orange
                  : VTheme.orange.withOpacity(0.30),
              backgroundImage:
                  m.photoBase64 != null ? MemoryImage(base64Decode(m.photoBase64!)) : null,
              child: m.photoBase64 == null
                  ? Text(
                      m.username.isNotEmpty ? m.username[0].toUpperCase() : '?',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(m.username,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: VTheme.warmDark,
                          fontWeight: FontWeight.w600)),
                ),
                if (mIsAdmin) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: VTheme.orange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(mIsCreator ? 'créateur' : 'admin',
                        style: TextStyle(
                            color: VTheme.orange,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
            subtitle: Text(m.email,
                style: TextStyle(color: VTheme.warmMuted, fontSize: 12)),
            trailing: _memberTrailing(group, m, isAdmin, mIsAdmin, mIsCreator),
          );
        }),
        const SizedBox(height: 24),
        TextButton(
          onPressed: _leave,
          child: const Text('Quitter le groupe',
              style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    );
  }

  Widget? _memberTrailing(Group group, GroupMember m, bool viewerIsAdmin,
      bool mIsAdmin, bool mIsCreator) {
    if (m.email == _user?.email) {
      return Text('moi',
          style: TextStyle(color: VTheme.warmMuted, fontSize: 12));
    }
    // Seuls les admins agissent ; le créateur ne peut être ni rétrogradé ni exclu.
    if (!viewerIsAdmin || mIsCreator) return null;
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: VTheme.warmMuted),
      onSelected: (value) {
        switch (value) {
          case 'promote':
            _setAdmin(m, true);
            break;
          case 'demote':
            _setAdmin(m, false);
            break;
          case 'remove':
            _removeMember(m);
            break;
        }
      },
      itemBuilder: (_) => [
        if (!mIsAdmin)
          const PopupMenuItem(value: 'promote', child: Text('Rendre admin')),
        if (mIsAdmin)
          const PopupMenuItem(value: 'demote', child: Text('Retirer admin')),
        const PopupMenuItem(
            value: 'remove',
            child: Text('Supprimer du groupe',
                style: TextStyle(color: Colors.redAccent))),
      ],
    );
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
    _load();
  }
}
