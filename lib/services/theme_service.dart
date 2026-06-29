import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/v_theme.dart';

/// Gère le thème choisi par l'utilisateur (palette + polices), le persiste,
/// et notifie l'app pour qu'elle se re-rende instantanément.
class ThemeService {
  static const _paletteKey = 'theme_palette';
  static const _titleFontKey = 'theme_title_font';
  static const _bodyFontKey = 'theme_body_font';

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
