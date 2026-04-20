import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'models/scan_model.dart';
import 'identify_result_screen.dart';
import 'diagnose_result_screen.dart';
import 'services/firestore_service.dart';
import 'services/storage_service.dart';
import 'widgets/tomo_ui.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.tutorialFilterKey});

  final GlobalKey? tutorialFilterKey;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _showHealthy = true;
  final _firestoreService = FirestoreService();
  final _storageService = StorageService();
  final ScrollController _scrollController = ScrollController();
  List<ScanModel> _allScans = [];
  bool _isLoadingHistory = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastScanDocument;

  // Multi-select state (Improvement 5)
  bool _isSelectMode = false;
  final Set<String> _selectedScanIds = {};
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitialHistory();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _enterSelectMode() {
    setState(() {
      _isSelectMode = true;
      _selectedScanIds.clear();
    });
  }

  void _exitSelectMode() {
    setState(() {
      _isSelectMode = false;
      _selectedScanIds.clear();
    });
  }

  void _toggleSelection(String scanId) {
    setState(() {
      if (_selectedScanIds.contains(scanId)) {
        _selectedScanIds.remove(scanId);
      } else {
        _selectedScanIds.add(scanId);
      }
    });
  }

  void _selectAll(List<ScanModel> scans) {
    setState(() {
      _selectedScanIds.addAll(scans.map((s) => s.scanId));
    });
  }

  Future<void> _deleteSelected(String userId) async {
    if (_selectedScanIds.isEmpty) return;

    final count = _selectedScanIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $count scan${count > 1 ? 's' : ''}?',
            style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
        content:
            Text('This action cannot be undone.', style: GoogleFonts.dmSans()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.dmSans()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete',
                style: GoogleFonts.dmSans(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isDeleting = true);

    try {
      for (final scanId in _selectedScanIds) {
        await _storageService.deleteScanImage(uid: userId, scanId: scanId);
        await _firestoreService.deleteScan(userId, scanId);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Some scans could not be deleted.',
                  style: GoogleFonts.dmSans())),
        );
      }
    }

    if (mounted) {
      setState(() {
        _isDeleting = false;
        _isSelectMode = false;
        _selectedScanIds.clear();
      });
      await _loadInitialHistory();
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoadingMore || !_hasMore) return;
    final threshold = _scrollController.position.maxScrollExtent - 300;
    if (_scrollController.position.pixels >= threshold) {
      _loadMoreHistory();
    }
  }

  Future<void> _loadInitialHistory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _allScans = [];
          _isLoadingHistory = false;
          _isLoadingMore = false;
          _hasMore = false;
          _lastScanDocument = null;
        });
      }
      return;
    }

    setState(() {
      _isLoadingHistory = true;
      _isLoadingMore = false;
      _hasMore = true;
      _lastScanDocument = null;
    });

    try {
      final page =
          await _firestoreService.getUserScansPage(user.uid, limit: 15);
      if (!mounted) return;
      setState(() {
        _allScans = page.scans;
        _lastScanDocument = page.lastDocument;
        _hasMore = page.hasMore;
        _isLoadingHistory = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _loadMoreHistory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);
    try {
      final page = await _firestoreService.getUserScansPage(
        user.uid,
        limit: 15,
        startAfterDocument: _lastScanDocument,
      );
      if (!mounted) return;
      setState(() {
        _allScans = [..._allScans, ...page.scans];
        _lastScanDocument = page.lastDocument;
        _hasMore = page.hasMore;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  void _showCardMenu(ScanModel scan, String userId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131B17) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[600] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.visibility, color: Color(0xFF3CB45A)),
              title: Text('View Result',
                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(ctx);
                _openScanResult(scan);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: Text('Delete This Scan',
                  style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w500, color: Colors.redAccent)),
              onTap: () async {
                Navigator.pop(ctx);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx2) => AlertDialog(
                    title: Text('Delete Scan',
                        style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
                    content: Text('Remove this scan from your history?',
                        style: GoogleFonts.dmSans()),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx2, false),
                        child: Text('Cancel', style: GoogleFonts.dmSans()),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx2, true),
                        child: Text('Delete',
                            style: GoogleFonts.dmSans(color: Colors.redAccent)),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  try {
                    await _storageService.deleteScanImage(
                        uid: userId, scanId: scan.scanId);
                    await _firestoreService.deleteScan(userId, scan.scanId);
                    if (mounted) {
                      await _loadInitialHistory();
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text('Failed to delete scan.',
                                style: GoogleFonts.dmSans())),
                      );
                    }
                  }
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.close,
                  color: isDark ? Colors.grey[400] : Colors.grey[600]),
              title: Text('Cancel',
                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w500)),
              onTap: () => Navigator.pop(ctx),
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
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: isDark ? TomoPalette.bg : const Color(0xFFF5F5F0),
      body: TomoBackdrop(
        isDark: isDark,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                // Header with Select/Cancel button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_isSelectMode)
                      Text(
                        "${_selectedScanIds.length} selected",
                        style: GoogleFonts.dmSans(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color:
                              isDark ? TomoPalette.text : TomoPalette.lightText,
                        ),
                      )
                    else
                      Text(
                        "My Plant History",
                        style: GoogleFonts.dmSans(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color:
                              isDark ? TomoPalette.text : TomoPalette.lightText,
                        ),
                      ),
                    Row(
                      children: [
                        if (_isSelectMode) ...[
                          if (_isDeleting)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.redAccent,
                              ),
                            )
                          else
                            IconButton(
                              icon: const Icon(Icons.delete,
                                  color: Colors.redAccent, size: 26),
                              onPressed: user == null
                                  ? null
                                  : () => _deleteSelected(user.uid),
                            ),
                          TextButton(
                            onPressed: _exitSelectMode,
                            child: Text('Cancel',
                                style: GoogleFonts.dmSans(
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF3CB45A))),
                          ),
                        ] else
                          TextButton(
                            onPressed: _enterSelectMode,
                            child: Text('Select',
                                style: GoogleFonts.dmSans(
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF3CB45A))),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Toggle Switch
                TomoGlassCard(
                  key: widget.tutorialFilterKey,
                  isDark: isDark,
                  radius: 18,
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      _buildToggle("Healthy", true, isDark),
                      _buildToggle("Infected", false, isDark),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // History List
                Expanded(
                  child: user == null
                      ? Center(
                          child: Text(
                            'Sign in to view your scan history.',
                            style: GoogleFonts.dmSans(color: Colors.grey),
                          ),
                        )
                      : _buildHistoryContent(user.uid, isDark),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToggle(String label, bool isHealthyToggle, bool isDark) {
    final isActive = _showHealthy == isHealthyToggle;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _showHealthy = isHealthyToggle);
          if (_isSelectMode) _selectedScanIds.clear();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive
                ? (isDark
                    ? TomoPalette.surfaceRaised
                    : TomoPalette.lightSurface)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ]
                : [],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontWeight: FontWeight.bold,
              color: isActive
                  ? (isDark ? TomoPalette.text : TomoPalette.lightText)
                  : (isDark
                      ? TomoPalette.textMuted
                      : TomoPalette.lightTextSubtle),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryContent(String userId, bool isDark) {
    if (_isLoadingHistory) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF3CB45A)),
      );
    }

    final filteredScans = _allScans.where((scan) {
      if (_showHealthy) {
        return scan.predictedDisease == 'Healthy';
      }
      return scan.predictedDisease != 'Healthy';
    }).toList();

    if (filteredScans.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _showHealthy ? Icons.eco : Icons.search_off,
              size: 60,
              color: const Color(0xFF3CB45A).withAlpha(80),
            ),
            const SizedBox(height: 16),
            Text(
              _showHealthy ? 'No healthy scans yet' : 'No infected scans yet',
              style: GoogleFonts.dmSans(
                fontSize: 16,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Scan a leaf to start tracking!',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: isDark ? Colors.grey[500] : Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    final diseaseNumbers = _computeDiseaseNumbers(filteredScans);

    return Column(
      children: [
        if (_isSelectMode)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _selectAll(filteredScans),
                child: Text(
                  'Select All',
                  style: GoogleFonts.dmSans(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: const Color(0xFF3CB45A),
                  ),
                ),
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadInitialHistory,
            child: ListView.builder(
              controller: _scrollController,
              cacheExtent: 500,
              itemCount: filteredScans.length + (_isLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= filteredScans.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF3CB45A),
                      ),
                    ),
                  );
                }
                return _buildScanCard(
                  scan: filteredScans[index],
                  isDark: isDark,
                  userId: userId,
                  diseaseNumber: diseaseNumbers[index],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  List<int?> _computeDiseaseNumbers(List<ScanModel> scans) {
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

  Widget _buildScanCard({
    required ScanModel scan,
    required bool isDark,
    required String userId,
    int? diseaseNumber,
  }) {
    final isHealthy = scan.predictedDisease == 'Healthy';
    final baseName = _getDisplayName(scan.predictedDisease);
    final displayName =
        diseaseNumber != null ? '$baseName #$diseaseNumber' : baseName;
    final dateStr = DateFormat('MMM d, yyyy h:mm a').format(scan.timestamp);
    final isIdentify = scan.scanType == 'identify';
    final isDiagnose = scan.scanType == 'diagnose';
    final isSelected = _selectedScanIds.contains(scan.scanId);

    return GestureDetector(
      onTap: () {
        if (_isSelectMode) {
          _toggleSelection(scan.scanId);
        } else {
          _openScanResult(scan);
        }
      },
      onLongPress: () {
        if (!_isSelectMode) {
          _enterSelectMode();
          _toggleSelection(scan.scanId);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131B17) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF3CB45A)
                : (isDark ? const Color(0x12FFFFFF) : Colors.transparent),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.25 : 0.05),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                // Checkbox in select mode
                if (_isSelectMode) ...[
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? const Color(0xFF3CB45A)
                          : Colors.transparent,
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF3CB45A)
                            : (isDark ? Colors.grey[600]! : Colors.grey[400]!),
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : null,
                  ),
                  const SizedBox(width: 10),
                ],
                // Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 60,
                    height: 60,
                    child: scan.previewImageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: scan.previewImageUrl!,
                            memCacheWidth: 120,
                            memCacheHeight: 120,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color:
                                  isDark ? Colors.grey[800] : Colors.grey[200],
                              child: const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Color(0xFF3CB45A)),
                                ),
                              ),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color:
                                  isDark ? Colors.grey[800] : Colors.grey[200],
                              child: Icon(Icons.eco, color: Colors.grey[400]),
                            ),
                          )
                        : Container(
                            color: isDark ? Colors.grey[800] : Colors.grey[200],
                            child: Icon(Icons.eco, color: Colors.grey[400]),
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              displayName,
                              style: GoogleFonts.dmSans(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.fade,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            isHealthy
                                ? Icons.check_circle
                                : Icons.warning_rounded,
                            color: isHealthy
                                ? const Color(0xFF3CB45A)
                                : Colors.redAccent,
                            size: 16,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateStr,
                        style: GoogleFonts.dmSans(
                          color: Colors.grey[500],
                          fontSize: 12,
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
                // 3-dot menu (Improvement 5)
                if (!_isSelectMode)
                  IconButton(
                    icon: Icon(Icons.more_vert,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        size: 20),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => _showCardMenu(scan, userId),
                  ),
              ],
            ),
            // Scan type badges + View Result
            const SizedBox(height: 10),
            Row(
              children: [
                _buildScanTypeBadge(
                  label: isIdentify
                      ? "Identify"
                      : (isDiagnose ? "Diagnose" : "Scan"),
                  color: isIdentify
                      ? const Color(0xFF2D6A2E)
                      : (isDiagnose ? const Color(0xFF455A64) : Colors.grey),
                  icon: isDiagnose ? Icons.healing : null,
                  isDark: isDark,
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color:
                        _getConfidenceBadgeColor(scan.confidenceScore, isDark),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    scan.confidenceLabel.isNotEmpty
                        ? scan.confidenceLabel
                        : '${(scan.confidenceScore * 100).toInt()}%',
                    style: GoogleFonts.dmSans(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _getConfidenceTextColor(scan.confidenceScore),
                    ),
                  ),
                ),
                const Spacer(),
                if (isDiagnose)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 14,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "Guide",
                          style: GoogleFonts.dmSans(
                            fontSize: 11,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!_isSelectMode)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "View Result",
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF3CB45A),
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: Color(0xFF3CB45A),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openScanResult(ScanModel scan) {
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

  Widget _buildScanTypeBadge({
    required String label,
    required Color color,
    IconData? icon,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.3 : 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? color.withOpacity(0.9) : color,
            ),
          ),
        ],
      ),
    );
  }

  String _getDisplayName(String label) {
    const names = {
      'Early_Blight': 'Early Blight',
      'Healthy': 'Healthy',
      'Leaf_Miner': 'Leaf Miner',
      'Leaf_Mold': 'Leaf Mold',
      'Not_Tomato': 'Not a Tomato Leaf',
    };
    return names[label] ?? label.replaceAll('_', ' ');
  }

  Color _getConfidenceBadgeColor(double confidence, bool isDark) {
    if (confidence >= 0.80) {
      return isDark ? const Color(0xFF1B3A1B) : const Color(0xFFE8F3E5);
    }
    if (confidence >= 0.60) {
      return isDark ? const Color(0xFF3A3020) : const Color(0xFFFFF3E0);
    }
    return isDark ? const Color(0xFF3A2020) : const Color(0xFFFFEBEE);
  }

  Color _getConfidenceTextColor(double confidence) {
    if (confidence >= 0.80) return const Color(0xFF3CB45A);
    if (confidence >= 0.60) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }
}
