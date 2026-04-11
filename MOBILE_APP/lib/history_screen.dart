import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'models/scan_model.dart';
import 'identify_result_screen.dart';
import 'diagnose_result_screen.dart';
import 'services/firestore_service.dart';
import 'services/storage_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _showHealthy = true;
  final _firestoreService = FirestoreService();
  final _storageService = StorageService();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F0),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text(
                "My Plant History",
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 20),
              // Toggle Switch
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.grey[300],
                  borderRadius: BorderRadius.circular(25),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    _buildToggle("Healthy", true, isDark),
                    _buildToggle("Infected", false, isDark),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // History List — real-time from Firestore
              Expanded(
                child: user == null
                    ? Center(
                        child: Text(
                          'Sign in to view your scan history.',
                          style: GoogleFonts.spaceGrotesk(color: Colors.grey),
                        ),
                      )
                    : StreamBuilder<List<ScanModel>>(
                        stream: _firestoreService.getUserScansStream(user.uid),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(color: Color(0xFF309249)),
                            );
                          }

                          final allScans = snapshot.data ?? [];
                          final filteredScans = allScans.where((scan) {
                            if (_showHealthy) {
                              return scan.predictedDisease == 'Healthy';
                            } else {
                              return scan.predictedDisease != 'Healthy';
                            }
                          }).toList();

                          if (filteredScans.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _showHealthy ? Icons.eco : Icons.search_off,
                                    size: 60,
                                    color: const Color(0xFF309249).withAlpha(80),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _showHealthy
                                        ? 'No healthy scans yet'
                                        : 'No infected scans yet',
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 16,
                                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Scan a leaf to start tracking!',
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 13,
                                      color: isDark ? Colors.grey[500] : Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          final diseaseNumbers = _computeDiseaseNumbers(filteredScans);

                          return ListView.builder(
                            itemCount: filteredScans.length,
                            itemBuilder: (context, index) {
                              return _buildScanCard(
                                scan: filteredScans[index],
                                isDark: isDark,
                                userId: user.uid,
                                diseaseNumber: diseaseNumbers[index],
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggle(String label, bool isHealthyToggle, bool isDark) {
    final isActive = _showHealthy == isHealthyToggle;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _showHealthy = isHealthyToggle),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive
                ? (isDark ? const Color(0xFF2C2C2C) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
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
            style: GoogleFonts.spaceGrotesk(
              fontWeight: FontWeight.bold,
              color: isActive
                  ? (isDark ? Colors.white : Colors.black)
                  : (isDark ? Colors.grey[500] : Colors.grey[600]),
            ),
          ),
        ),
      ),
    );
  }

  /// Returns a list parallel to [scans] where each entry is null (no
  /// numbering needed) or the 1-based occurrence index for that disease.
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
    final displayName = diseaseNumber != null ? '$baseName #$diseaseNumber' : baseName;
    final dateStr = DateFormat('MMM d, yyyy  h:mm a').format(scan.timestamp);
    final isIdentify = scan.scanType == 'identify';
    final isDiagnose = scan.scanType == 'diagnose';

    return Dismissible(
      key: Key(scan.scanId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Delete Scan', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600)),
            content: Text('Remove this scan from your history?', style: GoogleFonts.spaceGrotesk()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel', style: GoogleFonts.spaceGrotesk()),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Delete', style: GoogleFonts.spaceGrotesk(color: Colors.redAccent)),
              ),
            ],
          ),
        );
        if (confirmed != true) return false;
        try {
          await _storageService.deleteScanImage(uid: userId, scanId: scan.scanId);
          await _firestoreService.deleteScan(userId, scan.scanId);
          return true;
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to delete scan. Please try again.', style: GoogleFonts.spaceGrotesk())),
            );
          }
          return false;
        }
      },
      onDismissed: (_) {},
      child: GestureDetector(
        onTap: () => _openScanResult(scan),
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Thumbnail from Cloud Storage
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 60,
                      height: 60,
                      child: scan.imageUrl != null && scan.imageUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: scan.imageUrl!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: isDark ? Colors.grey[800] : Colors.grey[200],
                                child: const Center(
                                  child: SizedBox(
                                    width: 20, height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF309249)),
                                  ),
                                ),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: isDark ? Colors.grey[800] : Colors.grey[200],
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
                            Flexible(
                              child: Text(
                                displayName,
                                style: GoogleFonts.spaceGrotesk(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              isHealthy ? Icons.check_circle : Icons.warning_rounded,
                              color: isHealthy ? const Color(0xFF309249) : Colors.redAccent,
                              size: 16,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateStr,
                          style: GoogleFonts.spaceGrotesk(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Confidence badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getConfidenceBadgeColor(scan.confidenceScore, isDark),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      scan.confidenceLabel.isNotEmpty
                          ? scan.confidenceLabel
                          : '${(scan.confidenceScore * 100).toInt()}%',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _getConfidenceTextColor(scan.confidenceScore),
                      ),
                    ),
                  ),
                ],
              ),
              // Scan type badges + View Result
              const SizedBox(height: 10),
              Row(
                children: [
                  // Scan type badge
                  _buildScanTypeBadge(
                    label: isIdentify ? "Identify" : (isDiagnose ? "Diagnose" : "Scan"),
                    color: isIdentify
                        ? const Color(0xFF2D6A2E)
                        : (isDiagnose ? const Color(0xFF455A64) : Colors.grey),
                    icon: isDiagnose ? Icons.healing : null,
                    isDark: isDark,
                  ),
                  const Spacer(),
                  // Show treatment indicator for diagnose scans
                  if (isDiagnose && scan.treatmentSteps != null && scan.treatmentSteps!.isNotEmpty)
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
                            "${scan.treatmentSteps!.length} steps",
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 11,
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  // View Result indicator
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "View Result",
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF309249),
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: Color(0xFF309249),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
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
            style: GoogleFonts.spaceGrotesk(
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
      'Bacterial_Spot': 'Bacterial Spot',
      'Early_Blight': 'Early Blight',
      'Healthy': 'Healthy Leaf',
      'Late_Blight': 'Late Blight',
      'Septoria': 'Septoria Leaf Spot',
    };
    return names[label] ?? label.replaceAll('_', ' ');
  }

  Color _getConfidenceBadgeColor(double confidence, bool isDark) {
    if (confidence >= 0.80) return isDark ? const Color(0xFF1B3A1B) : const Color(0xFFE8F3E5);
    if (confidence >= 0.60) return isDark ? const Color(0xFF3A3020) : const Color(0xFFFFF3E0);
    return isDark ? const Color(0xFF3A2020) : const Color(0xFFFFEBEE);
  }

  Color _getConfidenceTextColor(double confidence) {
    if (confidence >= 0.80) return const Color(0xFF309249);
    if (confidence >= 0.60) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }
}
