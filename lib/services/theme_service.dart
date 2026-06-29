import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/v_theme.dart';

/// Enveloppe un écran pour qu'il se reconstruise quand le thème change
/// (les couleurs VTheme étant lues statiquement, sans ce scope les écrans
/// déjà empilés gardent leurs anciennes couleurs).
class ThemedScope extends StatelessWidget {
  final WidgetBuilder builder;
  const ThemedScope({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ThemeService.revision,
      builder: (context, _, __) => builder(context),
    );
  }
}

/// Gère le thème choisi par l'utilisateur (palette + polices), le persiste,
/// et notifie l'app pour qu'elle se re-rende instantanément.
class ThemeService {
  static const _paletteKey = 'theme_palette';
  static const _titleFontKey = 'theme_title_font';
  static const _bodyFontKey = 'theme_body_font';
  static const _darkKey = 'theme_dark';

  /// Incrémenté à chaque changement → déclenche la reconstruction du thème.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// À appeler au démarrage, avant runApp.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final pid = prefs.getString(_paletteKey);
    if (pid != null) {
      VTheme.palette = VTheme.palettes.firstWhere(
        (p) => p.id == pid,
        orElse: () => VTheme.palettes.first,
      );
    }
    VTheme.titleFont = prefs.getString(_titleFontKey) ?? VTheme.titleFont;
    VTheme.bodyFont = prefs.getString(_bodyFontKey) ?? VTheme.bodyFont;
    VTheme.isDark = prefs.getBool(_darkKey) ?? false;
  }

  static Future<void> setDark(bool dark) async {
    VTheme.isDark = dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkKey, dark);
    revision.value++;
  }

  static Future<void> setPalette(VPalette palette) async {
    VTheme.palette = palette;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_paletteKey, palette.id);
    revision.value++;
  }

  static Future<void> setTitleFont(String font) async {
    VTheme.titleFont = font;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_titleFontKey, font);
    revision.value++;
  }

  static Future<void> setBodyFont(String font) async {
    VTheme.bodyFont = font;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bodyFontKey, font);
    revision.value++;
  }
}
