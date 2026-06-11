import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/names_service.dart';
import '../services/notification_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<String> _names = [];
  int _startHour = 9;
  int _endHour = 21;
  int _dailyCount = 3;
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
        _startHour = prefs.getInt('notif_start_hour') ?? 9;
        _endHour = prefs.getInt('notif_end_hour') ?? 21;
        _dailyCount = prefs.getInt('notif_daily_count') ?? 3;
        _countdownEnabled = prefs.getBool('countdown_enabled') ?? false;
        _countdownSeconds = prefs.getInt('countdown_seconds') ?? 15;
        _loading = false;
      });
    }
  }

  Future<void> _saveNotifSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notif_start_hour', _startHour);
    await prefs.setInt('notif_end_hour', _endHour);
    await prefs.setInt('notif_daily_count', _dailyCount);
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
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle('Notifications'),
          const SizedBox(height: 8),
          _NotifSettings(
            startHour: _startHour,
            endHour: _endHour,
            dailyCount: _dailyCount,
            onStartHourChanged: (v) => setState(() => _startHour = v),
            onEndHourChanged: (v) => setState(() => _endHour = v),
            onDailyCountChanged: (v) => setState(() => _dailyCount = v),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saveNotifSettings,
            child: const Text('Appliquer et replanifier'),
          ),
          const SizedBox(height: 32),
          _SectionTitle('Compte à rebours'),
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFF111111),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Activer le compte à rebours',
                        style: TextStyle(color: Colors.white)),
                    subtitle: const Text(
                      'Capture automatique à la fin du temps',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    value: _countdownEnabled,
                    activeColor: Colors.white,
                    activeTrackColor: Colors.green,
                    onChanged: (v) {
                      setState(() => _countdownEnabled = v);
                      _saveCountdownSettings();
                    },
                  ),
                  if (_countdownEnabled)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          const Text('Durée',
                              style: TextStyle(color: Colors.white70)),
                          Expanded(
                            child: Slider(
                              value: _countdownSeconds.toDouble().clamp(5, 60),
                              min: 5,
                              max: 60,
                              divisions: 11,
                              label: '$_countdownSeconds s',
                              onChanged: (v) => setState(
                                  () => _countdownSeconds = v.round()),
                              onChangeEnd: (_) => _saveCountdownSettings(),
                            ),
                          ),
                          SizedBox(
                            width: 44,
                            child: Text('${_countdownSeconds}s',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
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
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.bold,
        fontSize: 12,
        letterSpacing: 2,
      ),
    );
  }
}

class _NotifSettings extends StatelessWidget {
  final int startHour;
  final int endHour;
  final int dailyCount;
  final ValueChanged<int> onStartHourChanged;
  final ValueChanged<int> onEndHourChanged;
  final ValueChanged<int> onDailyCountChanged;

  const _NotifSettings({
    required this.startHour,
    required this.endHour,
    required this.dailyCount,
    required this.onStartHourChanged,
    required this.onEndHourChanged,
    required this.onDailyCountChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1A1A2E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SliderRow(
              label: 'Heure de début',
              value: startHour.toDouble(),
              min: 6,
              max: 12,
              onChanged: (v) => onStartHourChanged(v.round()),
              display: '${startHour}h00',
            ),
            _SliderRow(
              label: 'Heure de fin',
              value: endHour.toDouble(),
              min: 16,
              max: 23,
              onChanged: (v) => onEndHourChanged(v.round()),
              display: '${endHour}h00',
            ),
            _SliderRow(
              label: 'Notifications par jour',
              value: dailyCount.toDouble(),
              min: 1,
              max: 10,
              onChanged: (v) => onDailyCountChanged(v.round()),
              display: '$dailyCount',
            ),
          ],
        ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70)),
            Text(display,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: (max - min).round(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
