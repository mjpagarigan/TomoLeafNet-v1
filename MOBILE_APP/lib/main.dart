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

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'TOMOLeafNet',
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

  final List<Widget> _screens = [
    const HomeScreen(),
    const ChatScreen(),
    const HistoryScreen(),
    const MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final navBgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    const fabColor = Color(0xFF309249); // Darker rich green for FAB like the image

    return Scaffold(
      extendBody: true, // Ensures Scaffold background flows under the transparent notch and rounded corners
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
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const CameraScreen()),
            );
          },
          backgroundColor: fabColor,
          shape: const CircleBorder(),
          elevation: 0, // Shadow strictly handled by parent container's BoxShadow to avoid black artifact
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
        notchMargin: 10.0, // Clean, tight wrap around the FAB
        elevation: 10,
        child: SizedBox(
          height: 65,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(Icons.home, Icons.home_outlined, "Home", 0, theme),
              _buildNavItem(Icons.chat_bubble, Icons.chat_bubble_outline, "Chat", 1, theme),

              // Empty space for the notch without text, hidden on Chat tab
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
