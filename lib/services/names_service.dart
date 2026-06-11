import 'package:shared_preferences/shared_preferences.dart';

class NamesService {
  static const _key = 'vershoq_names';

  static const List<String> defaultNames = [
    'Alice',
    'Bob',
    'Charlie',
    'Diana',
    'Emma',
    'François',
    'Gabriel',
    'Hélène',
    'Ivan',
    'Julia',
    'Kevin',
    'Laura',
    'Martin',
    'Nina',
    'Olivier',
    'Pierre',
    'Quentin',
    'Rachel',
    'Sophie',
    'Thomas',
  ];

  static Future<List<String>> getNames() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? List.from(defaultNames);
  }

  static Future<void> saveNames(List<String> names) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, names);
  }

  static Future<void> addName(String name) async {
    final names = await getNames();
    final trimmed = name.trim();
    if (trimmed.isNotEmpty && !names.contains(trimmed)) {
      names.add(trimmed);
      await saveNames(names);
    }
  }

  static Future<void> removeName(String name) async {
    final names = await getNames();
    names.remove(name);
    await saveNames(names);
  }
}
