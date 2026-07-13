import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../theme/v_theme.dart';
import 'account_screen.dart';
import 'camera_screen.dart';
import 'feed_screen.dart';
import 'gallery_screen.dart';
import 'groups_screen.dart';

/// Coquille principale (design v2) : barre de navigation permanente en bas.
/// Onglets : Fil · Galerie · Capture (bouton central) · Groupe · Compte.
///
/// Le bouton Capture n'ouvre l'appareil photo QUE s'il y a une alerte en cours
/// (les photos se prennent uniquement via notification) ; sinon un message
/// invite à attendre la prochaine alerte.
class MainShell extends StatefulWidget {
  final int initialIndex;
  const MainShell({super.key, this.initialIndex = 0});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _index = widget.initialIndex;

  // 4 écrans persistants ; « Capture » est une action, pas un onglet.
  final List<Widget> _screens = const [
    FeedScreen(),
    // Galerie = MES photos (celles où je suis identifié), tous groupes confondus.
    GalleryScreen(personalOnly: true, allGroups: true),
    GroupsScreen(),
    AccountScreen(),
  ];

  Future<void> _onCapture() async {
    final moment = await NotificationService.peekActiveMoment();
    if (!mounted) return;
    if (moment != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CameraScreen(personName: moment)),
      );
      if (mounted) setState(() {});
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('⏳ Attends la prochaine alerte pour prendre ta photo.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VTheme.bgWarm,
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: _NavBar(
        index: _index,
        onTapTab: (i) => setState(() => _index = i),
        onCapture: _onCapture,
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTapTab;
  final VoidCallback onCapture;

  const _NavBar({
    required this.index,
    required this.onTapTab,
    required this.onCapture,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: VTheme.surface,
        border: Border(top: BorderSide(color: VTheme.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(
            children: [
              _tab(Icons.home_rounded, 'Fil', 0),
              _tab(Icons.photo_library_rounded, 'Galerie', 1),
              _capture(),
              _tab(Icons.group_rounded, 'Groupe', 2),
              _tab(Icons.person_rounded, 'Compte', 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(IconData icon, String label, int i) {
    final active = index == i;
    final color = active ? VTheme.orange : VTheme.warmMuted;
    return Expanded(
      child: InkWell(
        onTap: () => onTapTab(i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _capture() {
    return Expanded(
      child: Center(
        child: GestureDetector(
          onTap: onCapture,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: VTheme.solarGradient,
              shape: BoxShape.circle,
              boxShadow: VTheme.glowSolar,
            ),
            child: const Icon(Icons.photo_camera_rounded,
                color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }
}
