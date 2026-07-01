import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/group.dart';
import '../models/photo_entry.dart';
import '../services/group_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../theme/v_theme.dart';
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
        await GroupService.cacheMemberNames(members.map((m) => m.username).toList());
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
      backgroundColor: VTheme.bgWarm,
      body: _loading
          ? Center(child: CircularProgressIndicator(color: VTheme.orange))
          : CustomScrollView(
              slivers: [
                _buildAppBar(),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_members.isNotEmpty) ...[
                          _buildMembersRow(),
                          const SizedBox(height: 24),
                        ],
                        _buildHeroButton(),
                        const SizedBox(height: 20),
                        _buildStatsRow(),
                        const SizedBox(height: 28),
                        if (_recent.isNotEmpty) ...[
                          _buildRecentHeader(),
                          const SizedBox(height: 10),
                          _buildPhotoGrid(),
                        ] else
                          _buildEmptyState(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  SliverAppBar _buildAppBar() {
    return SliverAppBar(
      backgroundColor: VTheme.bgWarm,
      surfaceTintColor: Colors.transparent,
      floating: true,
      snap: true,
      title: Text(
        _group?.name ?? "Snap'It",
        style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 24,
            color: VTheme.warmDark),
      ),
      actions: [
        _IconBtn(
          icon: Icons.group_outlined,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const GroupsScreen()))
              .then((_) => _load()),
        ),
        _IconBtn(
          icon: Icons.photo_library_outlined,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const GalleryScreen()))
              .then((_) => _load()),
        ),
        _IconBtn(
          icon: Icons.settings_outlined,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()))
              .then((_) => _load()),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildMembersRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Label('MEMBRES'),
        const SizedBox(height: 12),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _members.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final m = _members[i];
              final isMe = m.email == _user?.email;
              return Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: VTheme.avatarGradients[i % VTheme.avatarGradients.length],
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: VTheme.orange.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        m.username.isNotEmpty ? m.username[0].toUpperCase() : '?',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isMe ? 'Toi' : m.username.split(' ').first,
                    style: TextStyle(color: VTheme.warmMuted, fontSize: 11),
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

  Widget _buildHeroButton() {
    return GestureDetector(
      onTap: _triggerShot,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: VTheme.sunriseGradient,
          borderRadius: BorderRadius.circular(28),
          boxShadow: VTheme.glowSolar,
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📸', style: TextStyle(fontSize: 44)),
            SizedBox(height: 12),
            Text(
              'Prendre un shot',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5),
            ),
            SizedBox(height: 4),
            Text(
              'Ouvre la caméra avec un membre aléatoire',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(child: _StatCard(value: '$_total', label: 'photos', gradient: VTheme.coralGradient)),
        const SizedBox(width: 12),
        Expanded(child: _StatCard(value: '${_members.length}', label: 'membres', gradient: VTheme.skyGradient)),
      ],
    );
  }

  Widget _buildRecentHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const _Label('RÉCENTES'),
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const GalleryScreen()),
          ).then((_) => _load()),
          child: Text('Voir tout',
              style: TextStyle(
                  color: VTheme.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
        ),
      ],
    );
  }

  Widget _buildPhotoGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _recent.length,
      itemBuilder: (_, i) => PhotoCard(
        entry: _recent[i],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => _PhotoDetail(entry: _recent[i])),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: VTheme.solarGradient,
                shape: BoxShape.circle,
                boxShadow: VTheme.glowSolar,
              ),
              child: const Center(
                  child: Text('🎲', style: TextStyle(fontSize: 36))),
            ),
            const SizedBox(height: 20),
            Text(
              'Prêt pour les moments spontanés',
              style: TextStyle(
                  color: VTheme.warmDark,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Les notifications arriveront de façon aléatoire\ntout au long de la journée.',
              textAlign: TextAlign.center,
              style: TextStyle(color: VTheme.warmMuted, fontSize: 14, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small widgets ─────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(
            color: VTheme.warmMuted,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 2));
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: VTheme.warmDark),
      onPressed: onTap,
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final Gradient gradient;
  const _StatCard({required this.value, required this.label, required this.gradient});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: VTheme.cardShadow,
      ),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (b) => gradient.createShader(b),
            child: Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(color: VTheme.warmMuted, fontSize: 13)),
        ],
      ),
    );
  }
}

// ── Photo detail ──────────────────────────────────────────────────────────────

class _PhotoDetail extends StatelessWidget {
  final PhotoEntry entry;
  const _PhotoDetail({required this.entry});

  String _fmt(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month}/${dt.year} à $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white),
      body: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
              child: Image.file(File(entry.localPath), fit: BoxFit.contain)),
          Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.personName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(_fmt(entry.timestamp),
                    style: const TextStyle(color: Colors.white54, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
