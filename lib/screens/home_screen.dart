import 'dart:math';

import 'package:flutter/material.dart';

import '../models/photo_entry.dart';
import '../services/names_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../widgets/photo_card.dart';
import 'camera_screen.dart';
import 'gallery_screen.dart';
import 'groups_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
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
    final entries = await StorageService.getEntries();
    if (mounted) {
      setState(() {
        _total = entries.length;
        _recent = entries.take(6).toList();
        _loading = false;
      });
    }
  }

  Future<void> _triggerTestShot() async {
    final names = await NamesService.getNames();
    if (names.isEmpty) return;
    final name = names[Random().nextInt(names.length)];

    // Show notification (fires immediately) and navigate
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
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text(
              "Snap'It",
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 32),
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
                  MaterialPageRoute(builder: (_) => const GalleryScreen()),
                ).then((_) => _load()),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Paramètres',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ).then((_) => _load()),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: _loading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(48),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : _buildContent(),
          ),
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
          _StatsRow(total: _total),
          const SizedBox(height: 28),

          // CTA hero button
          _HeroButton(onPressed: _triggerTestShot),
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
          ] else ...[
            _EmptyState(onTrigger: _triggerTestShot),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final int total;
  const _StatsRow({required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatChip(value: total.toString(), label: 'photos'),
        const SizedBox(width: 12),
        _StatChip(
          value: total == 0 ? '0' : (total * 0.92).toStringAsFixed(0),
          label: 'moments',
        ),
      ],
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

class _HeroButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _HeroButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
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
              'Tester un shot',
              style: TextStyle(
                color: Colors.black,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Ouvre la caméra avec un prénom aléatoire',
              style: TextStyle(color: Colors.black54, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onTrigger;
  const _EmptyState({required this.onTrigger});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const Text('🎲', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          const Text(
            'Prêt pour les moments spontanés',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Les notifications vont arriver de façon aléatoire\ntout au long de la journée.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }
}
