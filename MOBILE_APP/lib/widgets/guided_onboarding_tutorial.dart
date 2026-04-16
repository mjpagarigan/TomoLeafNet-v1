import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef StartTutorialCallback = Future<void> Function({bool force});

class OnboardingTutorial {
  const OnboardingTutorial._();

  static String _storageKeyForUser(String uid) => 'hasSeenTutorial_$uid';

  static Future<bool> hasSeenForUser(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_storageKeyForUser(uid)) ?? false;
  }

  static Future<void> markSeenForUser(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_storageKeyForUser(uid), true);
  }

  static Future<void> showTutorial(BuildContext context) async {
    final scope = OnboardingTutorialScope.maybeOf(context);
    if (scope == null) return;
    await scope.startTutorial(force: true);
  }
}

class OnboardingTutorialScope extends InheritedWidget {
  const OnboardingTutorialScope({
    super.key,
    required this.startTutorial,
    required super.child,
  });

  final StartTutorialCallback startTutorial;

  static OnboardingTutorialScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<OnboardingTutorialScope>();
  }

  @override
  bool updateShouldNotify(OnboardingTutorialScope oldWidget) {
    return startTutorial != oldWidget.startTutorial;
  }
}

enum TutorialCardPlacement { automatic, above, below }

class TutorialStepData {
  const TutorialStepData({
    required this.targetKey,
    required this.pageIndex,
    required this.icon,
    required this.title,
    required this.description,
    this.preferredPlacement = TutorialCardPlacement.automatic,
  });

  final GlobalKey targetKey;
  final int pageIndex;
  final IconData icon;
  final String title;
  final String description;
  final TutorialCardPlacement preferredPlacement;
}

class OnboardingTutorialOverlay extends StatelessWidget {
  const OnboardingTutorialOverlay({
    super.key,
    required this.steps,
    required this.currentStepIndex,
    required this.onNext,
    required this.onSkip,
    this.onBack,
  });

  final List<TutorialStepData> steps;
  final int currentStepIndex;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final size = media.size;
    final step = steps[currentStepIndex];
    final targetRect = _resolveTargetRect(context, step.targetKey);
    final spotlightRect = targetRect?.inflate(12);
    final showCardBelow =
        _shouldShowCardBelow(step.preferredPlacement, spotlightRect, size);
    final cardWidth = math.min(size.width - 32, 336.0);
    final cardLeft = _cardLeft(size.width, cardWidth, spotlightRect);
    final pointerLeft = _pointerLeft(cardLeft, cardWidth, spotlightRect);
    final cardTop = _cardTop(
      media.padding.top,
      media.padding.bottom,
      size.height,
      spotlightRect,
      showCardBelow,
    );

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: CustomPaint(
                painter: _SpotlightScrimPainter(
                  color: Colors.black.withValues(alpha: isDark ? 0.78 : 0.68),
                  spotlightRect: spotlightRect,
                ),
              ),
            ),
          ),
          if (spotlightRect != null)
            Positioned.fromRect(
              rect: spotlightRect,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    border:
                        Border.all(color: const Color(0xFF67E38A), width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF67E38A).withValues(alpha: 0.22),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            top: cardTop,
            left: cardLeft,
            width: cardWidth,
            child: _TutorialPopover(
              icon: step.icon,
              title: step.title,
              description: step.description,
              currentStepIndex: currentStepIndex,
              totalSteps: steps.length,
              pointerLeft: pointerLeft,
              pointerOnTop: showCardBelow,
              isDark: isDark,
              onBack: onBack,
              onNext: onNext,
              onSkip: onSkip,
            ),
          ),
        ],
      ),
    );
  }

  Rect? _resolveTargetRect(BuildContext context, GlobalKey key) {
    final overlayBox = context.findRenderObject();
    final targetBox = key.currentContext?.findRenderObject();
    if (overlayBox is! RenderBox ||
        targetBox is! RenderBox ||
        !targetBox.hasSize) {
      return null;
    }

    final offset = targetBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    return offset & targetBox.size;
  }

  bool _shouldShowCardBelow(
    TutorialCardPlacement placement,
    Rect? spotlightRect,
    Size size,
  ) {
    switch (placement) {
      case TutorialCardPlacement.above:
        return false;
      case TutorialCardPlacement.below:
        return true;
      case TutorialCardPlacement.automatic:
        return (spotlightRect?.center.dy ?? size.height * 0.5) <
            size.height * 0.45;
    }
  }

  double _cardLeft(double screenWidth, double cardWidth, Rect? spotlightRect) {
    if (spotlightRect == null) return (screenWidth - cardWidth) / 2;
    return (spotlightRect.center.dx - (cardWidth / 2))
        .clamp(16.0, screenWidth - cardWidth - 16.0);
  }

  double _pointerLeft(double cardLeft, double cardWidth, Rect? spotlightRect) {
    if (spotlightRect == null) return cardWidth / 2;
    return (spotlightRect.center.dx - cardLeft).clamp(34.0, cardWidth - 34.0);
  }

  double _cardTop(
    double safeTop,
    double safeBottom,
    double screenHeight,
    Rect? spotlightRect,
    bool showCardBelow,
  ) {
    const estimatedHeight = 248.0;
    const gap = 20.0;
    final minTop = safeTop + 14;
    final maxTop = screenHeight - safeBottom - estimatedHeight - 14;

    if (spotlightRect == null) {
      return (screenHeight * 0.5) - (estimatedHeight / 2);
    }

    final desiredTop = showCardBelow
        ? spotlightRect.bottom + gap
        : spotlightRect.top - estimatedHeight - gap;
    return desiredTop.clamp(minTop, maxTop);
  }
}

class _TutorialPopover extends StatelessWidget {
  const _TutorialPopover({
    required this.icon,
    required this.title,
    required this.description,
    required this.currentStepIndex,
    required this.totalSteps,
    required this.pointerLeft,
    required this.pointerOnTop,
    required this.isDark,
    required this.onNext,
    required this.onSkip,
    this.onBack,
  });

  final IconData icon;
  final String title;
  final String description;
  final int currentStepIndex;
  final int totalSteps;
  final double pointerLeft;
  final bool pointerOnTop;
  final bool isDark;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? const Color(0xFFEEF7F0) : Colors.white;
    const titleColor = Color(0xFF123D26);
    const bodyColor = Color(0xFF3B5E4B);
    final isLast = currentStepIndex == totalSteps - 1;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (pointerOnTop)
          Positioned(
            top: -12,
            left: pointerLeft - 12,
            child: _SpeechPointer(color: cardColor, pointsUp: true),
          ),
        if (!pointerOnTop)
          Positioned(
            bottom: -12,
            left: pointerLeft - 12,
            child: _SpeechPointer(color: cardColor, pointsUp: false),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.18),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F7B52),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFF1F7B52).withValues(alpha: 0.25),
                          blurRadius: 14,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: Colors.white, size: 24),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F6F2),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${currentStepIndex + 1} / $totalSteps',
                      style: GoogleFonts.spaceGrotesk(
                        color: titleColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: titleColor,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                description,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: bodyColor,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: List.generate(
                  totalSteps,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 6),
                    width: currentStepIndex == index ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: currentStepIndex == index
                          ? const Color(0xFF309249)
                          : const Color(0xFFD7E6DA),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  if (onBack != null)
                    TextButton(
                      onPressed: onBack,
                      style: TextButton.styleFrom(
                        foregroundColor: titleColor,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                      ),
                      child: Text(
                        'Back',
                        style: GoogleFonts.spaceGrotesk(
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  TextButton(
                    onPressed: onSkip,
                    style: TextButton.styleFrom(
                      foregroundColor: titleColor.withValues(alpha: 0.7),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                    ),
                    child: Text(
                      'Skip',
                      style:
                          GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: onNext,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F7B52),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Text(
                      isLast ? 'Finish' : 'Next',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SpeechPointer extends StatelessWidget {
  const _SpeechPointer({
    required this.color,
    required this.pointsUp,
  });

  final Color color;
  final bool pointsUp;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(24, 12),
      painter: _SpeechPointerPainter(color: color, pointsUp: pointsUp),
    );
  }
}

class _SpeechPointerPainter extends CustomPainter {
  const _SpeechPointerPainter({
    required this.color,
    required this.pointsUp,
  });

  final Color color;
  final bool pointsUp;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();

    if (pointsUp) {
      path
        ..moveTo(size.width / 2, 0)
        ..lineTo(0, size.height)
        ..lineTo(size.width, size.height)
        ..close();
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close();
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SpeechPointerPainter oldDelegate) {
    return color != oldDelegate.color || pointsUp != oldDelegate.pointsUp;
  }
}

class _SpotlightScrimPainter extends CustomPainter {
  const _SpotlightScrimPainter({
    required this.color,
    required this.spotlightRect,
  });

  final Color color;
  final Rect? spotlightRect;

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPath = Path()..addRect(Offset.zero & size);
    if (spotlightRect != null) {
      final holePath = Path()
        ..addRRect(
          RRect.fromRectAndRadius(spotlightRect!, const Radius.circular(28)),
        );
      final difference =
          Path.combine(PathOperation.difference, overlayPath, holePath);
      canvas.drawPath(difference, Paint()..color = color);
      return;
    }

    canvas.drawPath(overlayPath, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SpotlightScrimPainter oldDelegate) {
    return color != oldDelegate.color ||
        spotlightRect != oldDelegate.spotlightRect;
  }
}
