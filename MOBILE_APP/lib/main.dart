import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'services/local_notification_service.dart';
import 'widgets/onboarding_tutorial.dart';

List<CameraDescription> cameras = [];

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

  // Local notifications + FCM bootstrap for the reminder system
  await LocalNotificationService.instance.init();
  await LocalNotificationService.instance.requestPermissions();
  LocalNotificationService.instance.onNotificationTap = (payload) {
    final navigator = MyApp.rootNavigatorKey.currentState;
    navigator?.push(MaterialPageRoute(builder: (_) => const RemindersScreen()));
  };
  await FcmService.instance.init();

  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    print('Error: $e.code\nError Message: $e.message');
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
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

  late final List<Widget> _screens = [
    const HomeScreen(),
    const ChatScreen(),
    const HistoryScreen(),
    const MoreScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Show onboarding tutorial on first launch (Improvement 2)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      OnboardingTutorial.showIfFirstTime(context);
    });
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
                          builder: (_) => const CameraScreen(scanType: 'identify'),
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
                          builder: (_) => const CameraScreen(scanType: 'diagnose'),
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
    final navBgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    const fabColor = Color(0xFF309249);

    return Scaffold(
      extendBody: true,
      body: _screens[_currentIndex],
      floatingActionButton: _currentIndex == 1 ? null : Container(
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
          child: const Icon(Icons.camera_alt, size: 32, color: Colors.white),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
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
              _buildNavItem(Icons.home, Icons.home_outlined, "Home", 0, theme),
              _buildNavItem(Icons.chat_bubble, Icons.chat_bubble_outline, "Chat", 1, theme),

              // Empty space for the notch, hidden on Chat tab
              if (_currentIndex != 1) const SizedBox(width: 48),

              _buildNavItem(Icons.eco, Icons.eco_outlined, "My Plants", 2, theme),
              _buildNavItem(Icons.more_horiz, Icons.more_horiz, "More", 3, theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData activeIcon, IconData inactiveIcon, String label, int index, ThemeData theme) {
    bool isSelected = _currentIndex == index;
    const activeColor = Color(0xFF309249);
    final inactiveColor = theme.colorScheme.onSurface.withOpacity(0.5);

    return InkWell(
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
    );
  }
}
