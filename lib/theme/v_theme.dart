import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette d'accent sélectionnable par l'utilisateur.
class VPalette {
  final String id;
  final String label;
  final Color accent; // couleur principale (boutons, icônes, sliders…)
  final List<Color> gradient; // dégradé principal (3 couleurs)
  final Color highlight; // surbrillance (ex : prénom « feat. »)

  const VPalette({
    required this.id,
    required this.label,
    required this.accent,
    required this.gradient,
    required this.highlight,
  });
}

class VTheme {
  // ── Choix utilisateur (modifiés via ThemeService) ──────────────────────────
  static VPalette palette = palettes.first;
  static String titleFont = 'Space Grotesk';
  static String bodyFont = 'Inter';

  static const List<VPalette> palettes = [
    VPalette(
      id: 'solaire',
      label: 'Solaire',
      accent: Color(0xFFFF8A3D),
      gradient: [Color(0xFFFFD600), Color(0xFFFF8A3D), Color(0xFFFF5C8A)],
      highlight: Color(0xFFFFD600),
    ),
    VPalette(
      id: 'ocean',
      label: 'Océan',
      accent: Color(0xFF2E9BF0),
      gradient: [Color(0xFF5EE7DF), Color(0xFF2E9BF0), Color(0xFF7C5CFF)],
      highlight: Color(0xFF5EE7DF),
    ),
    VPalette(
      id: 'foret',
      label: 'Forêt',
      accent: Color(0xFF1FA971),
      gradient: [Color(0xFFA8E063), Color(0xFF1FA971), Color(0xFF0E9E8E)],
      highlight: Color(0xFFC6F68D),
    ),
    VPalette(
      id: 'violet',
      label: 'Violet',
      accent: Color(0xFF8B5CF6),
      gradient: [Color(0xFFFF8AD8), Color(0xFF8B5CF6), Color(0xFF5B7CFA)],
      highlight: Color(0xFFFF8AD8),
    ),
    VPalette(
      id: 'rose',
      label: 'Rose',
      accent: Color(0xFFFF4D8D),
      gradient: [Color(0xFFFFB86B), Color(0xFFFF4D8D), Color(0xFFFF2D55)],
      highlight: Color(0xFFFFC36B),
    ),
    VPalette(
      id: 'menthe',
      label: 'Menthe',
      accent: Color(0xFF14B8A6),
      gradient: [Color(0xFF6EE7B7), Color(0xFF14B8A6), Color(0xFF0EA5E9)],
      highlight: Color(0xFF6EE7B7),
    ),
  ];

  static const List<String> fonts = [
    'Space Grotesk',
    'Poppins',
    'Outfit',
    'Sora',
    'Nunito',
    'Inter',
    'DM Sans',
    'Quicksand',
  ];

  // ── Typographie ────────────────────────────────────────────────────────────
  /// Gros titres « sticker », dans la police de titre choisie.
  static TextStyle grotesk({
    double? fontSize,
    FontWeight fontWeight = FontWeight.w700,
    Color color = warmDark,
    double letterSpacing = -0.5,
    double? height,
    List<Shadow>? shadows,
  }) =>
      GoogleFonts.getFont(
        titleFont,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
        shadows: shadows,
      );

  // ── Ancres fixes (texte / fond) ────────────────────────────────────────────
  static const warmDark = Color(0xFF3D1A08);
  static const warmMuted = Color(0xFF9A6B50);
  static const bgWarm = Color(0xFFFFF1D6);

  // ── Accents dynamiques (suivent la palette choisie) ────────────────────────
  static Color get orange => palette.accent;
  static Color get sunshine => palette.highlight;

  static LinearGradient get solarGradient => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: palette.gradient,
      );

  static LinearGradient get sunriseGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: palette.gradient,
      );

  // ── Couleurs / dégradés fixes secondaires ──────────────────────────────────
  static const coral = Color(0xFFFF6B6B);
  static const sky = Color(0xFF4FC3F7);
  static const hotPink = Color(0xFFFF5C8A);
  static const peach = Color(0xFFFFB86B);

  static const bgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFF1D6), Color(0xFFFFD9C2), Color(0xFFFFC2CE)],
  );

  static const coralGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF8A3D), Color(0xFFFF6B6B)],
  );

  static const skyGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4FC3F7), Color(0xFFA78BFA)],
  );

  // ── Avatar gradients (cycle with index % 6) ───────────────────────────────
  static const avatarGradients = [
    LinearGradient(colors: [Color(0xFFFFD600), Color(0xFFFF6B6B)], begin: Alignment.topLeft, end: Alignment.bottomRight),
    LinearGradient(colors: [Color(0xFF4FC3F7), Color(0xFFA78BFA)], begin: Alignment.topLeft, end: Alignment.bottomRight),
    LinearGradient(colors: [Color(0xFFFF8A3D), Color(0xFFFF5C8A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
    LinearGradient(colors: [Color(0xFF6EE7B7), Color(0xFF4FC3F7)], begin: Alignment.topLeft, end: Alignment.bottomRight),
    LinearGradient(colors: [Color(0xFFFFB86B), Color(0xFFFFD600)], begin: Alignment.topLeft, end: Alignment.bottomRight),
    LinearGradient(colors: [Color(0xFFF472B6), Color(0xFFFB7185)], begin: Alignment.topLeft, end: Alignment.bottomRight),
  ];

  // ── Ombres (suivent l'accent) ──────────────────────────────────────────────
  static List<BoxShadow> get softShadow => [
        BoxShadow(color: orange.withOpacity(0.22), blurRadius: 28, offset: const Offset(0, 10)),
      ];

  static List<BoxShadow> get glowSolar => [
        BoxShadow(color: orange.withOpacity(0.45), blurRadius: 40, spreadRadius: -6, offset: const Offset(0, 14)),
      ];

  static List<BoxShadow> get cardShadow => [
        BoxShadow(color: orange.withOpacity(0.10), blurRadius: 20, spreadRadius: -4, offset: const Offset(0, 8)),
      ];
}

// ── Gradient button ────────────────────────────────────────────────────────

class GradientButton extends StatelessWidget {
  final String label;
  final Gradient gradient;
  final VoidCallback? onPressed;
  final List<BoxShadow>? shadows;
  final double height;

  const GradientButton({
    super.key,
    required this.label,
    required this.gradient,
    this.onPressed,
    this.shadows,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    final active = onPressed != null;
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: active ? gradient : null,
        color: active ? null : const Color(0xFFE0D0C8),
        borderRadius: BorderRadius.circular(30),
        boxShadow: active ? shadows : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(30),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(30),
          splashColor: Colors.white24,
          child: Center(
            child: active
                ? Text(label,
                    style: VTheme.grotesk(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        letterSpacing: 0))
                : const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white)),
          ),
        ),
      ),
    );
  }
}

// ── Gradient scaffold background ───────────────────────────────────────────

class GradientBackground extends StatelessWidget {
  final Widget child;
  const GradientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: VTheme.bgGradient),
      child: child,
    );
  }
}
