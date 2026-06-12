import 'dart:math';

import 'package:flutter/material.dart';

import '../models/group.dart';
import '../models/photo_entry.dart';
import '../services/group_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../widgets/photo_card.dart';
import 'camera_screen.dart';
import 'gallery_screen.dart';
import 'groups_screen.dart';
import 'settings_screen.dart';

class GroupHomeScreen extends StatefulWidget {
  const GroupHomeScreen({super.key});

  @override
  State<GroupHomeScreen> createState() => _GroupHomeScreenState();
}

class _GroupHomeScreenState extends State<GroupHomeScreen>
    with WidgetsBindingObserver {
  Group? _group;
  GroupMember? _user;
  List<GroupMember> _members = [];
  List<PhotoEntry> _recent = [];
  int _total = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final group = await GroupService.getCurrentGroup();
    final user = await GroupService.getCurrentUser();
    List<GroupMember> members = [];
    if (group != null) {
      try {
        members = await GroupService.getMembers(group.id);
        await GroupService.cacheMemberNames(
            members.map((m) => m.username).toList());
        await NotificationService.scheduleRandom();
      } catch (_) {}
    }
    final entries = await StorageService.getEntries();
    if (mounted) {
      setState(() {
        _group = group;
        _user = user;
        _members = members;
        _total = entries.length;
        _recent = entries.take(6).toList();
        _loading = false;
      });
    }
  }

  Future<void> _triggerShot() async {
    final names = _members.map((m) => m.username).toList();
    if (names.isEmpty) return;
    final name = names[Random().nextInt(names.length)];

    await NotificationService.sendTestNotification(name);

    if (mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CameraScreen(personName: name)),
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverAppBar.large(
                  title: Text(
                    _group?.name ?? 'Vershoq',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 28),
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.group_outlined),
                      tooltip: 'Groupe',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const GroupsScreen()),
                      ).then((_) => _load()),
                    ),
                    IconButton(
                      icon: const Icon(Icons.photo_library_outlined),
                      tooltip: 'Galerie',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const GalleryScreen()),
                      ).then((_) => _load()),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      tooltip: 'Paramètres',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen()),
                      ).then((_) => _load()),
                    ),
                  ],
                ),
                SliverToBoxAdapter(child: _buildContent()),
              ],
            ),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_members.isNotEmpty) _buildMembersRow(),
          const SizedBox(height: 20),
          _buildStatsRow(),
          const SizedBox(height: 24),
          _buildHeroButton(),
          const SizedBox(height: 32),
          if (_recent.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'RÉCENTES',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const GalleryScreen()),
                  ).then((_) => _load()),
                  child: const Text('Voir tout',
                      style: TextStyle(color: Colors.white38)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _recent.length,
              itemBuilder: (_, i) => PhotoCard(entry: _recent[i]),
            ),
          ] else
            _buildEmptyState(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildMembersRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'MEMBRES',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _members.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final m = _members[i];
              final isMe = m.email == _user?.email;
              return Column(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor:
                        isMe ? Colors.white : Colors.white12,
                    child: Text(
                      m.username.isNotEmpty
                          ? m.username[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        color: isMe ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isMe ? 'Toi' : m.username.split(' ').first,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _StatChip(value: _total.toString(), label: 'photos'),
        const SizedBox(width: 12),
        _StatChip(value: _members.length.toString(), label: 'membres'),
      ],
    );
  }

  Widget _buildHeroButton() {
    return GestureDetector(
      onTap: _triggerShot,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📸', style: TextStyle(fontSize: 40)),
            SizedBox(height: 12),
            Text(
              'Prendre un shot',
              style: TextStyle(
                color: Colors.black,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Ouvre la caméra avec un membre aléatoire',
              style: TextStyle(color: Colors.black54, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          children: [
            Text('🎲', style: TextStyle(fontSize: 56)),
            SizedBox(height: 16),
            Text(
              'Prêt pour les moments spontanés',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Les notifications arriveront de façon aléatoire\ntout au long de la journée.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white38, fontSize: 14, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String value;
  final String label;
  const _StatChip({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
