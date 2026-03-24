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
        _showLocationSnackBar(
          'Location services are disabled. Please enable GPS in your device settings.',
        );
        break;
      case 'denied':
        setState(() => _weatherLoading = false);
        _showLocationSnackBar(
          'Location permission denied. Tap the location button to try again.',
        );
        break;
      case 'denied_forever':
        setState(() => _weatherLoading = false);
        _showLocationDialog();
        break;
      case 'granted':
        // Permission granted — now fetch weather with location
        await _loadWeather();
        break;
      default:
        setState(() => _weatherLoading = false);
        _showLocationSnackBar('Could not retrieve location. Please try again.');
    }
  }

  void _showLocationSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showLocationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Location Permission', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(
          'Location permission is permanently denied. Please open Settings and enable location access for this app.',
          style: GoogleFonts.poppins(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openAppSettings();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text('Open Settings', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  IconData _getWeatherIcon(String condition) {
    switch (condition.toLowerCase()) {
      case 'clear':
        return Icons.wb_sunny;
      case 'clouds':
        return Icons.cloud;
      case 'rain':
      case 'drizzle':
        return Icons.water_drop;
      case 'thunderstorm':
        return Icons.flash_on;
      case 'snow':
        return Icons.ac_unit;
      case 'mist':
      case 'fog':
      case 'haze':
        return Icons.foggy;
      default:
        return Icons.cloud;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final themeProvider = Provider.of<ThemeProvider>(context);

    final subtleText = theme.colorScheme.onSurface.withAlpha(140);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Header: Location + Weather + Theme Toggle ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Location (tappable to request permission + refresh)
                  GestureDetector(
                    onTap: _requestLocation,
                    child: Row(
                      children: [
                        Icon(Icons.location_on, color: Colors.green, size: 20),
                        const SizedBox(width: 4),
                        Text(
                          _weather?.cityName ?? (_weatherLoading ? '...' : 'Set Location'),
                          style: GoogleFonts.poppins(
                            color: theme.colorScheme.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Icon(Icons.arrow_drop_down, color: theme.colorScheme.onSurface),
                      ],
                    ),
                  ),
                  // Weather + Theme toggle
                  Row(
                    children: [
                      if (_weather != null && _weather!.condition != 'unavailable') ...[
                        Text(
                          "${_weather!.tempMin.round()}°C - ${_weather!.tempMax.round()}°C",
                          style: GoogleFonts.poppins(color: subtleText, fontSize: 13),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          _getWeatherIcon(_weather!.condition),
                          color: theme.colorScheme.onSurface.withAlpha(180),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                      ],
                      // Theme toggle button
                      GestureDetector(
                        onTap: () => themeProvider.toggleTheme(context),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF0F0F0),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isDark ? Icons.light_mode : Icons.dark_mode,
                            size: 18,
                            color: isDark ? Colors.amber : Colors.blueGrey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // --- Search Bar ---
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.green, width: 1.5),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.search, color: subtleText),
                    const SizedBox(width: 10),
                    Text(
                      "Search plants",
                      style: GoogleFonts.poppins(color: subtleText),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // --- Scanning Section: Identify & Diagnose Cards ---
              Row(
                children: [
                  // Identify Card
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const CameraScreen()),
                        );
                      },
                      child: _buildFeatureCard(
                        title: 'Identify',
                        subtitle: 'Recognize any plant',
                        backgroundColor: const Color(0xFF2E7D32),
                        icon: Icons.eco,
                        iconColor: Colors.green[200]!,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Diagnose Card
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const CameraScreen()),
                        );
                      },
                      child: _buildFeatureCard(
                        title: 'Diagnose',
                        subtitle: "Check your plant's health",
                        backgroundColor: isDark ? const Color(0xFF2C2C2C) : const Color(0xFF3A3A3A),
                        icon: Icons.local_hospital,
                        iconColor: Colors.orange[300]!,
                      ),
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

  Widget _buildFeatureCard({
    required String title,
    required String subtitle,
    required Color backgroundColor,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          // Background decorative icon
          Positioned(
            right: -15,
            bottom: -15,
            child: Icon(
              icon,
              size: 110,
              color: Colors.white.withAlpha(20),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 28),
                ),
                const Spacer(),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                    color: Colors.white.withAlpha(180),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}
