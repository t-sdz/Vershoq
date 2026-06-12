import 'package:flutter/material.dart';

class VTheme {
  // ── Core colors ────────────────────────────────────────────────────────────
  static const warmDark  = Color(0xFF3D1A08);
  static const warmMuted = Color(0xFF9A6B50);
  static const bgWarm    = Color(0xFFFFF1D6);
  static const sunshine  = Color(0xFFFFD600);
  static const coral     = Color(0xFFFF6B6B);
  static const sky       = Color(0xFF4FC3F7);
  static const orange    = Color(0xFFFF8A3D);
  static const hotPink   = Color(0xFFFF5C8A);
  static const peach     = Color(0xFFFFB86B);

  // ── Gradients ──────────────────────────────────────────────────────────────
  static const bgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFF1D6), Color(0xFFFFD9C2), Color(0xFFFFC2CE)],
  );

  static const solarGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFFFD600), Color(0xFFFF8A3D), Color(0xFFFF5C8A)],
  );

  static const sunriseGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFE08A), Color(0xFFFF9F6B), Color(0xFFFF6B6B)],
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

  // ── Shadows ────────────────────────────────────────────────────────────────
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
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16))
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
