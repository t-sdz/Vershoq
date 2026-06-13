import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/names_service.dart';
import '../services/notification_service.dart';
import '../theme/v_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<String> _names = [];

  // Notifications
  bool _timeLimitEnabled = true;
  int _startHour = 9;
  int _endHour = 21;
  int _minCount = 2;
  int _maxCount = 5;

  // Countdown
  bool _countdownEnabled = false;
  int _countdownSeconds = 15;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final names = await NamesService.getNames();
    if (mounted) {
      setState(() {
        _names = names;
        _timeLimitEnabled = prefs.getBool('notif_time_limit_enabled') ?? true;
        _startHour = prefs.getInt('notif_start_hour') ?? 9;
        _endHour = prefs.getInt('notif_end_hour') ?? 21;
        _minCount = prefs.getInt('notif_min_count') ?? 2;
        _maxCount = prefs.getInt('notif_max_count') ?? 5;
        _countdownEnabled = prefs.getBool('countdown_enabled') ?? false;
        _countdownSeconds = prefs.getInt('countdown_seconds') ?? 15;
        _loading = false;
      });
    }
  }

  Future<void> _saveNotifSettings() async {
    if (_startHour > _endHour) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('L\'heure de début doit être avant l\'heure de fin.')),
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_time_limit_enabled', _timeLimitEnabled);
    await prefs.setInt('notif_start_hour', _startHour);
    await prefs.setInt('notif_end_hour', _endHour);
    await prefs.setInt('notif_min_count', _minCount);
    await prefs.setInt('notif_max_count', _maxCount);
    await NotificationService.cancelAll();
    await NotificationService.scheduleRandom();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notifications replanifiées !')),
      );
    }
  }

  Future<void> _saveCountdownSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('countdown_enabled', _countdownEnabled);
    await prefs.setInt('countdown_seconds', _countdownSeconds);
  }

  Future<void> _addName() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ajouter un prénom'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Prénom...'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Ajouter')),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await NamesService.addName(name);
      await _load();
    }
  }

  Future<void> _removeName(String name) async {
    if (_names.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Il doit rester au moins un prénom dans la liste.')),
      );
      return;
    }
    await NamesService.removeName(name);
    await _load();
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
          _SectionTitle('Notifications'),
          const SizedBox(height: 8),
          _buildNotifCard(),
          const SizedBox(height: 12),
          GradientButton(
            label: 'Appliquer et replanifier',
            gradient: VTheme.solarGradient,
            shadows: VTheme.glowSolar,
            onPressed: _saveNotifSettings,
          ),
          const SizedBox(height: 32),
          _SectionTitle('Compte à rebours'),
          const SizedBox(height: 8),
          _buildCountdownCard(),
          const SizedBox(height: 32),
          _SectionTitle('Liste des prénoms'),
          const SizedBox(height: 8),
          ..._names.map(
            (name) => ListTile(
              title: Text(name),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _removeName(name),
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _addName,
            icon: const Icon(Icons.add),
            label: const Text('Ajouter un prénom'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildNotifCard() {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      shadowColor: VTheme.orange.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Toggle heures
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Limiter les heures',
                  style: TextStyle(color: VTheme.warmDark)),
              subtitle: Text(
                _timeLimitEnabled
                    ? 'Entre ${_startHour}h00 et ${_endHour}h00'
                    : 'À toute heure de la journée',
                style: const TextStyle(color: VTheme.warmMuted, fontSize: 12),
              ),
              value: _timeLimitEnabled,
              activeColor: VTheme.orange,
              onChanged: (v) => setState(() => _timeLimitEnabled = v),
            ),

            // Heures de début / fin (visibles seulement si toggle actif)
            if (_timeLimitEnabled) ...[
              const Divider(color: Color(0xFFFFE8D6)),
              const SizedBox(height: 4),
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

            const Divider(color: Color(0xFFFFE8D6)),
            const SizedBox(height: 4),

            // Min / Max par jour
            const Text('Notifications par jour',
                style: TextStyle(
                    color: VTheme.warmDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
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
                style:
                    const TextStyle(color: VTheme.warmMuted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountdownCard() {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Activer le compte à rebours',
                  style: TextStyle(color: VTheme.warmDark)),
              subtitle: const Text(
                'Capture automatique à la fin du temps',
                style: TextStyle(color: VTheme.warmMuted, fontSize: 12),
              ),
              value: _countdownEnabled,
              activeColor: VTheme.orange,
              onChanged: (v) {
                setState(() => _countdownEnabled = v);
                _saveCountdownSettings();
              },
            ),
            if (_countdownEnabled)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SliderRow(
                  label: 'Durée',
                  value: _countdownSeconds.toDouble().clamp(5, 60),
                  min: 5,
                  max: 60,
                  display: '${_countdownSeconds}s',
                  onChanged: (v) {
                    setState(() => _countdownSeconds = v.round());
                    _saveCountdownSettings();
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
      style: const TextStyle(
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

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.display,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(label,
              style: const TextStyle(color: VTheme.warmDark, fontSize: 13)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: (max - min).round(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(display,
              textAlign: TextAlign.right,
              style: const TextStyle(
                  color: VTheme.warmDark, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
