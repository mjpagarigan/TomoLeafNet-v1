import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'theme_provider.dart';
import 'weather_service.dart';
import 'camera_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  WeatherData? _weather;
  bool _weatherLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWeather();
  }

  Future<void> _loadWeather() async {
    setState(() => _weatherLoading = true);
    final data = await WeatherService.fetchWeather();
    if (mounted) {
      setState(() {
        _weather = data;
        _weatherLoading = false;
      });
    }
  }

  Future<void> _requestLocation() async {
    setState(() => _weatherLoading = true);
    final result = await WeatherService.requestLocationWithStatus();
    if (!mounted) return;

    switch (result.status) {
      case 'service_disabled':
        setState(() => _weatherLoading = false);
        _showLocationSnackBar('Location services disabled.');
        break;
      case 'denied':
        setState(() => _weatherLoading = false);
        _showLocationSnackBar('Location permission denied.');
        break;
      case 'denied_forever':
        setState(() => _weatherLoading = false);
        _showLocationDialog();
        break;
      case 'granted':
        await _loadWeather();
        break;
      default:
        setState(() => _weatherLoading = false);
        _showLocationSnackBar('Could not retrieve location.');
    }
  }

  void _showLocationSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _showLocationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Location Permission', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600)),
        content: Text('Please enable location access in settings.', style: GoogleFonts.spaceGrotesk()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: GoogleFonts.spaceGrotesk())),
          ElevatedButton(
            onPressed: () { Navigator.pop(ctx); Geolocator.openAppSettings(); },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF13EC13)),
            child: Text('Settings', style: GoogleFonts.spaceGrotesk(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final themeProvider = Provider.of<ThemeProvider>(context);

    // Color definitions from Image
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F0);
    final cardColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFFFFFFF);
    final badgeBgColor = isDark ? const Color(0xFF2A3C2A) : const Color(0xFFE8F3E5); // Very soft green
    final gradientStart = const Color(0xFF5ED866);
    final gradientEnd = const Color(0xFF309249);
    final iconBgColor = badgeBgColor;

    final dropShadow = BoxShadow(
      color: Colors.black.withOpacity(isDark ? 0.55 : 0.18), // Increased from 0.08 in light mode and 0.35 in dark mode
      blurRadius: 28,
      offset: const Offset(0, 14), // Dropped slightly further down to enhance the floating feel
    );

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Header Card (Weather Pill)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [dropShadow],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Weather & Location
                    GestureDetector(
                      onTap: _requestLocation,
                      child: Row(
                        children: [
                          Icon(
                            isDark ? Icons.nightlight_round : Icons.wb_sunny,
                            color: isDark ? Colors.grey[400] : Colors.amber, 
                            size: 32
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _weather?.cityName ?? (_weatherLoading ? "Loading..." : "San Francisco, CA"),
                                style: GoogleFonts.spaceGrotesk(
                                  fontWeight: FontWeight.bold, 
                                  fontSize: 16,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              Text(
                                "Sunny, ${_weather?.tempMax.round() ?? '78'}°F",
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 13, 
                                  color: isDark ? Colors.grey[400] : Colors.grey[800],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Theme Toggle masquerading as Health Badge
                    GestureDetector(
                      onTap: () => themeProvider.toggleTheme(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: badgeBgColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Text("🍅", style: TextStyle(fontSize: 18)),
                            const SizedBox(width: 6),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Tomato Plant",
                                  style: GoogleFonts.spaceGrotesk(
                                    color: isDark ? Colors.white70 : Colors.black87,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    height: 1.1,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      "Health: ",
                                      style: GoogleFonts.spaceGrotesk(
                                        color: isDark ? Colors.white70 : Colors.black87,
                                        fontSize: 10,
                                        height: 1.1,
                                      ),
                                    ),
                                    Text(
                                      "Good",
                                      style: GoogleFonts.spaceGrotesk(
                                        color: gradientEnd,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                        height: 1.1,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Hero Card "Scan Leaf"
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CameraScreen())),
                child: Container(
                  width: double.infinity,
                  height: 240,
                  // Add clipping so the scaled image doesn't overflow outside the rounded corners
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [gradientStart, gradientEnd],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: gradientEnd.withOpacity(isDark ? 0.8 : 0.65), // Intensified green glowing shadow
                        blurRadius: 30, 
                        offset: const Offset(0, 14),
                      )
                    ],
                  ),
                  child: Stack(
                    children: [
                      // 3D Plant Graphic 
                      Positioned(
                        right: -20,
                        bottom: -100, // Aggressively pull down to eliminate bottom gap
                        child: Transform.scale(
                          scale: 1.5, 
                          alignment: Alignment.center, // Center scale so it expands evenly
                          child: Image.asset(
                            'assets/images/tomato_plant.png',
                            height: 350, // Massive height to fill the box length
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.local_florist,
                                size: 150,
                                color: Colors.white24,
                              );
                            },
                          ),
                        ),
                      ),
                      // White camera icon at bottom left
                      Positioned(
                        bottom: 24,
                        left: 24,
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 40),
                      ),
                      // Text content
                      Positioned(
                        top: 40,
                        left: 24,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Scan Leaf",
                              style: GoogleFonts.spaceGrotesk(
                                color: Colors.white,
                                fontSize: 38,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                                shadows: [
                                  Shadow(
                                    offset: const Offset(0, 4),
                                    blurRadius: 12.0,
                                    color: Colors.black.withOpacity(0.6),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Detect diseases instantly.",
                              style: GoogleFonts.spaceGrotesk(
                                color: Colors.white.withOpacity(0.95),
                                fontSize: 16,
                                shadows: [
                                  Shadow(
                                    offset: const Offset(0, 2),
                                    blurRadius: 10.0,
                                    color: Colors.black.withOpacity(0.6),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Secondary Actions Grid
              Row(
                children: [
                  Expanded(
                    child: _buildSecondaryCard(
                      isDark: isDark,
                      cardColor: cardColor,
                      iconBgColor: iconBgColor,
                      iconColor: gradientEnd,
                      icon: Icons.menu_book_rounded,
                      title: "Disease Library",
                      subtitle: "Browse conditions",
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildSecondaryCard(
                      isDark: isDark,
                      cardColor: cardColor,
                      iconBgColor: iconBgColor,
                      iconColor: gradientEnd,
                      icon: Icons.access_time_rounded,
                      title: "Recent Scans",
                      subtitle: "View history",
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryCard({
    required bool isDark,
    required Color cardColor,
    required Color iconBgColor,
    required Color iconColor,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      // Set fixed height to ensure cards are square-ish
      height: 180,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          // Apply the same darkened shadow logic as the top header
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.55 : 0.18), 
            blurRadius: 28, 
            offset: const Offset(0, 14)
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.spaceGrotesk(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.spaceGrotesk(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
