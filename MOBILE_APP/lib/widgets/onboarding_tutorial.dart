import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Full-screen onboarding tutorial modal shown on first launch.
///
/// Tracks completion via SharedPreferences key 'hasSeenTutorial'.
class OnboardingTutorial extends StatefulWidget {
  const OnboardingTutorial({super.key});

  /// Show the tutorial as a modal overlay if user hasn't seen it.
  static Future<void> showIfFirstTime(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenTutorial = prefs.getBool('hasSeenTutorial') ?? false;
    if (!hasSeenTutorial && context.mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black87,
        builder: (_) => const OnboardingTutorial(),
      );
    }
  }

  /// Force-show the tutorial (from Settings).
  static Future<void> showTutorial(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => const OnboardingTutorial(),
    );
  }

  @override
  State<OnboardingTutorial> createState() => _OnboardingTutorialState();
}

class _OnboardingTutorialState extends State<OnboardingTutorial> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  static const _slides = [
    _TutorialSlide(
      emoji: '\u{1F3E0}', // 🏠
      title: 'Welcome to TomoLeafNet!',
      body: 'Your personal tomato leaf disease detection assistant.\n'
          'Scan leaves, get diagnoses, and keep your plants healthy.',
    ),
    _TutorialSlide(
      emoji: '\u{1F4F7}', // 📷
      title: 'Scan Your Tomato Leaf',
      body: 'Tap the camera button to scan a leaf. Use Identify for\n'
          'a quick disease check, or Diagnose for full AI-powered\n'
          'treatment advice.',
    ),
    _TutorialSlide(
      emoji: '\u{1F33F}', // 🌿
      title: 'Ask Tomo Anything',
      body: 'Tomo is your AI plant health assistant. Ask about\n'
          'diseases, treatments, or your recent scan results \u2014\n'
          'in English or Filipino.',
    ),
    _TutorialSlide(
      emoji: '\u{1F4CB}', // 📋
      title: 'Track Your Scan History',
      body: 'All your past scans are saved here. Tap any scan to\n'
          'view the full result again or get a diagnosis.',
    ),
    _TutorialSlide(
      emoji: '\u{1F514}', // 🔔
      title: 'Never Forget Plant Care',
      body: 'Set reminders for watering, fertilizing, and cutting.\n'
          'Get notified so your plants stay healthy.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _completeTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenTutorial', true);
    if (mounted) Navigator.pop(context);
  }

  void _nextPage() {
    if (_currentPage < _slides.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeTutorial();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final isLast = _currentPage == _slides.length - 1;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 520),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.6 : 0.2),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 16, 0),
                child: TextButton(
                  onPressed: _completeTutorial,
                  child: Text(
                    'Skip',
                    style: GoogleFonts.spaceGrotesk(
                      color: isDark ? Colors.grey[400] : Colors.grey[500],
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),

            // Slide content
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          slide.emoji,
                          style: const TextStyle(fontSize: 64),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          slide.title,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          slide.body,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 14,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Dot indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _slides.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == i ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: _currentPage == i
                        ? const Color(0xFF309249)
                        : (isDark ? Colors.grey[600] : Colors.grey[300]),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Next / Get Started button
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _nextPage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF309249),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    isLast ? "Get Started \u{1F33F}" : "Next",
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TutorialSlide {
  final String emoji;
  final String title;
  final String body;

  const _TutorialSlide({
    required this.emoji,
    required this.title,
    required this.body,
  });
}
