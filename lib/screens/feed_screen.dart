import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

import '../models/group.dart';
import '../models/group_photo_entry.dart';
import '../models/photo_entry.dart';
import '../services/group_photo_service.dart';
import '../services/group_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/theme_service.dart';
import '../theme/v_theme.dart';
import 'create_group_screen.dart';
import 'gallery_screen.dart';
import 'groups_screen.dart';
import 'join_group_screen.dart';
import 'landing_screen.dart';
import 'settings_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  Group? _group;
  GroupMember? _user;
  List<GroupMember> _members = [];
  List<JoinedGroup> _joined = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final group = await GroupService.getCurrentGroup();
    final user  = await GroupService.getCurrentUser();
    final joined = await GroupService.getJoinedGroups();
    List<GroupMember> members = [];
    if (group != null) {
      try {
        members = await GroupService.getMembers(group.id);
        await GroupService.cacheMemberNames(members.map((m) => m.username).toList());
        await NotificationService.scheduleRandom();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _group   = group;
        _user    = user;
        _members = members;
        _joined  = joined;
        _loading = false;
      });
    }
  }

  Future<void> _switchGroup(String groupId) async {
    if (_group?.id == groupId) return;
    setState(() => _loading = true);
    await GroupService.setActiveGroup(groupId);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return ThemedScope(
      builder: (context) => Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: VTheme.bgWarm,
        appBar: _buildAppBar(),
        drawer: _buildDrawer(),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: VTheme.orange))
            : _group != null
                ? _GroupFeed(groupId: _group!.id, userEmail: _user?.email ?? '')
                : _LocalFeed(onReload: _load),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      foregroundColor: VTheme.warmDark,
      elevation: 0,
      centerTitle: true,
      title: ShaderMask(
        shaderCallback: (b) => VTheme.solarGradient.createShader(b),
        child: Text(
          'Vershoq',
          style: VTheme.grotesk(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -1),
        ),
      ),
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: Icon(Icons.menu_rounded, color: VTheme.warmDark),
          onPressed: () => Scaffold.of(ctx).openDrawer(),
        ),
      ),
    );
  }

  Drawer _buildDrawer() {
    return Drawer(
      backgroundColor: VTheme.bgWarm,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: VTheme.sunriseGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: VTheme.glowSolar,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('☀️', style: TextStyle(fontSize: 32)),
                  const SizedBox(height: 8),
                  Text(
                    _group?.name ?? 'Vershoq',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900),
                  ),
                  if (_members.isNotEmpty)
                    Text(
                      '${_members.length} membre${_members.length > 1 ? 's' : ''}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Members avatars
            if (_members.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text('MEMBRES',
                    style: TextStyle(
                        color: VTheme.warmMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2)),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _members.asMap().entries.map((e) {
                    final i = e.key;
                    final m = e.value;
                    final isMe = m.email == _user?.email;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: VTheme.avatarGradients[
                                i % VTheme.avatarGradients.length],
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              m.username.isNotEmpty
                                  ? m.username[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isMe ? 'Toi' : m.username.split(' ').first,
                          style: TextStyle(
                              color: VTheme.warmMuted, fontSize: 10),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
              Divider(indent: 16, endIndent: 16, color: VTheme.hairline),
            ],

            // Sélecteur de groupes (multi-groupes)
            if (_joined.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                child: Text('MES GROUPES',
                    style: TextStyle(
                        color: VTheme.warmMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2)),
              ),
              ..._joined.map((j) {
                final active = j.group.id == _group?.id;
                return ListTile(
                  dense: true,
                  leading: Icon(
                      active
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: active ? VTheme.orange : VTheme.warmMuted,
                      size: 20),
                  title: Text(j.group.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: VTheme.warmDark,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w500)),
                  onTap: () {
                    Navigator.pop(context);
                    _switchGroup(j.group.id);
                  },
                );
              }),
              const SizedBox(height: 4),
              Divider(indent: 16, endIndent: 16, color: VTheme.hairline),
            ],

            // Nav items
            _DrawerTile(
              icon: Icons.group_add_outlined,
              label: 'Rejoindre un groupe',
              onTap: () async {
                Navigator.pop(context);
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const JoinGroupScreen()));
                _load();
              },
            ),
            _DrawerTile(
              icon: Icons.add_circle_outline,
              label: 'Créer un groupe',
              onTap: () async {
                Navigator.pop(context);
                await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const CreateGroupScreen()));
                _load();
              },
            ),
            _DrawerTile(
              icon: Icons.photo_library_outlined,
              label: 'Galerie du groupe',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const GalleryScreen()));
              },
            ),
            _DrawerTile(
              icon: Icons.person_outline,
              label: 'Ma galerie',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            const GalleryScreen(personalOnly: true)));
              },
            ),
            _DrawerTile(
              icon: Icons.group_outlined,
              label: 'Gérer le groupe',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const GroupsScreen()));
              },
            ),
            _DrawerTile(
              icon: Icons.settings_outlined,
              label: 'Paramètres',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()));
              },
            ),

            const Spacer(),

            if (_group != null)
              _DrawerTile(
                icon: Icons.logout_rounded,
                label: 'Quitter le groupe',
                color: VTheme.coral,
                onTap: () async {
                  Navigator.pop(context);
                  final leftName = _group?.name ?? '';
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('Quitter « $leftName » ?'),
                      content: const Text(
                          'Tu devras rejoindre avec un nouveau code.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Annuler')),
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Quitter',
                                style: TextStyle(color: VTheme.coral))),
                      ],
                    ),
                  );
                  if (ok == true && mounted) {
                    await GroupService.leaveGroup();
                    final remaining = await GroupService.getJoinedGroups();
                    if (!mounted) return;
                    if (remaining.isNotEmpty) {
                      // Il reste d'autres groupes : on recharge le feed sur le
                      // nouveau groupe actif.
                      _load();
                    } else {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LandingScreen()),
                        (_) => false,
                      );
                    }
                  }
                },
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ── Group feed ────────────────────────────────────────────────────────────────

class _GroupFeed extends StatelessWidget {
  final String groupId;
  final String userEmail;
  const _GroupFeed({required this.groupId, required this.userEmail});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GroupPhotoEntry>>(
      stream: GroupPhotoService.streamGroupPhotos(groupId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(
              child: CircularProgressIndicator(color: VTheme.orange));
        }
        final photos = snap.data ?? [];
        if (photos.isEmpty) return const _EmptyFeed();
        return Stack(
          children: [
            PageView.builder(
              scrollDirection: Axis.vertical,
              itemCount: photos.length,
              itemBuilder: (_, i) => _GroupPhotoPage(
                photo: photos[i],
                isMe: photos[i].uploaderEmail == userEmail,
                groupId: groupId,
                index: i,
                total: photos.length,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GroupPhotoPage extends StatelessWidget {
  final GroupPhotoEntry photo;
  final bool isMe;
  final String groupId;
  final int index;
  final int total;

  const _GroupPhotoPage({
    required this.photo,
    required this.isMe,
    required this.groupId,
    required this.index,
    required this.total,
  });

  void _openFullscreen(BuildContext context, Uint8List bytes) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.download_outlined, color: Colors.white),
              onPressed: () => _download(context),
            ),
          ],
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
        ),
      ),
    ));
  }

  Future<void> _download(BuildContext context) async {
    try {
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      final bytes = base64Decode(photo.imageBase64);
      await Gal.putImageBytes(bytes, album: 'Vershoq');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo sauvegardée !')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ?'),
        content: const Text('Supprimée pour tout le groupe.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer',
                  style: TextStyle(color: VTheme.coral))),
        ],
      ),
    );
    if (ok == true) await GroupPhotoService.deletePhoto(groupId, photo.id);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = base64Decode(photo.imageBase64);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            const Spacer(),

            // Photo contenue (pas plein écran), coins arrondis façon BeReal.
            // Tap → affichage plein écran avec zoom.
            GestureDetector(
              onTap: () => _openFullscreen(context, bytes),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Image.memory(bytes, fit: BoxFit.cover),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Infos SOUS la photo : avatar + @uploader feat. personName + heure
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: VTheme.solarGradient,
                    border: Border.all(color: Colors.white24, width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      photo.uploaderUsername.isNotEmpty
                          ? photo.uploaderUsername[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 18, height: 1.2),
                          children: [
                            TextSpan(
                              text: '@${photo.uploaderUsername}',
                              style: VTheme.grotesk(
                                color: VTheme.warmDark,
                                fontWeight: FontWeight.w800,
                                fontSize: 19,
                              ),
                            ),
                            TextSpan(
                              text: ' feat. ',
                              style: TextStyle(
                                color: VTheme.warmMuted,
                                fontSize: 15,
                              ),
                            ),
                            TextSpan(
                              text: photo.personName,
                              style: VTheme.grotesk(
                                color: VTheme.orange,
                                fontWeight: FontWeight.w800,
                                fontSize: 19,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _fmt(photo.timestamp),
                        style: TextStyle(
                            color: VTheme.warmMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                // Actions
                _ActionBtn(
                  icon: Icons.download_outlined,
                  onTap: () => _download(context),
                ),
                if (isMe) ...[
                  const SizedBox(width: 10),
                  _ActionBtn(
                    icon: Icons.delete_outline,
                    onTap: () => _delete(context),
                    color: VTheme.coral,
                  ),
                ],
              ],
            ),

            const Spacer(),

            // Indice de swipe
            SizedBox(
              height: 28,
              child: index < total - 1
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.keyboard_arrow_up_rounded,
                            color: VTheme.warmMuted, size: 18),
                        const SizedBox(width: 4),
                        Text('Swipe pour la suite',
                            style: TextStyle(
                                color: VTheme.warmMuted, fontSize: 11)),
                      ],
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month}/${dt.year} à $h:$m';
  }
}

// ── Local feed ────────────────────────────────────────────────────────────────

class _LocalFeed extends StatefulWidget {
  final VoidCallback onReload;
  const _LocalFeed({required this.onReload});

  @override
  State<_LocalFeed> createState() => _LocalFeedState();
}

class _LocalFeedState extends State<_LocalFeed> {
  List<PhotoEntry> _photos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await StorageService.getEntries();
    if (mounted) setState(() { _photos = entries; _loading = false; });
  }

  Future<void> _delete(PhotoEntry entry) async {
    await StorageService.deleteEntry(entry.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: VTheme.orange));
    }
    if (_photos.isEmpty) return const _EmptyFeed();
    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: _photos.length,
      itemBuilder: (_, i) => _LocalPhotoPage(
        entry: _photos[i],
        index: i,
        total: _photos.length,
        onDelete: _delete,
      ),
    );
  }
}

class _LocalPhotoPage extends StatelessWidget {
  final PhotoEntry entry;
  final int index;
  final int total;
  final Future<void> Function(PhotoEntry) onDelete;

  const _LocalPhotoPage({
    required this.entry,
    required this.index,
    required this.total,
    required this.onDelete,
  });

  Future<void> _download(BuildContext context) async {
    try {
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await Gal.putImage(entry.localPath, album: 'Vershoq');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo sauvegardée !')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(File(entry.localPath), fit: BoxFit.cover),
        const _BottomGradient(),

        // Bottom info
        Positioned(
          bottom: 110,
          left: 20,
          right: 80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.personName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                      shadows: [Shadow(blurRadius: 8, color: Colors.black54)])),
              const SizedBox(height: 4),
              Text(_fmt(entry.timestamp),
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ],
          ),
        ),

        // Right actions
        Positioned(
          bottom: 120,
          right: 16,
          child: Column(
            children: [
              _ActionBtn(
                  icon: Icons.download_outlined,
                  onTap: () => _download(context)),
              const SizedBox(height: 16),
              _ActionBtn(
                icon: Icons.delete_outline,
                color: VTheme.coral,
                onTap: () async {
                  await onDelete(entry);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _fmt(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month}/${dt.year} à $h:$m';
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class _BottomGradient extends StatelessWidget {
  const _BottomGradient();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      height: 320,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _ActionBtn({
    required this.icon,
    required this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.black45,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? VTheme.warmDark;
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: c.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: c, size: 20),
      ),
      title: Text(label,
          style: TextStyle(
              color: c, fontWeight: FontWeight.w600, fontSize: 15)),
      onTap: onTap,
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: VTheme.bgGradient),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: VTheme.solarGradient,
                shape: BoxShape.circle,
                boxShadow: VTheme.glowSolar,
              ),
              child: const Center(
                  child: Text('📸', style: TextStyle(fontSize: 44))),
            ),
            const SizedBox(height: 24),
            Text('Aucune photo encore',
                style: TextStyle(
                    color: VTheme.warmDark,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Attends la notification Vershoq\npour capturer un moment !',
                textAlign: TextAlign.center,
                style: TextStyle(color: VTheme.warmMuted, fontSize: 14)),
            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }
}
