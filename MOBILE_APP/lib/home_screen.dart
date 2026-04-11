import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:metadata_fetch/metadata_fetch.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'weather_service.dart';
import 'camera_screen.dart';
import 'core/data/articles_data.dart';
import 'models/reminder_model.dart';
import 'models/scan_model.dart';
import 'screens/article_reader_screen.dart';
import 'screens/reminders_screen.dart';
import 'services/firestore_service.dart';
import 'services/reminder_service.dart';
import 'identify_result_screen.dart';
import 'diagnose_result_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  WeatherData? _weather;
  bool _weatherLoading = true;

  // Search state
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _firestoreService = FirestoreService();
  List<ScanModel>? _cachedScans;
  List<ScanModel> _filteredScans = [];
  bool _scansLoading = false;
  bool _isSearchActive = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadWeather();
    _fetchScanHistory();
    _searchFocusNode.addListener(_onSearchFocusChange);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
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

  // ── Search helpers ──────────────────────────────────────────────────

  void _onSearchFocusChange() {
    setState(() {
      if (_searchFocusNode.hasFocus) {
        _isSearchActive = true;
        if (_searchController.text.isEmpty) {
          _filteredScans = (_cachedScans ?? []).take(5).toList();
        }
      } else {
        _isSearchActive = false;
        _filteredScans = [];
      }
    });
  }

  Future<void> _fetchScanHistory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _scansLoading = true);
    try {
      final scans = await _firestoreService.getRecentScans(user.uid, limit: 200);
      if (mounted) {
        setState(() {
          _cachedScans = scans;
          _scansLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _scansLoading = false);
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    if (query.isEmpty) {
      setState(() {
        _isSearchActive = _searchFocusNode.hasFocus;
        _filteredScans = _searchFocusNode.hasFocus
            ? (_cachedScans ?? []).take(5).toList()
            : [];
      });
      return;
    }
    setState(() => _isSearchActive = true);
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final lq = query.toLowerCase();
      final results = (_cachedScans ?? []).where((s) {
        return s.predictedDisease.toLowerCase().contains(lq) ||
            s.confidenceLabel.toLowerCase().contains(lq) ||
            s.scanType.toLowerCase().contains(lq);
      }).toList();
      setState(() => _filteredScans = results);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _isSearchActive = false;
      _filteredScans = [];
    });
  }

  void _openSearchResult(ScanModel scan) {
    if (scan.scanType == 'diagnose') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DiagnoseResultScreen.history(historyScan: scan),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => IdentifyResultScreen(historyScan: scan),
        ),
      );
    }
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
    final dropShadow = BoxShadow(
      color: Colors.black.withOpacity(isDark ? 0.55 : 0.18),
      blurRadius: 28,
      offset: const Offset(0, 14),
    );

    return Scaffold(
      backgroundColor: bgColor,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
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
              const SizedBox(height: 20),

              // ── Search Bar ────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onChanged: _onSearchChanged,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search your scan history...',
                    hintStyle: GoogleFonts.spaceGrotesk(
                      color: isDark ? Colors.grey[500] : Colors.grey[400],
                      fontSize: 15,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: isDark ? Colors.grey[500] : Colors.grey[400],
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.clear,
                              color: isDark ? Colors.grey[400] : Colors.grey[500],
                            ),
                            onPressed: _clearSearch,
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ── Conditional: normal home or search results ────────
              if (!_isSearchActive) ...[
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

                Row(
                  children: [
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
                const SizedBox(height: 32),

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
              ] else ...[
                // ── Search Results ────────────────────────────────────
                _buildSearchHeader(isDark),
                const SizedBox(height: 16),
                _buildSearchResultsList(isDark),
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }

  // ── Search result widgets ───────────────────────────────────────────

  Widget _buildSearchHeader(bool isDark) {
    final query = _searchController.text;
    if (query.isEmpty) {
      return Text(
        'Recent Scans',
        style: GoogleFonts.spaceGrotesk(
          fontWeight: FontWeight.bold,
          fontSize: 20,
          color: isDark ? Colors.white : Colors.black87,
        ),
      );
    }
    return Text(
      '${_filteredScans.length} result${_filteredScans.length == 1 ? '' : 's'} for \u201c$query\u201d',
      style: GoogleFonts.spaceGrotesk(
        fontWeight: FontWeight.bold,
        fontSize: 20,
        color: isDark ? Colors.white : Colors.black87,
      ),
    );
  }

  Widget _buildSearchResultsList(bool isDark) {
    if (_scansLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFF309249)),
        ),
      );
    }

    if (_cachedScans == null || _cachedScans!.isEmpty) {
      return _buildSearchEmptyState(
        icon: Icons.eco,
        title: 'No scan history yet.',
        subtitle: 'Use Identify or Diagnose to scan your first tomato leaf.',
        isDark: isDark,
      );
    }

    if (_filteredScans.isEmpty && _searchController.text.isNotEmpty) {
      return _buildSearchEmptyState(
        icon: Icons.search_off,
        title: 'No scans found for \u201c${_searchController.text}\u201d',
        subtitle:
            "Try searching for a disease name like \u2018Late Blight\u2019 or \u2018Bacterial Spot\u2019",
        isDark: isDark,
      );
    }

    final diseaseNumbers = _computeSearchDiseaseNumbers(_filteredScans);

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _filteredScans.length,
      itemBuilder: (_, index) =>
          _buildScanSearchCard(_filteredScans[index], isDark, diseaseNumber: diseaseNumbers[index]),
    );
  }

  List<int?> _computeSearchDiseaseNumbers(List<ScanModel> scans) {
    final counts = <String, int>{};
    for (final s in scans) {
      counts[s.predictedDisease] = (counts[s.predictedDisease] ?? 0) + 1;
    }

    final tracker = <String, int>{};
    final result = <int?>[];
    for (final s in scans.reversed) {
      if (counts[s.predictedDisease]! > 1) {
        tracker[s.predictedDisease] = (tracker[s.predictedDisease] ?? 0) + 1;
        result.add(tracker[s.predictedDisease]);
      } else {
        result.add(null);
      }
    }
    return result.reversed.toList();
  }

  Widget _buildScanSearchCard(ScanModel scan, bool isDark, {int? diseaseNumber}) {
    final baseName = _getSearchDisplayName(scan.predictedDisease);
    final displayName = diseaseNumber != null ? '$baseName #$diseaseNumber' : baseName;
    final isHealthy = scan.predictedDisease == 'Healthy';
    final dateStr = DateFormat('MMM d, yyyy  h:mm a').format(scan.timestamp);
    final isIdentify = scan.scanType == 'identify';
    final isDiagnose = scan.scanType == 'diagnose';

    return GestureDetector(
      onTap: () => _openSearchResult(scan),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 56,
                child: scan.imageUrl != null && scan.imageUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: scan.imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: isDark ? Colors.grey[800] : Colors.grey[200],
                          child: const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFF309249)),
                            ),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: isDark ? Colors.grey[800] : Colors.grey[200],
                          child:
                              Icon(Icons.eco, color: Colors.grey[400], size: 24),
                        ),
                      )
                    : Container(
                        color: isDark ? Colors.grey[800] : Colors.grey[200],
                        child:
                            Icon(Icons.eco, color: Colors.grey[400], size: 24),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          style: GoogleFonts.spaceGrotesk(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        isHealthy
                            ? Icons.check_circle
                            : Icons.warning_rounded,
                        color: isHealthy
                            ? const Color(0xFF309249)
                            : Colors.redAccent,
                        size: 14,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (isIdentify
                                  ? const Color(0xFF2D6A2E)
                                  : (isDiagnose
                                      ? const Color(0xFF455A64)
                                      : Colors.grey))
                              .withOpacity(isDark ? 0.3 : 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isIdentify
                              ? 'Identify'
                              : (isDiagnose ? 'Diagnose' : 'Scan'),
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isIdentify
                                ? const Color(0xFF2D6A2E)
                                : (isDiagnose
                                    ? const Color(0xFF455A64)
                                    : Colors.grey),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          dateStr,
                          style: GoogleFonts.spaceGrotesk(
                            color: Colors.grey[500],
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getSearchBadgeColor(
                        scan.confidenceScore, isDark),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    scan.confidenceLabel.isNotEmpty
                        ? scan.confidenceLabel
                        : '${(scan.confidenceScore * 100).toInt()}%',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color:
                          _getSearchTextColor(scan.confidenceScore),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: isDark ? Colors.grey[500] : Colors.grey[400],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 56,
                color: isDark
                    ? Colors.grey[700]
                    : const Color(0xFF309249).withAlpha(80)),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[400] : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 13,
                  color: Colors.grey[500],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getSearchDisplayName(String label) {
    const names = {
      'Bacterial_Spot': 'Bacterial Spot',
      'Early_Blight': 'Early Blight',
      'Healthy': 'Healthy Leaf',
      'Late_Blight': 'Late Blight',
      'Septoria': 'Septoria Leaf Spot',
    };
    return names[label] ?? label.replaceAll('_', ' ');
  }

  Color _getSearchBadgeColor(double confidence, bool isDark) {
    if (confidence >= 0.80) {
      return isDark ? const Color(0xFF1B3A1B) : const Color(0xFFE8F3E5);
    }
    if (confidence >= 0.60) {
      return isDark ? const Color(0xFF3A3020) : const Color(0xFFFFF3E0);
    }
    return isDark ? const Color(0xFF3A2020) : const Color(0xFFFFEBEE);
  }

  Color _getSearchTextColor(double confidence) {
    if (confidence >= 0.80) return const Color(0xFF309249);
    if (confidence >= 0.60) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
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
