import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_session.dart';
import 'firebase_options.dart';
import 'theme_provider.dart';
import 'home_screen.dart';
import 'chat_screen.dart';
import 'camera_screen.dart';
import 'more_screen.dart';
import 'history_screen.dart';
import 'screens/auth/auth_wrapper.dart';
import 'screens/reminders_screen.dart';
import 'services/fcm_service.dart';
import 'services/community_contribution_service.dart';
import 'services/local_notification_service.dart';
import 'widgets/guided_onboarding_tutorial.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Enable Firestore offline persistence
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider.value(value: AppSession.instance),
      ],
      child: const MyApp(),
    ),
  );

  unawaited(_bootstrapDeferredServices());
}

Future<void> _bootstrapDeferredServices() async {
  await Future<void>.delayed(const Duration(milliseconds: 250));
  try {
    await LocalNotificationService.instance.init();
    LocalNotificationService.instance.onNotificationTap = (payload) {
      final navigator = MyApp.rootNavigatorKey.currentState;
      navigator
          ?.push(MaterialPageRoute(builder: (_) => const RemindersScreen()));
    };
    await LocalNotificationService.instance.requestPermissions();
    await FcmService.instance.init();
    await CommunityContributionService.instance.initialize();
  } catch (e) {
    debugPrint('Deferred startup service failed: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  /// Root navigator key — exposed so background callbacks (e.g. notification
  /// taps fired from the OS) can push routes without a BuildContext.
  static final GlobalKey<NavigatorState> rootNavigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'TOMOLeafNet',
      navigatorKey: rootNavigatorKey,
      theme: ThemeProvider.lightTheme,
      darkTheme: ThemeProvider.darkTheme,
      themeMode: themeProvider.themeMode,
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  bool _isTutorialVisible = false;
  int _tutorialStepIndex = 0;

  final GlobalKey _homeSearchTutorialKey =
      GlobalKey(debugLabel: 'tutorial-home-search');
  final GlobalKey _homeScanActionsTutorialKey =
      GlobalKey(debugLabel: 'tutorial-home-scan-actions');
  final GlobalKey _chatInputTutorialKey =
      GlobalKey(debugLabel: 'tutorial-chat-input');
  final GlobalKey _historyFilterTutorialKey =
      GlobalKey(debugLabel: 'tutorial-history-filter');
  final GlobalKey _chatNavTutorialKey =
      GlobalKey(debugLabel: 'tutorial-chat-nav');
  final GlobalKey _historyNavTutorialKey =
      GlobalKey(debugLabel: 'tutorial-history-nav');
  final GlobalKey _moreNavTutorialKey =
      GlobalKey(debugLabel: 'tutorial-more-nav');
  final GlobalKey _fabTutorialKey = GlobalKey(debugLabel: 'tutorial-fab');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowTutorial();
    });
  }

  List<TutorialStepData> _buildTutorialSteps({required bool isGuest}) {
    if (isGuest) {
      return [
        TutorialStepData(
          targetKey: _chatInputTutorialKey,
          pageIndex: 0,
          icon: Icons.chat_bubble_outline_rounded,
          title: 'Ask Tomo anything',
          description:
              'Use chat to ask about symptoms, leaf damage, treatments, and everyday tomato care in natural language.',
          preferredPlacement: TutorialCardPlacement.above,
        ),
        TutorialStepData(
          targetKey: _moreNavTutorialKey,
          pageIndex: 1,
          icon: Icons.tune_rounded,
          title: 'Open account and app settings',
          description:
              'More gives you access to sign-in options, appearance settings, and a way to replay this walkthrough later.',
          preferredPlacement: TutorialCardPlacement.above,
        ),
        TutorialStepData(
          targetKey: _fabTutorialKey,
          pageIndex: 1,
          icon: Icons.camera_alt_rounded,
          title: 'Scan from anywhere',
          description:
              'The center camera button opens the scanner so you can capture a leaf and jump into Identify or Diagnose.',
          preferredPlacement: TutorialCardPlacement.above,
        ),
      ];
    }

    return [
      TutorialStepData(
        targetKey: _homeSearchTutorialKey,
        pageIndex: 0,
        icon: Icons.search_rounded,
        title: 'Search your recent scans',
        description:
            'Quickly find past results by disease name, scan type, or confidence label right from the home dashboard.',
        preferredPlacement: TutorialCardPlacement.below,
      ),
      TutorialStepData(
        targetKey: _homeScanActionsTutorialKey,
        pageIndex: 0,
        icon: Icons.eco_outlined,
        title: 'Start with Identify or Diagnose',
        description:
            'Identify is your fast disease check, while Diagnose goes deeper with guidance and treatment-focused results.',
        preferredPlacement: TutorialCardPlacement.below,
      ),
      TutorialStepData(
        targetKey: _chatInputTutorialKey,
        pageIndex: 1,
        icon: Icons.chat_bubble_outline_rounded,
        title: 'Talk to Tomo',
        description:
            'Ask questions about symptoms, care routines, and even your recent scan history to get extra help.',
        preferredPlacement: TutorialCardPlacement.above,
      ),
      TutorialStepData(
        targetKey: _historyFilterTutorialKey,
        pageIndex: 2,
        icon: Icons.history_rounded,
        title: 'Track healthy and infected scans',
        description:
            'Your history keeps every saved scan organized, and these filters make it easy to review plant progress over time.',
        preferredPlacement: TutorialCardPlacement.below,
      ),
      TutorialStepData(
        targetKey: _moreNavTutorialKey,
        pageIndex: 3,
        icon: Icons.tune_rounded,
        title: 'Manage settings in More',
        description:
            'Visit More to view your profile, change the theme, replay this tutorial, and manage account actions.',
        preferredPlacement: TutorialCardPlacement.above,
      ),
      TutorialStepData(
        targetKey: _fabTutorialKey,
        pageIndex: 0,
        icon: Icons.camera_alt_rounded,
        title: 'Scan from anywhere',
        description:
            'The floating camera button stays ready across the app. Tap it anytime to choose Identify or Diagnose.',
        preferredPlacement: TutorialCardPlacement.above,
      ),
    ];
  }

  Future<void> _maybeShowTutorial() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final hasSeenTutorial = await OnboardingTutorial.hasSeenForUser(user.uid);
    if (!mounted || hasSeenTutorial) return;

    await _startTutorial(force: true);
  }

  Future<void> _startTutorial({bool force = false}) async {
    if (!mounted || _isTutorialVisible) return;

    final session = AppSession.instance;
    final user = FirebaseAuth.instance.currentUser;
    if (!force && user == null) return;

    final steps = _buildTutorialSteps(isGuest: session.isGuest);
    if (steps.isEmpty) return;

    setState(() {
      _isTutorialVisible = true;
      _tutorialStepIndex = 0;
      _currentIndex = steps.first.pageIndex;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isTutorialVisible) {
        setState(() {});
      }
    });
  }

  void _goToTutorialStep(int index) {
    final steps = _buildTutorialSteps(isGuest: AppSession.instance.isGuest);
    if (steps.isEmpty) return;
    final nextIndex = index.clamp(0, steps.length - 1);
    final nextStep = steps[nextIndex];

    setState(() {
      _tutorialStepIndex = nextIndex;
      _currentIndex = nextStep.pageIndex;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isTutorialVisible) {
        setState(() {});
      }
    });
  }

  Future<void> _closeTutorial({required bool markSeen}) async {
    if (markSeen) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await OnboardingTutorial.markSeenForUser(user.uid);
      }
    }

    if (!mounted) return;
    setState(() => _isTutorialVisible = false);
  }

  /// Show a bottom sheet letting the user choose between Identify and Diagnose.
  void _showScanTypeChooser(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[600] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              "Choose Scan Type",
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                // Identify option
                Expanded(
                  child: _buildScanOption(
                    context: ctx,
                    icon: Icons.search,
                    title: "Identify",
                    subtitle: "Detect disease",
                    color: const Color(0xFF2D6A2E),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const CameraScreen(scanType: 'identify'),
                        ),
                      );
                    },
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 14),
                // Diagnose option
                Expanded(
                  child: _buildScanOption(
                    context: ctx,
                    icon: Icons.healing,
                    title: "Diagnose",
                    subtitle: "Get treatment",
                    color: const Color(0xFF546E7A),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const CameraScreen(scanType: 'diagnose'),
                        ),
                      );
                    },
                    isDark: isDark,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanOption({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.35),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 36),
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white.withOpacity(0.8),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final session = context.watch<AppSession>();
    final isGuest = session.isGuest;
    final tutorialSteps = _buildTutorialSteps(isGuest: isGuest);
    final screens = isGuest
        ? <Widget>[
            ChatScreen(tutorialInputKey: _chatInputTutorialKey),
            const MoreScreen(),
          ]
        : <Widget>[
            HomeScreen(
              tutorialSearchKey: _homeSearchTutorialKey,
              tutorialScanActionsKey: _homeScanActionsTutorialKey,
            ),
            ChatScreen(tutorialInputKey: _chatInputTutorialKey),
            HistoryScreen(tutorialFilterKey: _historyFilterTutorialKey),
            const MoreScreen(),
          ];
    final currentIndex = _currentIndex < screens.length ? _currentIndex : 0;
    if (currentIndex != _currentIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _currentIndex = 0);
        }
      });
    }
    final navBgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    const fabColor = Color(0xFF309249);

    return OnboardingTutorialScope(
      startTutorial: _startTutorial,
      child: Stack(
        children: [
          Scaffold(
            extendBody: true,
            body: screens[currentIndex],
            floatingActionButton: (!isGuest && currentIndex == 1)
                ? null
                : Container(
                    key: _fabTutorialKey,
                    height: 70,
                    width: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: fabColor.withOpacity(isDark ? 0.4 : 0.6),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        )
                      ],
                    ),
                    child: FloatingActionButton(
                      onPressed: () => _showScanTypeChooser(context),
                      backgroundColor: fabColor,
                      shape: const CircleBorder(),
                      elevation: 0,
                      child: const Icon(Icons.camera_alt,
                          size: 32, color: Colors.white),
                    ),
                  ),
            floatingActionButtonLocation:
                FloatingActionButtonLocation.centerDocked,
            bottomNavigationBar: BottomAppBar(
              color: navBgColor,
              shape: const AutomaticNotchedShape(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                CircleBorder(),
              ),
              notchMargin: 10.0,
              elevation: 10,
              child: SizedBox(
                height: 65,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    if (!isGuest)
                      _buildNavItem(
                          Icons.home, Icons.home_outlined, "Home", 0, theme),
                    if (isGuest)
                      _buildNavItem(
                        Icons.chat_bubble,
                        Icons.chat_bubble_outline,
                        "Chat",
                        0,
                        theme,
                        tutorialKey: _chatNavTutorialKey,
                      )
                    else
                      _buildNavItem(
                        Icons.chat_bubble,
                        Icons.chat_bubble_outline,
                        "Chat",
                        1,
                        theme,
                        tutorialKey: _chatNavTutorialKey,
                      ),
                    const SizedBox(width: 48),
                    if (!isGuest)
                      _buildNavItem(
                        Icons.eco,
                        Icons.eco_outlined,
                        "My Plants",
                        2,
                        theme,
                        tutorialKey: _historyNavTutorialKey,
                      ),
                    _buildNavItem(
                      Icons.more_horiz,
                      Icons.more_horiz,
                      "More",
                      isGuest ? 1 : 3,
                      theme,
                      tutorialKey: _moreNavTutorialKey,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isTutorialVisible && tutorialSteps.isNotEmpty)
            OnboardingTutorialOverlay(
              key: ValueKey(
                  'tutorial-step-$_tutorialStepIndex-${tutorialSteps[_tutorialStepIndex].title}'),
              steps: tutorialSteps,
              currentStepIndex: _tutorialStepIndex,
              onBack: _tutorialStepIndex == 0
                  ? null
                  : () => _goToTutorialStep(_tutorialStepIndex - 1),
              onNext: () {
                if (_tutorialStepIndex >= tutorialSteps.length - 1) {
                  _closeTutorial(markSeen: true);
                } else {
                  _goToTutorialStep(_tutorialStepIndex + 1);
                }
              },
              onSkip: () => _closeTutorial(markSeen: true),
            ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    IconData activeIcon,
    IconData inactiveIcon,
    String label,
    int index,
    ThemeData theme, {
    GlobalKey? tutorialKey,
  }) {
    bool isSelected = _currentIndex == index;
    const activeColor = Color(0xFF309249);
    final inactiveColor = theme.colorScheme.onSurface.withOpacity(0.5);

    return SizedBox(
      key: tutorialKey,
      child: InkWell(
        onTap: () => setState(() => _currentIndex = index),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: SizedBox(
          width: 60,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSelected ? activeIcon : inactiveIcon,
                color: isSelected ? activeColor : inactiveColor,
                size: 26,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.spaceGrotesk(
                  color: isSelected ? activeColor : inactiveColor,
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
