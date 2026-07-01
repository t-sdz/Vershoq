import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Gère le mode de l'app (spontané / défis) et la banque de défis.
class ChallengeService {
  static const _modeKey = 'app_mode'; // 'normal' | 'challenge'

  /// Défis avec un emplacement {name} remplacé par un membre du groupe.
  static const templates = <String>[
    'Prends {name} en photo sans qu\'il/elle s\'en rende compte 🤫',
    'Fais le porté de Dirty Dancing avec {name} 🕺',
    'Selfie avec {name} en train de faire une grimace 😜',
    'Imite {name} sur la photo 🎭',
    'Prends {name} en pleine action 📸',
    'Fais un cœur avec les mains avec {name} 💛',
    'Prends {name} dans une pose de super-héros 🦸',
    'Le selfie le plus moche possible avec {name} 🤪',
    'Surprends {name} et capture l\'instant 😲',
    'Photo façon paparazzi de {name} 📷',
    'Prends {name} en plein fou rire 😂',
    'Recrée une pub de parfum avec {name} 💫',
    'Photo dos à dos façon film d\'action avec {name} 🎬',
    'Fais un high five avec {name} en pleine photo ✋',
  ];

  static Future<bool> isChallengeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_modeKey) ?? 'normal') == 'challenge';
  }

  static Future<void> setChallengeMode(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, on ? 'challenge' : 'normal');
  }

  /// Construit un défi aléatoire pour [name].
  static String randomChallenge(String name, Random random) {
    final t = templates[random.nextInt(templates.length)];
    return t.replaceAll('{name}', name);
  }
}
