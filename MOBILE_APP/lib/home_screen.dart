import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'weather_service.dart';
import 'camera_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:metadata_fetch/metadata_fetch.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'core/data/articles_data.dart';
import 'models/reminder_model.dart';
import 'screens/article_reader_screen.dart';
import 'screens/reminders_screen.dart';
import 'services/reminder_service.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onNavigateToRecentScans;

  const HomeScreen({super.key, this.onNavigateToRecentScans});

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

    // Color definitions
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F0);
    final cardColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFFFFFFF);
    final badgeBgColor = isDark ? const Color(0xFF2A3C2A) : const Color(0xFFE8F3E5);
    final gradientEnd = const Color(0xFF309249);
    final iconBgColor = badgeBgColor;

    final dropShadow = BoxShadow(
      color: Colors.black.withOpacity(isDark ? 0.55 : 0.18),
      blurRadius: 28,
      offset: const Offset(0, 14),
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
                    // Notification bell with live unread badge
                    _NotificationBell(
                      isDark: isDark,
                      badgeBgColor: badgeBgColor,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // ── Scanning Section ──────────────────────────────────
              Text(
                "Scanning",
                style: GoogleFonts.spaceGrotesk(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 16),

              // Two side-by-side scanning cards
              Row(
                children: [
                  // Card 1 — Identify
                  Expanded(
                    child: _buildScanningCard(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CameraScreen(scanType: 'identify'),
                        ),
                      ),
                      title: "Identify",
                      subtitle: "Recognize\nany plant",
                      backgroundColor: isDark
                          ? const Color(0xFF1E4D2B)
                          : const Color(0xFF2D6A2E),
                      imagePath: 'assets/images/tomato_plant.png',
                      isDark: isDark,
                      imageHeight: 250,
                      rightOffset: -30,
                      bottomOffset: -40,
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Card 2 — Diagnose
                  Expanded(
                    child: _buildScanningCard(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CameraScreen(scanType: 'diagnose'),
                        ),
                      ),
                      title: "Diagnose",
                      subtitle: "Check your\nplant's health",
                      backgroundColor: isDark
                          ? const Color(0xFF2A2A2A)
                          : const Color(0xFF3A3A3A),
                      imagePath: 'assets/images/tomato_plant2.png',
                      isDark: isDark,
                      imageHeight: 280,
                      rightOffset: -20,
                      bottomOffset: -75,
                    ),
                  ),
                ],
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
                    child: GestureDetector(
                      onTap: widget.onNavigateToRecentScans,
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
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // ── Articles Section ──────────────────────────────────
              Text(
                "Articles for You",
                style: GoogleFonts.spaceGrotesk(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: hardcodedArticles.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  return ArticleCard(article: hardcodedArticles[index], isDark: isDark);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a scanning card matching the reference UI design.
  Widget _buildScanningCard({
    required VoidCallback onTap,
    required String title,
    required String subtitle,
    required Color backgroundColor,
    required String imagePath,
    required bool isDark,
    double rightOffset = -25,
    double bottomOffset = -20,
    double imageHeight = 230,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 220,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: backgroundColor.withOpacity(isDark ? 0.5 : 0.35),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Leaf image positioned at bottom-right, overflowing
            Positioned(
              right: rightOffset,
              bottom: bottomOffset,
              child: Image.asset(
                imagePath,
                height: imageHeight,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.local_florist,
                    size: 80,
                    color: Colors.white.withOpacity(0.15),
                  );
                },
              ),
            ),
            // Text content at top-left
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 14,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
      height: 180,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
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

/// Notification bell with a live unread badge driven by a Firestore stream
/// of the user's reminders. Tapping it opens the [RemindersScreen].
class _NotificationBell extends StatelessWidget {
  final bool isDark;
  final Color badgeBgColor;

  const _NotificationBell({
    required this.isDark,
    required this.badgeBgColor,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final iconColor = isDark ? Colors.white : Colors.black87;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RemindersScreen()),
      ),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: badgeBgColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.notifications_none_rounded, color: iconColor, size: 24),
            if (user != null)
              StreamBuilder<List<ReminderModel>>(
                stream: ReminderService().streamReminders(user.uid),
                builder: (context, snap) {
                  final count = _unreadCountForToday(snap.data ?? const []);
                  if (count == 0) return const SizedBox.shrink();
                  return Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: count > 9 ? 4 : 5,
                        vertical: 1,
                      ),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: badgeBgColor, width: 1.5),
                      ),
                      child: Text(
                        count > 9 ? '9+' : '$count',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.spaceGrotesk(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Count expired-and-uncompleted reminders for today plus reminders that
  /// fire later today and are still pending.
  int _unreadCountForToday(List<ReminderModel> reminders) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    int count = 0;
    for (final r in reminders) {
      if (r.isCompleted) continue;
      // Walk occurrences from startDate forward to find one falling today
      DateTime cursor = DateTime(
        r.startDate.year,
        r.startDate.month,
        r.startDate.day,
        r.notifyTime.hour,
        r.notifyTime.minute,
      );
      var safety = 200;
      while (safety-- > 0 && cursor.isBefore(tomorrow)) {
        if (!cursor.isBefore(today)) {
          count++;
          break;
        }
        final next = r.repeat.nextAfter(cursor);
        if (next == null) break;
        cursor = next;
      }
    }
    return count;
  }
}

class ArticleCard extends StatefulWidget {
  final ArticleModel article;
  final bool isDark;

  const ArticleCard({super.key, required this.article, required this.isDark});

  @override
  State<ArticleCard> createState() => _ArticleCardState();
}

class _ArticleCardState extends State<ArticleCard> {
  String? _fetchedImageUrl;
  bool _isRead = false;

  @override
  void initState() {
    super.initState();
    _fetchMetadata();
    _checkIfRead();
  }

  Future<void> _fetchMetadata() async {
    try {
      final data = await MetadataFetch.extract(widget.article.url);
      if (data?.image != null && mounted) {
        setState(() {
          _fetchedImageUrl = data!.image;
        });
      }
    } catch (_) {
      // Fallback to local image will happen implicitly
    }
  }

  Future<void> _checkIfRead() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final safeId = widget.article.url.replaceAll(RegExp(r'[^\w\s]+'), '_');
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('readArticles')
            .doc(safeId)
            .get();
        if (doc.exists && mounted) {
          setState(() {
            _isRead = true;
          });
        }
      }
    } catch (_) {}
  }

  Color _getAudienceColor(String audience) {
    switch (audience.toLowerCase()) {
      case 'beginner':
        return Colors.green;
      case 'intermediate':
        return Colors.orange;
      case 'expert':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ArticleReaderScreen(article: widget.article),
          ),
        );
        // Refresh read status when coming back
        _checkIfRead();
      },
      child: Container(
        height: 200,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: widget.isDark ? const Color(0xFF1E1E1E) : Colors.grey[200],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Cover Image
            _fetchedImageUrl != null
                ? CachedNetworkImage(
                    imageUrl: _fetchedImageUrl!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: widget.isDark ? Colors.grey[800] : Colors.grey[300],
                    ),
                    errorWidget: (context, url, error) => Image.asset(
                      widget.article.coverImageUrl,
                      fit: BoxFit.cover,
                    ),
                  )
                : Image.asset(
                    widget.article.coverImageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFF1E4D2B),
                    ),
                  ),

            // Gradient Overlay
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black87],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.3, 1.0],
                ),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Top Row: Audience Badge & Read Indicator
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getAudienceColor(widget.article.audience).withOpacity(0.9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          widget.article.audience,
                          style: GoogleFonts.spaceGrotesk(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (_isRead)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle, color: Colors.greenAccent, size: 12),
                              const SizedBox(width: 4),
                              Text(
                                "Read",
                                style: GoogleFonts.spaceGrotesk(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),

                  // Bottom Content: Title & Source
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.article.title,
                        style: GoogleFonts.spaceGrotesk(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.article.source,
                        style: GoogleFonts.spaceGrotesk(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
