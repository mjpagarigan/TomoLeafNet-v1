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
import 'screens/video_article_screen.dart';
import 'services/firestore_service.dart';
import 'services/reminder_service.dart';
import 'identify_result_screen.dart';
import 'diagnose_result_screen.dart';
import 'widgets/tomo_ui.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.tutorialSearchKey,
    this.tutorialScanActionsKey,
  });

  final GlobalKey? tutorialSearchKey;
  final GlobalKey? tutorialScanActionsKey;

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
        title: Text('Location Permission',
            style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
        content: Text('Please enable location access in settings.',
            style: GoogleFonts.dmSans()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: GoogleFonts.dmSans())),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openAppSettings();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3CB45A)),
            child: Text('Settings',
                style: GoogleFonts.dmSans(color: Colors.white)),
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
      final scans = await _firestoreService.getRecentScans(user.uid, limit: 50);
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

    // Color definitions — aligned with TomoLeafNet design tokens.
    final bgColor = isDark ? TomoPalette.bg : const Color(0xFFF4F7F3);
    final badgeBgColor =
        isDark ? const Color(0xFF1F3025) : const Color(0xFFE8F3E5);

    return Scaffold(
      backgroundColor: bgColor,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: TomoBackdrop(
          isDark: isDark,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Greeting header ──────────────────────────────────
                  _buildGreetingHeader(isDark, badgeBgColor),
                  const SizedBox(height: 18),

                  // ── Search Bar ────────────────────────────────────────
                  TomoGlassCard(
                    key: widget.tutorialSearchKey,
                    isDark: isDark,
                    radius: 22,
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: _onSearchChanged,
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search your scan history...',
                        prefixIcon: Icon(
                          Icons.search,
                          color: isDark
                              ? TomoPalette.textMuted
                              : TomoPalette.lightTextSubtle,
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  Icons.clear,
                                  color: isDark
                                      ? TomoPalette.textSubtle
                                      : TomoPalette.lightTextSubtle,
                                ),
                                onPressed: _clearSearch,
                              )
                            : null,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Conditional: normal home or search results ────────
                  if (!_isSearchActive) ...[
                    // ── Weather pill ──────────────────────────────────
                    _buildWeatherPillRedesign(isDark),
                    const SizedBox(height: 24),

                    // ── Scanning Section ──────────────────────────────────
                    TomoSectionLabel("SCAN YOUR PLANT", isDark: isDark),
                    const SizedBox(height: 14),

                    Row(
                      key: widget.tutorialScanActionsKey,
                      children: [
                        Expanded(
                          child: _buildScanCardHtml(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const CameraScreen(scanType: 'identify'),
                              ),
                            ),
                            label: "IDENTIFY",
                            title: "Recognize\nany leaf",
                            accent: const Color(0xFF3CB45A),
                            gradientStart: isDark
                                ? const Color(0xFF1C3522)
                                : const Color(0xFF2D6A2E),
                            gradientEnd: isDark
                                ? const Color(0xFF0F1A13)
                                : const Color(0xFF1E4D2B),
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildScanCardHtml(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const CameraScreen(scanType: 'diagnose'),
                              ),
                            ),
                            label: "DIAGNOSE",
                            title: "Check\nplant health",
                            accent: const Color(0xFFD29B3C),
                            gradientStart: isDark
                                ? const Color(0xFF3A2A18)
                                : const Color(0xFF6B4A1F),
                            gradientEnd: isDark
                                ? const Color(0xFF0F1A13)
                                : const Color(0xFF2E1F0E),
                            isDark: isDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // ── Quick stats grid ──────────────────────────────
                    _buildStatsGridRedesign(isDark),
                    const SizedBox(height: 28),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TomoSectionLabel("ARTICLES FOR YOU", isDark: isDark),
                        Text(
                          "See all",
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: TomoPalette.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: hardcodedArticles.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        return ArticleCard(
                            article: hardcodedArticles[index], isDark: isDark);
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
      ),
    );
  }

  // ── Search result widgets ───────────────────────────────────────────

  Widget _buildSearchHeader(bool isDark) {
    final query = _searchController.text;
    if (query.isEmpty) {
      return Text(
        'Recent Scans',
        style: GoogleFonts.dmSans(
          fontWeight: FontWeight.bold,
          fontSize: 20,
          color: isDark ? Colors.white : Colors.black87,
        ),
      );
    }
    return Text(
      '${_filteredScans.length} result${_filteredScans.length == 1 ? '' : 's'} for \u201c$query\u201d',
      style: GoogleFonts.dmSans(
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
          child: CircularProgressIndicator(color: Color(0xFF3CB45A)),
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
            "Try searching for a disease name like \u2018Early Blight\u2019 or \u2018Leaf Mold\u2019",
        isDark: isDark,
      );
    }

    final diseaseNumbers = _computeSearchDiseaseNumbers(_filteredScans);

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _filteredScans.length,
      itemBuilder: (_, index) => _buildScanSearchCard(
          _filteredScans[index], isDark,
          diseaseNumber: diseaseNumbers[index]),
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

  Widget _buildScanSearchCard(ScanModel scan, bool isDark,
      {int? diseaseNumber}) {
    final baseName = _getSearchDisplayName(scan.predictedDisease);
    final displayName =
        diseaseNumber != null ? '$baseName #$diseaseNumber' : baseName;
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
          color: isDark ? const Color(0xFF131B17) : Colors.white,
          borderRadius: BorderRadius.circular(18),
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
                child: scan.previewImageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: scan.previewImageUrl!,
                        memCacheWidth: 112,
                        memCacheHeight: 112,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: isDark ? Colors.grey[800] : Colors.grey[200],
                          child: const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFF3CB45A)),
                            ),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: isDark ? Colors.grey[800] : Colors.grey[200],
                          child: Icon(Icons.eco,
                              color: Colors.grey[400], size: 24),
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
                          style: GoogleFonts.dmSans(
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
                        isHealthy ? Icons.check_circle : Icons.warning_rounded,
                        color: isHealthy
                            ? const Color(0xFF3CB45A)
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
                          style: GoogleFonts.dmSans(
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
                          style: GoogleFonts.dmSans(
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
                    color: _getSearchBadgeColor(scan.confidenceScore, isDark),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    scan.confidenceLabel.isNotEmpty
                        ? scan.confidenceLabel
                        : '${(scan.confidenceScore * 100).toInt()}%',
                    style: GoogleFonts.dmSans(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: _getSearchTextColor(scan.confidenceScore),
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
                    : const Color(0xFF3CB45A).withAlpha(80)),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
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
                style: GoogleFonts.dmSans(
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
      'Early_Blight': 'Early Blight',
      'Healthy': 'Healthy',
      'Leaf_Miner': 'Leaf Miner',
      'Leaf_Mold': 'Leaf Mold',
      'Not_Tomato': 'Not a Tomato Leaf',
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
    if (confidence >= 0.80) return const Color(0xFF3CB45A);
    if (confidence >= 0.60) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  /// HTML-matching greeting header with leaf avatar, greeting + name, and bell.
  Widget _buildGreetingHeader(bool isDark, Color badgeBgColor) {
    final user = FirebaseAuth.instance.currentUser;
    final raw = user?.displayName?.trim();
    final emailPrefix = user?.email?.split('@').first ?? '';
    final name = (raw != null && raw.isNotEmpty)
        ? raw.split(' ').first
        : (emailPrefix.isNotEmpty ? emailPrefix : 'there');
    final greeting = _greetingForNow();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [TomoPalette.primaryBright, TomoPalette.primaryDeep],
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.14),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: TomoPalette.primary.withOpacity(0.24),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Text('🌿', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: isDark
                        ? TomoPalette.textMuted
                        : TomoPalette.lightTextSubtle,
                  ),
                ),
                Text(
                  name,
                  style: GoogleFonts.dmSans(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    color: isDark ? TomoPalette.text : TomoPalette.lightText,
                  ),
                ),
              ],
            ),
          ],
        ),
        _NotificationBell(isDark: isDark, badgeBgColor: badgeBgColor),
      ],
    );
  }

  String _greetingForNow() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  /// Compact weather pill placed below the search bar (HTML design).
  // ignore: unused_element
  Widget _buildWeatherPill(bool isDark) {
    final temp = _weather?.tempMax.round();
    final tempLabel = temp != null ? '$temp°F' : '78°F';
    final condition =
        _weather?.cityName ?? (_weatherLoading ? 'Loading' : 'Sunny');

    return GestureDetector(
      onTap: _requestLocation,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131B17) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? const Color(0x12FFFFFF)
                : Colors.black.withOpacity(0.05),
          ),
        ),
        child: Row(
          children: [
            const Text('☀️', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$condition, $tempLabel — Good scanning conditions',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Low humidity · Bright light',
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      color:
                          isDark ? const Color(0xFF6B7A72) : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF3CB45A).withOpacity(0.18),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Now',
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF3CB45A),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildSectionLabel(String label, bool isDark) {
    return TomoSectionLabel(label, isDark: isDark);
  }

  Widget _buildWeatherPillRedesign(bool isDark) {
    final temp = _weather?.tempMax.round();
    final tempLabel = temp != null ? '$temp°F' : '78°F';
    final condition =
        _weather?.cityName ?? (_weatherLoading ? 'Loading' : 'Sunny');

    return GestureDetector(
      onTap: _requestLocation,
      child: TomoGlassCard(
        isDark: isDark,
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Text('☀️', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$condition, $tempLabel - Good scanning conditions',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? TomoPalette.text : TomoPalette.lightText,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Low humidity · Bright light',
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      color: isDark
                          ? TomoPalette.textMuted
                          : TomoPalette.lightTextSubtle,
                    ),
                  ),
                ],
              ),
            ),
            const TomoChip(
              label: 'Now',
              color: TomoPalette.primary,
              small: true,
            ),
          ],
        ),
      ),
    );
  }

  /// 3-column stat grid (Scans / Healthy / Infected) from cached scans.
  // ignore: unused_element
  Widget _buildStatsGrid(bool isDark) {
    final scans = _cachedScans ?? const [];
    final total = scans.length;
    final healthy = scans.where((s) => s.predictedDisease == 'Healthy').length;
    final infected = total - healthy;

    final items = <List<String>>[
      ['$total', 'Scans'],
      ['$healthy', 'Healthy'],
      ['$infected', 'Infected'],
    ];

    return Row(
      children: List.generate(items.length, (i) {
        final pair = items[i];
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == items.length - 1 ? 0 : 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF131B17) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark
                      ? const Color(0x12FFFFFF)
                      : Colors.black.withOpacity(0.05),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    pair[0],
                    style: GoogleFonts.dmSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    pair[1],
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      color:
                          isDark ? const Color(0xFF6B7A72) : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStatsGridRedesign(bool isDark) {
    final scans = _cachedScans ?? const [];
    final total = scans.length;
    final healthy = scans.where((s) => s.predictedDisease == 'Healthy').length;
    final infected = total - healthy;

    final items = <List<String>>[
      ['$total', 'Scans'],
      ['$healthy', 'Healthy'],
      ['$infected', 'Infected'],
    ];

    return Row(
      children: List.generate(items.length, (i) {
        final pair = items[i];
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == items.length - 1 ? 0 : 10),
            child: TomoGlassCard(
              isDark: isDark,
              radius: 18,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Column(
                children: [
                  Text(
                    pair[0],
                    style: GoogleFonts.dmSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: isDark ? TomoPalette.text : TomoPalette.lightText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    pair[1],
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      color: isDark
                          ? TomoPalette.textMuted
                          : TomoPalette.lightTextSubtle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  /// HTML-matching scan card: gradient bg, colored border, uppercase label,
  /// big title, and a small circular arrow button.
  Widget _buildScanCardHtml({
    required VoidCallback onTap,
    required String label,
    required String title,
    required Color accent,
    required Color gradientStart,
    required Color gradientEnd,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: const Alignment(-0.6, -1),
            end: const Alignment(0.8, 1),
            colors: [gradientStart, gradientEnd],
          ),
          border: Border.all(color: accent.withOpacity(0.25), width: 1),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withOpacity(0.08),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: GoogleFonts.dmSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent,
                    boxShadow: [
                      BoxShadow(
                        color: accent.withOpacity(0.45),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.arrow_forward,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a scanning card matching the reference UI design.
  // ignore: unused_element
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
                    style: GoogleFonts.dmSans(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: GoogleFonts.dmSans(
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
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: badgeBgColor, width: 1.5),
                      ),
                      child: Text(
                        count > 9 ? '9+' : '$count',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmSans(
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
    if (!widget.article.isVideo) {
      _fetchMetadata();
    }
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
            builder: (_) => widget.article.isVideo
                ? VideoArticleScreen(article: widget.article)
                : ArticleReaderScreen(article: widget.article),
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
          color: widget.isDark ? const Color(0xFF131B17) : Colors.grey[200],
          border:
              widget.isDark ? Border.all(color: const Color(0x12FFFFFF)) : null,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Cover Image
            _fetchedImageUrl != null
                ? CachedNetworkImage(
                    imageUrl: _fetchedImageUrl!,
                    memCacheWidth: 720,
                    memCacheHeight: 400,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color:
                          widget.isDark ? Colors.grey[800] : Colors.grey[300],
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

            // Video play icon badge
            if (widget.article.isVideo)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white70, width: 2),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 36,
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getAudienceColor(widget.article.audience)
                              .withOpacity(0.9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          widget.article.audience,
                          style: GoogleFonts.dmSans(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (_isRead)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle,
                                  color: Colors.greenAccent, size: 12),
                              const SizedBox(width: 4),
                              Text(
                                "Read",
                                style: GoogleFonts.dmSans(
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
                        style: GoogleFonts.dmSans(
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
                        style: GoogleFonts.dmSans(
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
