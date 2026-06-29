import 'package:flutter/material.dart';

import '../models/group.dart';
import '../services/group_service.dart';
import '../theme/v_theme.dart';
import 'create_group_screen.dart';
import 'feed_screen.dart';
import 'join_group_screen.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  Group? _group;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkGroup();
  }

  Future<void> _checkGroup() async {
    final group = await GroupService.getCurrentGroup();
    if (mounted) setState(() { _group = group; _loading = false; });
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _checkGroup();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      body: GradientBackground(
        child: _loading
            ? Center(child: CircularProgressIndicator(color: VTheme.orange))
            : Stack(
                children: [
                  // Decorative blurred circles
                  Positioned(
                    top: -40,
                    right: -40,
                    child: _Blob(gradient: VTheme.solarGradient, size: 200, opacity: 0.35),
                  ),
                  Positioned(
                    bottom: 120,
                    left: -60,
                    child: _Blob(gradient: VTheme.skyGradient, size: 180, opacity: 0.25),
                  ),

                  SafeArea(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(28, top > 0 ? 0 : 16, 28, bottom > 0 ? 0 : 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 48),

                          // Logo
                          ShaderMask(
                            shaderCallback: (b) => VTheme.solarGradient.createShader(b),
                            child: const Text(
                              'Vershoq',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 64,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -2.5,
                                height: 1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Capturez les moments spontanés\navec vos amis. ☀️',
                            style: TextStyle(
                              color: VTheme.warmMuted,
                              fontSize: 16,
                              height: 1.4,
                            ),
                          ),

                          const Spacer(),

                          // Group banner
                          if (_group != null) ...[
                            _GroupBanner(group: _group!, onTap: () => _open(const FeedScreen())),
                            const SizedBox(height: 16),
                          ],

                          // Créer
                          SizedBox(
                            width: double.infinity,
                            child: GradientButton(
                              label: 'Créer un groupe',
                              gradient: VTheme.solarGradient,
                              shadows: VTheme.glowSolar,
                              onPressed: () => _open(const CreateGroupScreen()),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Rejoindre
                          SizedBox(
                            width: double.infinity,
                            child: _OutlineButton(
                              label: 'Rejoindre un groupe',
                              onPressed: () => _open(const JoinGroupScreen()),
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _GroupBanner extends StatelessWidget {
  final Group group;
  final VoidCallback onTap;
  const _GroupBanner({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: VTheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: VTheme.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: VTheme.sunriseGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.group_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TON GROUPE',
                      style: TextStyle(
                          color: VTheme.warmMuted,
                          fontSize: 11,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(group.name,
                      style: TextStyle(
                          color: VTheme.warmDark,
                          fontSize: 18,
                          fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: VTheme.warmMuted),
          ],
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _OutlineButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: VTheme.orange,
          side: BorderSide(color: VTheme.orange, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final Gradient gradient;
  final double size;
  final double opacity;
  const _Blob({required this.gradient, required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: gradient,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
