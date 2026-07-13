import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/group_service.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import '../services/theme_service.dart';
import '../theme/v_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Vrai si l'utilisateur est admin du groupe actif (accès notif + chrono).
  bool _isAdmin = false;
  String? _groupId;

  // Notifications (config partagée du groupe)
  bool _timeLimitEnabled = true;
  int _startHour = 9;
  int _endHour = 21;
  int _minCount = 2;
  int _maxCount = 5;
  int _minNames = 1;
  int _maxNames = 3;
  List<String> _extraNames = [];
  final TextEditingController _extraNameCtrl = TextEditingController();

  // Countdown (local)
  bool _countdownEnabled = false;
  int _countdownSeconds = 15;

  bool _notifsEnabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _extraNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    // Version fraîche depuis Firestore (admins à jour), pas le cache local.
    final group = await GroupService.refreshCurrentGroup();
    final user = await GroupService.getCurrentUser();
    final isAdmin = group != null && group.isAdmin(user?.email);
    if (mounted) {
      setState(() {
        _isAdmin = isAdmin;
        _groupId = group?.id;
        // Config des notifs : partagée par le groupe.
        _notifsEnabled = group?.notifEnabled ?? true;
        _timeLimitEnabled = group?.notifTimeLimit ?? true;
        _startHour = group?.notifStartHour ?? 9;
        _endHour = group?.notifEndHour ?? 21;
        _minCount = group?.notifMinCount ?? 2;
        _maxCount = group?.notifMaxCount ?? 5;
        _minNames = group?.notifMinNames ?? 1;
        _maxNames = group?.notifMaxNames ?? 3;
        _extraNames = List<String>.from(group?.extraNames ?? const []);
        // Compte à rebours : local.
        _countdownEnabled = prefs.getBool('countdown_enabled') ?? false;
        _countdownSeconds = prefs.getInt('countdown_seconds') ?? 15;
        _loading = false;
      });
    }
  }

  Map<String, dynamic> _buildConfig() => {
        'enabled': _notifsEnabled,
        'timeLimit': _timeLimitEnabled,
        'startHour': _startHour,
        'endHour': _endHour,
        'minCount': _minCount,
        'maxCount': _maxCount,
        'minNames': _minNames,
        'maxNames': _maxNames,
        'extraNames': _extraNames,
      };

  Future<void> _saveConfig({String? message}) async {
    if (_groupId == null) return;
    await GroupService.updateNotifConfig(_groupId!, _buildConfig());
    await NotificationService.cancelAll();
    await NotificationService.scheduleRandom();
    if (mounted && message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _saveNotifSettings() async {
    if (_startHour > _endHour) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('L\'heure de début doit être avant l\'heure de fin.')),
      );
      return;
    }
    await _saveConfig(message: 'Notifications replanifiées !');
  }

  Future<void> _saveCountdownSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('countdown_enabled', _countdownEnabled);
    await prefs.setInt('countdown_seconds', _countdownSeconds);
    // Replanifie pour que le chrono des notifs suive la nouvelle durée.
    await NotificationService.cancelAll();
    await NotificationService.scheduleRandom();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compte à rebours enregistré !')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: VTheme.bgWarm,
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle('Apparence'),
          const SizedBox(height: 8),
          _buildAppearanceCard(),
          const SizedBox(height: 32),
          // Réservé à l'admin du groupe.
          if (_isAdmin) ...[
            _SectionTitle('Notifications du groupe'),
            const SizedBox(height: 8),
            _buildAdminActionsCard(),
            const SizedBox(height: 24),

            _SectionTitle('Limiter les heures'),
            const SizedBox(height: 8),
            _buildHoursCard(),
            _validateButton('Valider les heures', _saveNotifSettings),
            const SizedBox(height: 24),

            _SectionTitle('Notifications par jour'),
            const SizedBox(height: 8),
            _buildCountCard(),
            _validateButton('Valider',
                () => _saveConfig(message: 'Notifications par jour enregistrées !')),
            const SizedBox(height: 24),

            _SectionTitle('Noms par photo'),
            const SizedBox(height: 8),
            _buildNamesCard(),
            _validateButton('Valider',
                () => _saveConfig(message: 'Noms par photo enregistrés !')),
            const SizedBox(height: 24),

            _SectionTitle('Prénoms en plus'),
            const SizedBox(height: 8),
            _buildExtraNamesCard(),
            const SizedBox(height: 32),

            _SectionTitle('Compte à rebours'),
            const SizedBox(height: 8),
            _buildCountdownCard(),
            const SizedBox(height: 12),
            GradientButton(
              label: 'Enregistrer le compte à rebours',
              gradient: VTheme.solarGradient,
              shadows: VTheme.glowSolar,
              onPressed: _saveCountdownSettings,
            ),
            const SizedBox(height: 32),
          ],
        ],
      ),
    );
  }

  Widget _buildAppearanceCard() {
    return Card(
      color: VTheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                  VTheme.isDark ? Icons.dark_mode : Icons.light_mode,
                  color: VTheme.orange),
              title: Text('Mode sombre',
                  style: TextStyle(color: VTheme.warmDark)),
              subtitle: Text(VTheme.isDark ? 'Activé' : 'Désactivé',
                  style: TextStyle(color: VTheme.warmMuted, fontSize: 12)),
              value: VTheme.isDark,
              activeColor: VTheme.orange,
              onChanged: (v) async {
                await ThemeService.setDark(v);
                if (mounted) setState(() {});
              },
            ),
            Divider(height: 24, color: VTheme.hairline),
            Text('Couleur',
                style: TextStyle(
                    color: VTheme.warmDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 16,
              runSpacing: 14,
              children: VTheme.palettes.map((p) {
                final selected = VTheme.palette.id == p.id;
                return GestureDetector(
                  onTap: () async {
                    await ThemeService.setPalette(p);
                    if (mounted) setState(() {});
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                              colors: p.gradient,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: selected
                                  ? VTheme.warmDark
                                  : Colors.transparent,
                              width: 3),
                        ),
                        child: selected
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 22)
                            : null,
                      ),
                      const SizedBox(height: 5),
                      Text(p.label,
                          style: TextStyle(
                              color: VTheme.warmMuted, fontSize: 11)),
                    ],
                  ),
                );
              }).toList(),
            ),
            const Divider(height: 32, color: Color(0xFFFFE8D6)),
            Text('Police des titres',
                style: TextStyle(
                    color: VTheme.warmDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            _fontChips(
              selected: VTheme.titleFont,
              onPick: (f) async {
                await ThemeService.setTitleFont(f);
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(height: 20),
            Text('Police du texte',
                style: TextStyle(
                    color: VTheme.warmDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            _fontChips(
              selected: VTheme.bodyFont,
              onPick: (f) async {
                await ThemeService.setBodyFont(f);
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _fontChips({
    required String selected,
    required Future<void> Function(String) onPick,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: VTheme.fonts.map((f) {
        final sel = f == selected;
        return ChoiceChip(
          label: Text(
            f,
            // Couleur de texte constante (lisible) quel que soit l'état.
            style: GoogleFonts.getFont(
              f,
              color: VTheme.warmDark,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          selected: sel,
          showCheckmark: false,
          // La sélection est indiquée par la bordure, pas par le fond,
          // pour que le texte garde la même couleur.
          selectedColor: VTheme.orange.withOpacity(0.18),
          backgroundColor: VTheme.surface,
          side: BorderSide(
              color: sel ? VTheme.orange : VTheme.hairline,
              width: sel ? 2 : 1),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          onSelected: (_) => onPick(f),
        );
      }).toList(),
    );
  }

  Widget _buildAdminActionsCard() {
    return Card(
      color: VTheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                  _notifsEnabled
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                  color: VTheme.orange),
              title: Text('Notifications activées',
                  style: TextStyle(color: VTheme.warmDark)),
              subtitle: Text(
                  _notifsEnabled
                      ? 'Les rappels aléatoires sont actifs'
                      : 'Aucun rappel ne sera envoyé',
                  style: TextStyle(color: VTheme.warmMuted, fontSize: 12)),
              value: _notifsEnabled,
              activeColor: VTheme.orange,
              onChanged: (v) async {
                setState(() => _notifsEnabled = v);
                await _saveConfig(
                    message: v
                        ? 'Notifications activées'
                        : 'Notifications désactivées');
              },
            ),
            Divider(height: 4, color: VTheme.hairline),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.send_outlined, color: VTheme.orange),
              title: Text('Envoyer une notif à tout le groupe',
                  style: TextStyle(color: VTheme.warmDark)),
              subtitle: Text('Notifie tous les membres en même temps',
                  style: TextStyle(color: VTheme.warmMuted, fontSize: 12)),
              onTap: () async {
                // Push serveur (tout le groupe, simultané) si configuré,
                // sinon notif locale sur cet appareil.
                // Graine COMMUNE : tous les téléphones (dont l'expéditeur)
                // forment le même appariement -> réciproque (Tess<->Max).
                final seed = Random().nextInt(0x7fffffff);
                var sent = false;
                if (_groupId != null) {
                  sent = await PushService.sendGroupPush(
                    groupId: _groupId!,
                    seed: seed,
                    title: "📸 Snap'It",
                    body: "C'est le moment ! Prends vite ta photo.",
                  );
                }
                if (sent) {
                  // L'expéditeur fait partie du groupe : arme sa bannière ET
                  // affiche une notif locale tout de suite (sans attendre le
                  // renvoi FCM à soi-même, qui peut tarder au 1er abonnement).
                  // Même id de notif (9998) que le renvoi FCM -> pas de doublon.
                  // MÊME graine que les autres -> même appariement.
                  final label =
                      await NotificationService.buildMyMomentLabel(seed: seed) ??
                          '';
                  await NotificationService.registerRemoteMoment(label);
                  await NotificationService.showRemote(
                    "📸 Snap'It",
                    label.trim().isEmpty
                        ? "C'est le moment ! Prends ta photo."
                        : "Prends vite ta photo avec $label !",
                    label,
                  );
                } else {
                  await NotificationService.sendImmediate();
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(sent
                          ? 'Notif envoyée à tout le groupe !'
                          : 'Notif envoyée (sur cet appareil)')));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsCard(List<Widget> children) => Card(
        color: VTheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      );

  Widget _validateButton(String label, VoidCallback onPressed) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: GradientButton(
          label: label,
          gradient: VTheme.solarGradient,
          shadows: VTheme.glowSolar,
          onPressed: onPressed,
        ),
      );

  Widget _buildHoursCard() {
    return _settingsCard([
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('Limiter les heures',
            style: TextStyle(color: VTheme.warmDark)),
        subtitle: Text(
          _timeLimitEnabled
              ? 'Entre ${_startHour}h00 et ${_endHour}h00'
              : 'À toute heure de la journée',
          style: TextStyle(color: VTheme.warmMuted, fontSize: 12),
        ),
        value: _timeLimitEnabled,
        activeColor: VTheme.orange,
        onChanged: (v) => setState(() => _timeLimitEnabled = v),
      ),
      if (_timeLimitEnabled) ...[
        Divider(color: VTheme.hairline),
        _SliderRow(
          label: 'Heure de début',
          value: _startHour.toDouble(),
          min: 0,
          max: 23,
          display: '${_startHour}h00',
          onChanged: (v) {
            final h = v.round();
            setState(() {
              _startHour = h;
              if (_endHour <= _startHour) _endHour = _startHour;
            });
          },
        ),
        _SliderRow(
          label: 'Heure de fin',
          value: _endHour.toDouble(),
          min: 0,
          max: 23,
          display: '${_endHour}h00',
          onChanged: (v) {
            final h = v.round();
            setState(() {
              _endHour = h;
              if (_startHour > _endHour) _startHour = _endHour;
            });
          },
        ),
      ],
    ]);
  }

  Widget _buildCountCard() {
    return _settingsCard([
      const SizedBox(height: 8),
      _SliderRow(
        label: 'Minimum',
        value: _minCount.toDouble(),
        min: 1,
        max: 20,
        display: '$_minCount',
        onChanged: (v) {
          final n = v.round();
          setState(() {
            _minCount = n;
            if (_maxCount < _minCount) _maxCount = _minCount;
          });
        },
      ),
      _SliderRow(
        label: 'Maximum',
        value: _maxCount.toDouble(),
        min: 1,
        max: 20,
        display: '$_maxCount',
        onChanged: (v) {
          final n = v.round();
          setState(() {
            _maxCount = n;
            if (_minCount > _maxCount) _minCount = _maxCount;
          });
        },
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'Entre $_minCount et $_maxCount notifications aléatoires par jour',
          style: TextStyle(color: VTheme.warmMuted, fontSize: 12),
        ),
      ),
    ]);
  }

  Widget _buildNamesCard() {
    return _settingsCard([
      const SizedBox(height: 8),
      _SliderRow(
        label: 'Minimum',
        value: _minNames.toDouble(),
        min: 1,
        max: 10,
        display: '$_minNames',
        onChanged: (v) {
          final n = v.round();
          setState(() {
            _minNames = n;
            if (_maxNames < _minNames) _maxNames = _minNames;
          });
        },
      ),
      _SliderRow(
        label: 'Maximum',
        value: _maxNames.toDouble(),
        min: 1,
        max: 10,
        display: '$_maxNames',
        onChanged: (v) {
          final n = v.round();
          setState(() {
            _maxNames = n;
            if (_minNames > _maxNames) _minNames = _maxNames;
          });
        },
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'Chaque photo à prendre avec $_minNames à $_maxNames personne(s)',
          style: TextStyle(color: VTheme.warmMuted, fontSize: 12),
        ),
      ),
    ]);
  }

  Future<void> _addExtraName() async {
    final name = _extraNameCtrl.text.trim();
    if (name.isEmpty) return;
    // Pas de doublon (insensible à la casse).
    if (_extraNames.any((n) => n.toLowerCase() == name.toLowerCase())) {
      _extraNameCtrl.clear();
      return;
    }
    setState(() {
      _extraNames = [..._extraNames, name];
      _extraNameCtrl.clear();
    });
    await _saveConfig();
  }

  Future<void> _removeExtraName(String name) async {
    setState(() {
      _extraNames = _extraNames.where((n) => n != name).toList();
    });
    await _saveConfig();
  }

  Widget _buildExtraNamesCard() {
    return _settingsCard([
      Text(
        'Ajoute des prénoms (même des gens pas sur l\'app). Ils peuvent '
        'apparaître dans les notifs « prends une photo avec… ».',
        style: TextStyle(color: VTheme.warmMuted, fontSize: 12),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _extraNameCtrl,
              textCapitalization: TextCapitalization.words,
              style: TextStyle(color: VTheme.warmDark),
              decoration: InputDecoration(
                hintText: 'Nouveau prénom',
                isDense: true,
              ),
              onSubmitted: (_) => _addExtraName(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _addExtraName,
            icon: Icon(Icons.add_circle, color: VTheme.orange, size: 32),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (_extraNames.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text('Aucun prénom ajouté pour l\'instant.',
              style: TextStyle(color: VTheme.warmMuted, fontSize: 12)),
        )
      else
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _extraNames
              .map((n) => Chip(
                    label: Text(n, style: TextStyle(color: VTheme.warmDark)),
                    backgroundColor: VTheme.bgWarm,
                    deleteIconColor: VTheme.warmMuted,
                    onDeleted: () => _removeExtraName(n),
                  ))
              .toList(),
        ),
    ]);
  }

  String _fmtCountdown(int seconds) {
    if (seconds <= 0) return '0s';
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s == 0 ? '${m}min' : '${m}m$s';
  }

  Widget _buildCountdownCard() {
    return Card(
      color: VTheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Activer le compte à rebours',
                  style: TextStyle(color: VTheme.warmDark)),
              subtitle: Text(
                'Capture automatique à la fin du temps',
                style: TextStyle(color: VTheme.warmMuted, fontSize: 12),
              ),
              value: _countdownEnabled,
              activeColor: VTheme.orange,
              onChanged: (v) => setState(() => _countdownEnabled = v),
            ),
            if (_countdownEnabled)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SliderRow(
                  label: 'Durée',
                  value: _countdownSeconds.toDouble().clamp(0, 600),
                  min: 0,
                  max: 600,
                  divisions: 40, // paliers de 15 s, de 0 à 10 min
                  display: _fmtCountdown(_countdownSeconds),
                  onChanged: (v) {
                    final snapped = (v / 15).round() * 15;
                    setState(() => _countdownSeconds = snapped);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: VTheme.warmMuted,
        fontWeight: FontWeight.bold,
        fontSize: 11,
        letterSpacing: 2,
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String display;
  final int? divisions;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.display,
    this.divisions,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(label,
              style: TextStyle(color: VTheme.warmDark, fontSize: 13)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions ?? (max - min).round(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(display,
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: VTheme.warmDark, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
