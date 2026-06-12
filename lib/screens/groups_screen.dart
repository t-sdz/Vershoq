import 'package:flutter/material.dart';

import '../models/group.dart';
import '../services/auth_service.dart';
import '../services/group_service.dart';
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
    final group = await GroupService.getCurrentGroup();
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
      await GroupService.removeMember(_current!.id, member.uid);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Groupe')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _current != null
              ? _buildCurrentGroup()
              : _buildChoice(),
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
          const Text(
            'Rejoins tes amis',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Crée un groupe ou rejoins-en un avec un code\npour partager vos moments spontanés.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.4),
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
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
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
    final isAdmin = group.createdByUid == AuthService.currentUid;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('TON GROUPE',
                  style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(group.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
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
                style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold)),
            if (isAdmin) ...[
              const SizedBox(width: 8),
              const Text('· ADMIN',
                  style: TextStyle(
                      color: Colors.white24,
                      fontSize: 11,
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold)),
            ],
          ],
        ),
        const SizedBox(height: 8),
        ..._members.map(
          (m) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: m.email == group.createdByEmail
                  ? Colors.white24
                  : Colors.white12,
              child: Text(
                m.username.isNotEmpty ? m.username[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            title: Row(
              children: [
                Text(m.username,
                    style: const TextStyle(color: Colors.white)),
                if (m.email == group.createdByEmail) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('admin',
                        style: TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
            subtitle: Text(m.email,
                style:
                    const TextStyle(color: Colors.white38, fontSize: 12)),
            trailing: m.email == _user?.email
                ? const Text('toi',
                    style:
                        TextStyle(color: Colors.white38, fontSize: 12))
                : isAdmin && m.uid != group.createdByUid
                    ? IconButton(
                        icon: const Icon(Icons.remove_circle_outline,
                            color: Colors.redAccent, size: 22),
                        tooltip: 'Supprimer du groupe',
                        onPressed: () => _removeMember(m),
                      )
                    : null,
          ),
        ),
        const SizedBox(height: 24),
        TextButton(
          onPressed: _leave,
          child: const Text('Quitter le groupe',
              style: TextStyle(color: Colors.redAccent)),
        ),
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
