import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TomoPalette {
  const TomoPalette._();

  static const Color bg = Color(0xFF0A0F0C);
  static const Color bgTop = Color(0xFF122018);
  static const Color bgBottom = Color(0xFF08100C);
  static const Color surface = Color(0xCC131B17);
  static const Color surfaceStrong = Color(0xE61B2620);
  static const Color surfaceRaised = Color(0xFF1D2721);
  static const Color border = Color(0x12FFFFFF);
  static const Color lightBorder = Color(0x12000000);
  static const Color primary = Color(0xFF3CB45A);
  static const Color primaryBright = Color(0xFF52D473);
  static const Color primaryDeep = Color(0xFF245A37);
  static const Color amber = Color(0xFFD29B3C);
  static const Color danger = Color(0xFFDC4646);
  static const Color text = Color(0xFFF2F5F1);
  static const Color textSubtle = Color(0xFFA9B5AD);
  static const Color textMuted = Color(0xFF6B7A72);
  static const Color lightBg = Color(0xFFF4F7F3);
  static const Color lightBgTop = Color(0xFFF7FBF6);
  static const Color lightSurface = Color(0xF5FFFFFF);
  static const Color lightSurfaceRaised = Color(0xFFEAF1EB);
  static const Color lightText = Color(0xFF111814);
  static const Color lightTextSubtle = Color(0xFF546056);
}

class TomoDecorations {
  const TomoDecorations._();

  static List<BoxShadow> cardShadow(bool isDark, {Color? tint}) {
    final color = tint ?? Colors.black;
    return [
      BoxShadow(
        color: color.withOpacity(isDark ? 0.34 : 0.08),
        blurRadius: isDark ? 28 : 16,
        offset: const Offset(0, 10),
      ),
    ];
  }

  static BoxDecoration card({
    required bool isDark,
    double radius = 24,
    Color? color,
    Gradient? gradient,
    bool elevated = true,
  }) {
    return BoxDecoration(
      color: gradient == null
          ? (color ??
              (isDark ? TomoPalette.surfaceStrong : TomoPalette.lightSurface))
          : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: isDark ? TomoPalette.border : TomoPalette.lightBorder,
      ),
      boxShadow: elevated ? cardShadow(isDark) : null,
    );
  }

  static BoxDecoration pill({
    required bool isDark,
    Color? color,
    Gradient? gradient,
  }) {
    return BoxDecoration(
      color: gradient == null
          ? (color ??
              (isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.04)))
          : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: isDark ? Colors.white.withOpacity(0.08) : Colors.black12,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(isDark ? 0.24 : 0.04),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}

class TomoBackdrop extends StatelessWidget {
  const TomoBackdrop({
    super.key,
    required this.isDark,
    required this.child,
  });

  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = isDark
        ? const [
            TomoPalette.bgTop,
            TomoPalette.bg,
            TomoPalette.bgBottom,
          ]
        : const [
            TomoPalette.lightBgTop,
            TomoPalette.lightBg,
            Color(0xFFEAF2EC),
          ];

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -90,
            right: -40,
            child: _GlowOrb(
              size: 240,
              color: (isDark ? TomoPalette.primary : TomoPalette.primaryDeep)
                  .withOpacity(isDark ? 0.16 : 0.10),
            ),
          ),
          Positioned(
            top: 120,
            left: -70,
            child: _GlowOrb(
              size: 200,
              color: (isDark ? TomoPalette.primaryBright : TomoPalette.primary)
                  .withOpacity(isDark ? 0.10 : 0.07),
            ),
          ),
          Positioned(
            bottom: -100,
            right: -30,
            child: _GlowOrb(
              size: 220,
              color: (isDark ? TomoPalette.amber : TomoPalette.primaryBright)
                  .withOpacity(isDark ? 0.08 : 0.05),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class TomoGlassCard extends StatelessWidget {
  const TomoGlassCard({
    super.key,
    required this.isDark,
    required this.child,
    this.radius = 24,
    this.padding,
    this.margin,
    this.color,
    this.gradient,
    this.border,
  });

  final bool isDark;
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Gradient? gradient;
  final Border? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: TomoDecorations.cardShadow(
          isDark,
          tint: gradient == null ? null : TomoPalette.primary,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: gradient == null
                  ? (color ??
                      (isDark ? TomoPalette.surface : TomoPalette.lightSurface))
                  : null,
              gradient: gradient,
              borderRadius: BorderRadius.circular(radius),
              border: border ??
                  Border.all(
                    color:
                        isDark ? TomoPalette.border : TomoPalette.lightBorder,
                  ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class TomoSectionLabel extends StatelessWidget {
  const TomoSectionLabel(this.label, {super.key, required this.isDark});

  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.dmSans(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
        color: isDark ? TomoPalette.textMuted : TomoPalette.lightTextSubtle,
      ),
    );
  }
}

class TomoChip extends StatelessWidget {
  const TomoChip({
    super.key,
    required this.label,
    required this.color,
    this.small = false,
  });

  final String label;
  final Color color;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 10 : 12,
        vertical: small ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: small ? 10 : 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              color.withOpacity(0),
            ],
          ),
        ),
      ),
    );
  }
}
