import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

import '../models/group.dart';
import '../models/group_photo_entry.dart';
import '../models/photo_entry.dart';
import '../services/group_photo_service.dart';
import '../services/group_service.dart';
import '../services/storage_service.dart';
import '../services/theme_service.dart';
import '../theme/v_theme.dart';
import '../widgets/photo_card.dart';

class GalleryScreen extends StatefulWidget {
  /// Si vrai, n'affiche que les photos prises par l'utilisateur ou celles
  /// où il est identifié (le prénom à capturer correspond à son pseudo).
  final bool personalOnly;

  /// Si vrai (avec personalOnly), agrège les photos personnelles de TOUS
  /// les groupes rejoints, pas seulement le groupe actif.
  final bool allGroups;

  const GalleryScreen(
      {super.key, this.personalOnly = false, this.allGroups = false});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  String? _groupId;
  String? _userEmail;
  String? _userUsername;
  List<PhotoEntry> _localEntries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final group = await GroupService.getCurrentGroup();
    final user = await GroupService.getCurrentUser();
    List<PhotoEntry> local = [];
    if (group == null) local = await StorageService.getEntries();
    if (mounted) {
      setState(() {
        _groupId = group?.id;
        _userEmail = user?.email;
        _userUsername = user?.username;
        _localEntries = local;
        _loading = false;
      });
    }
  }

  bool _isMine(GroupPhotoEntry p) {
    final mineUpload = _userEmail != null && p.uploaderEmail == _userEmail;
    final tagged = _userUsername != null &&
        p.personName.trim().toLowerCase() ==
            _userUsername!.trim().toLowerCase();
    return mineUpload || tagged;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.personalOnly
        ? 'Ma galerie'
        : (_groupId != null ? 'Galerie du groupe' : 'Ma galerie');
    return ThemedScope(
      builder: (context) => Scaffold(
        backgroundColor: VTheme.bgWarm,
        appBar: AppBar(title: Text(title)),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: VTheme.orange))
            : widget.allGroups
                ? _buildAllGroupsGallery()
                : _groupId != null
                    ? _buildGroupGallery()
                    : _buildLocalGallery(),
      ),
    );
  }

  // ── Group gallery ────────────────────────────────────────────────────────────

  Widget _buildGroupGallery() {
    return StreamBuilder<List<GroupPhotoEntry>>(
      stream: GroupPhotoService.streamGroupPhotos(_groupId!),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: VTheme.orange));
        }
        var photos = snap.data ?? [];
        if (widget.personalOnly) {
          photos = photos.where(_isMine).toList();
        }
        if (photos.isEmpty) {
          return _emptyState(
              personal: widget.personalOnly);
        }

        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: photos.length,
          itemBuilder: (_, i) => _GroupPhotoCard(
            photo: photos[i],
            onTap: () => _showGroupDetail(photos[i]),
          ),
        );
      },
    );
  }

  void _showGroupDetail(GroupPhotoEntry photo, [String? groupId]) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _GroupDetailScreen(
        photo: photo,
        userEmail: _userEmail,
        groupId: groupId ?? _groupId!,
      ),
    ));
  }

  // ── All-groups personal gallery ─────────────────────────────────────────────

  Widget _buildAllGroupsGallery() {
    return FutureBuilder<List<MapEntry<String, GroupPhotoEntry>>>(
      future: _fetchAllMyPhotos(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: VTheme.orange));
        }
        final entries = snap.data ?? [];
        if (entries.isEmpty) return _emptyState(personal: true);

        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: entries.length,
          itemBuilder: (_, i) => _GroupPhotoCard(
            photo: entries[i].value,
            onTap: () => _showGroupDetail(entries[i].value, entries[i].key),
          ),
        );
      },
    );
  }

  Future<List<MapEntry<String, GroupPhotoEntry>>> _fetchAllMyPhotos() async {
    final joined = await GroupService.getJoinedGroups();
    final result = <MapEntry<String, GroupPhotoEntry>>[];
    for (final j in joined) {
      final photos = await GroupPhotoService.fetchGroupPhotos(j.group.id);
      for (final p in photos) {
        if (_isMineFor(p, j.member)) {
          result.add(MapEntry(j.group.id, p));
        }
      }
    }
    result.sort((a, b) => b.value.timestamp.compareTo(a.value.timestamp));
    return result;
  }

  bool _isMineFor(GroupPhotoEntry p, GroupMember member) {
    return p.uploaderEmail == member.email ||
        p.personName.trim().toLowerCase() == member.username.trim().toLowerCase();
  }

  // ── Local gallery ────────────────────────────────────────────────────────────

  Widget _buildLocalGallery() {
    if (_localEntries.isEmpty) return _emptyState(personal: false);
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _localEntries.length,
      itemBuilder: (_, i) => PhotoCard(
        entry: _localEntries[i],
        onTap: () => _showLocalDetail(_localEntries[i]),
      ),
    );
  }

  void _showLocalDetail(PhotoEntry entry) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _LocalDetailScreen(entry: entry, onDelete: _deleteLocal),
    ));
  }

  Future<void> _deleteLocal(PhotoEntry entry) async {
    await StorageService.deleteEntry(entry.id);
    await _load();
  }

  Widget _emptyState({required bool personal}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo_library_outlined, size: 64, color: VTheme.peach),
          const SizedBox(height: 16),
          Text(personal ? 'Aucune photo de toi' : 'Aucune photo encore',
              style: TextStyle(color: VTheme.warmMuted, fontSize: 16)),
          const SizedBox(height: 8),
          Text(
              personal
                  ? 'Tes photos et celles où tu es identifié\napparaîtront ici.'
                  : 'Attends une notification !',
              textAlign: TextAlign.center,
              style: TextStyle(color: VTheme.peach, fontSize: 13)),
        ],
      ),
    );
  }
}

// ── Group photo card ─────────────────────────────────────────────────────────

class _GroupPhotoCard extends StatelessWidget {
  final GroupPhotoEntry photo;
  final VoidCallback onTap;

  const _GroupPhotoCard({required this.photo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bytes = base64Decode(photo.imageBase64);
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(bytes, fit: BoxFit.cover),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Text(
                  photo.personName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Group detail screen ───────────────────────────────────────────────────────

class _GroupDetailScreen extends StatelessWidget {
  final GroupPhotoEntry photo;
  final String? userEmail;
  final String groupId;

  const _GroupDetailScreen({
    required this.photo,
    required this.userEmail,
    required this.groupId,
  });

  Future<void> _download(BuildContext context) async {
    try {
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      final bytes = base64Decode(photo.imageBase64);
      await Gal.putImageBytes(bytes, album: 'Vershoq');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo sauvegardée dans la galerie !')),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Supprimer ?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
            'Cette photo sera supprimée pour tout le groupe.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler',
                  style: TextStyle(color: Colors.white38))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed == true) {
      await GroupPhotoService.deletePhoto(groupId, photo.id);
      if (context.mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = base64Decode(photo.imageBase64);
    final isUploader = photo.uploaderEmail == userEmail;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined, color: Colors.white),
            tooltip: 'Sauvegarder',
            onPressed: () => _download(context),
          ),
          if (isUploader)
            IconButton(
              icon:
                  const Icon(Icons.delete_outline, color: Colors.white70),
              onPressed: () => _delete(context),
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
          Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(photo.personName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('par ${photo.uploaderUsername}',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 14)),
                const SizedBox(height: 2),
                Text(_formatDate(photo.timestamp),
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month}/${dt.year} à $h:$m';
  }
}

// ── Local detail screen ───────────────────────────────────────────────────────

class _LocalDetailScreen extends StatelessWidget {
  final PhotoEntry entry;
  final Future<void> Function(PhotoEntry) onDelete;

  const _LocalDetailScreen({required this.entry, required this.onDelete});

  Future<void> _download(BuildContext context) async {
    try {
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await Gal.putImage(entry.localPath, album: 'Vershoq');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo sauvegardée dans la galerie !')),
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
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined, color: Colors.white),
            tooltip: 'Sauvegarder',
            onPressed: () => _download(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white70),
            onPressed: () async {
              await onDelete(entry);
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
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
                Text(_formatDate(entry.timestamp),
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month}/${dt.year} à $h:$m';
  }
}
