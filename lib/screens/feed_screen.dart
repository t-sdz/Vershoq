import 'dart:async';
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
import '../services/push_service.dart';
import '../services/storage_service.dart';
import '../services/theme_service.dart';
import '../theme/v_theme.dart';
import 'camera_screen.dart';
import 'settings_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with WidgetsBindingObserver {
  Group? _group;
  GroupMember? _user;
  AlertMoment? _activeAlert;
  bool _loading = true;
  // Rafraîchit le temps restant affiché dans la bannière.
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.momentTick.addListener(_onMomentTick);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.momentTick.removeListener(_onMomentTick);
    _bannerTimer?.cancel();
    super.dispose();
  }

  // Un push est arrivé app ouverte -> rafraîchit UNIQUEMENT la bannière (lecture
  // locale), sans relire Firestore, pour ne pas gaspiller le quota.
  void _onMomentTick() => _refreshBanner();

  Future<void> _refreshBanner() async {
    final a = await NotificationService.peekActiveAlert();
    if (mounted) _setActiveAlert(a);
  }

  /// Met à jour la bannière et (re)lance son minuteur si l'alerte a un
  /// compte à rebours (affichage du temps restant, disparition à 0).
  void _setActiveAlert(AlertMoment? a) {
    setState(() => _activeAlert = a);
    _bannerTimer?.cancel();
    _bannerTimer = null;
    if (a == null) return;
    // Sans compte à rebours : un contrôle par minute suffit (expiration 6 h).
    final period = a.hasCountdown
        ? const Duration(milliseconds: 500)
        : const Duration(minutes: 1);
    _bannerTimer = Timer.periodic(period, (_) {
      if (!mounted) return;
      if (a.isExpired()) {
        _bannerTimer?.cancel();
        _bannerTimer = null;
        setState(() => _activeAlert = null);
      } else if (a.hasCountdown) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Au retour dans l'app : on recharge pour afficher la bannière « moment ».
    if (state == AppLifecycleState.resumed) _load();
  }

  bool _refreshing = false;

  Future<void> _load() async {
    // 1. Affichage IMMÉDIAT à partir des données enregistrées sur le
    //    téléphone (aucun accès réseau) : le fil apparaît tout de suite.
    final group = await GroupService.getCurrentGroup();
    final user = await GroupService.getCurrentUser();
    final activeAlert = await NotificationService.peekActiveAlert();
    if (mounted) {
      setState(() {
        _group = group;
        _user = user;
        _loading = false;
      });
      _setActiveAlert(activeAlert);
    }
    // 2. Mises à jour réseau en arrière-plan (sans bloquer l'écran).
    _refreshInBackground();
  }

  Future<void> _refreshInBackground() async {
    if (_refreshing) return; // déjà en cours (retour rapide dans l'app)
    _refreshing = true;
    try {
      // Récupère la dernière alerte du serveur si la notif n'a pas été
      // traitée en arrière-plan (sinon « pas de photo à prendre »).
      await PushService.syncLastAlert();
      final a = await NotificationService.peekActiveAlert();
      if (mounted) _setActiveAlert(a);

      // refreshCurrentGroup détecte un groupe supprimé et bascule.
      final group = await GroupService.refreshCurrentGroup();
      if (mounted) setState(() => _group = group);
      // Auto-répare ma fiche membre si mon pseudo a changé.
      await GroupService.healMyMemberUsername();
      // Un seul topic push : le topic personnel de l'utilisateur.
      try {
        await PushService.reconcileSubscriptions();
      } catch (_) {}
    } catch (_) {
    } finally {
      _refreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThemedScope(
      builder: (context) => Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: VTheme.bgWarm,
        appBar: _buildAppBar(),
        body: Stack(
          children: [
            _loading
                ? Center(child: CircularProgressIndicator(color: VTheme.orange))
                : _group != null
                    ? _GroupFeed(
                        groupId: _group!.id, userEmail: _user?.email ?? '')
                    : _LocalFeed(onReload: _load),
            if (!_loading && _activeAlert != null)
              Positioned(
                top: MediaQuery.of(context).padding.top + 60,
                left: 16,
                right: 16,
                child: _MomentBanner(
                  alert: _activeAlert!,
                  onTap: () => _openCamera(_activeAlert!.id),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCamera(String alertId) async {
    if (CameraScreen.isOpen) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CameraScreen(alertId: alertId)),
    );
    _load();
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
          "Snap'It",
          style: VTheme.grotesk(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -1),
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.settings_rounded, color: VTheme.warmDark),
          tooltip: 'Paramètres',
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const SettingsScreen()))
              .then((_) => _load()),
        ),
      ],
    );
  }
}

// ── Group feed ────────────────────────────────────────────────────────────────

class _GroupFeed extends StatefulWidget {
  final String groupId;
  final String userEmail;
  const _GroupFeed({required this.groupId, required this.userEmail});

  @override
  State<_GroupFeed> createState() => _GroupFeedState();
}

class _GroupFeedState extends State<_GroupFeed> {
  // On charge par paquets (économise le quota) et on agrandit la fenêtre quand
  // l'utilisateur arrive au bout → toutes les photos restent accessibles.
  int _limit = 30;

  // Flux créé UNE fois (et recréé seulement si le groupe ou la fenêtre
  // change) : le recréer à chaque reconstruction relançait le chargement de
  // toutes les photos en boucle.
  late Stream<List<GroupPhotoEntry>> _stream = _makeStream();

  Stream<List<GroupPhotoEntry>> _makeStream() =>
      GroupPhotoService.streamGroupPhotos(widget.groupId, limit: _limit);

  @override
  void didUpdateWidget(covariant _GroupFeed old) {
    super.didUpdateWidget(old);
    if (old.groupId != widget.groupId) {
      _limit = 30;
      _stream = _makeStream();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GroupPhotoEntry>>(
      stream: _stream,
      builder: (context, snap) {
        if (!snap.hasData) {
          return Center(
              child: CircularProgressIndicator(color: VTheme.orange));
        }
        final photos = snap.data ?? [];
        if (photos.isEmpty) return const _EmptyFeed();
        return PageView.builder(
          scrollDirection: Axis.vertical,
          itemCount: photos.length,
          onPageChanged: (i) {
            // Proche de la fin ET il y a peut-être plus → on agrandit.
            if (i >= photos.length - 2 && photos.length >= _limit) {
              setState(() {
                _limit += 30;
                _stream = _makeStream();
              });
            }
          },
          itemBuilder: (_, i) => _GroupPhotoPage(
            photo: photos[i],
            isMe: photos[i].uploaderEmail == widget.userEmail,
            groupId: widget.groupId,
            index: i,
            total: photos.length,
          ),
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
      final bytes = photo.bytes;
      if (bytes == null) throw 'image illisible';
      await Gal.putImageBytes(bytes, album: "Snap'It");
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
    final bytes = photo.bytes;
    // Décode à la taille de l'écran (pas en pleine résolution) : beaucoup
    // moins de mémoire.
    final mq = MediaQuery.of(context);
    final cacheW = (mq.size.width * mq.devicePixelRatio).round();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            const Spacer(),

            // Photo contenue (pas plein écran), coins arrondis façon BeReal.
            // Tap → affichage plein écran avec zoom.
            GestureDetector(
              onTap: bytes == null
                  ? null
                  : () => _openFullscreen(context, bytes),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: bytes == null
                      ? Container(
                          color: VTheme.surface,
                          child: Center(
                            child: Icon(Icons.broken_image_outlined,
                                color: VTheme.warmMuted, size: 48),
                          ),
                        )
                      : Image.memory(
                          bytes,
                          fit: BoxFit.cover,
                          cacheWidth: cacheW,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => Container(
                            color: VTheme.surface,
                            child: Center(
                              child: Icon(Icons.broken_image_outlined,
                                  color: VTheme.warmMuted, size: 48),
                            ),
                          ),
                        ),
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
      await Gal.putImage(entry.localPath, album: "Snap'It");
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

class _MomentBanner extends StatelessWidget {
  final AlertMoment alert;
  final VoidCallback onTap;
  const _MomentBanner({required this.alert, required this.onTap});

  /// « 45 s » sous la minute, sinon « m:ss ».
  static String _fmt(Duration d) {
    final secs = (d.inMilliseconds / 1000).ceil();
    if (secs < 60) return '$secs s';
    return '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final names = alert.names;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          gradient: VTheme.solarGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: VTheme.glowSolar,
        ),
        child: Row(
          children: [
            const Text('📸', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      alert.hasCountdown
                          ? 'C\'est le moment ! ⏱ ${_fmt(alert.remaining())}'
                          : 'C\'est le moment !',
                      style: VTheme.grotesk(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                  Text(
                      names.trim().isEmpty
                          ? 'Prends vite ta photo avec le groupe'
                          : 'Prends ta photo avec $names',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 26),
          ],
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
            Text("Attends la notification Snap'It\npour capturer un moment !",
                textAlign: TextAlign.center,
                style: TextStyle(color: VTheme.warmMuted, fontSize: 14)),
            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }
}
