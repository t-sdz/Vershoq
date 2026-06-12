import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

import '../models/group_photo_entry.dart';
import '../models/photo_entry.dart';
import '../services/group_photo_service.dart';
import '../services/group_service.dart';
import '../services/storage_service.dart';
import '../widgets/photo_card.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  String? _groupId;
  String? _userEmail;
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
        _localEntries = local;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_groupId != null ? 'Galerie du groupe' : 'Ma galerie'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _groupId != null
              ? _buildGroupGallery()
              : _buildLocalGallery(),
    );
  }

  // ── Group gallery ────────────────────────────────────────────────────────────

  Widget _buildGroupGallery() {
    return StreamBuilder<List<GroupPhotoEntry>>(
      stream: GroupPhotoService.streamGroupPhotos(_groupId!),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final photos = snap.data ?? [];
        if (photos.isEmpty) return _emptyState();

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

  void _showGroupDetail(GroupPhotoEntry photo) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _GroupDetailScreen(
        photo: photo,
        userEmail: _userEmail,
        groupId: _groupId!,
      ),
    ));
  }

  // ── Local gallery ────────────────────────────────────────────────────────────

  Widget _buildLocalGallery() {
    if (_localEntries.isEmpty) return _emptyState();
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

  Widget _emptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo_library_outlined, size: 64, color: Colors.white24),
          SizedBox(height: 16),
          Text('Aucune photo encore',
              style: TextStyle(color: Colors.white38, fontSize: 16)),
          SizedBox(height: 8),
          Text('Attends une notification !',
              style: TextStyle(color: Colors.white24, fontSize: 13)),
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
      final bytes = base64Decode(photo.imageBase64);
      await Gal.putImageBytes(bytes);
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
      await Gal.putImage(entry.localPath);
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
