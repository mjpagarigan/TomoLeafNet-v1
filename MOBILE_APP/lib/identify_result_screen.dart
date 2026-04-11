import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'diagnose_result_screen.dart';
import 'models/scan_model.dart';
import 'services/tflite_service.dart';
import 'services/diagnose_service.dart';
import 'services/firestore_service.dart';
import 'services/storage_service.dart';

/// Identify Result Screen — disease detection only, no treatment info.
///
/// Two modes:
///   1. Live scan (imagePath supplied) — runs TFLite inference and saves a
///      new "identify" scan document.
///   2. History view (historyScan supplied) — rehydrates the UI from an
///      existing Firestore scan document and loads the leaf image from
///      Cloud Storage via cached_network_image.
class IdentifyResultScreen extends StatefulWidget {
  final String? imagePath;
  final ScanModel? historyScan;

  const IdentifyResultScreen({
    super.key,
    this.imagePath,
    this.historyScan,
  }) : assert(imagePath != null || historyScan != null,
            'Provide either imagePath (live scan) or historyScan (history)');

  @override
  State<IdentifyResultScreen> createState() => _IdentifyResultScreenState();
}

class _IdentifyResultScreenState extends State<IdentifyResultScreen>
    with SingleTickerProviderStateMixin {
  final _tfliteService = TFLiteService();
  final _diagnoseService = DiagnoseService();
  final _firestoreService = FirestoreService();
  final _storageService = StorageService();

  bool _isLoading = true;
  TFLiteResult? _result;
  String _errorMessage = "";

  // Firebase save state (live scan only)
  bool _isSaving = false;
  bool _isSaved = false;
  String? _savedScanId;

  // Diagnose This Leaf upgrade state
  bool _isDiagnosing = false;
  bool _hasUpgraded = false;
  List<String>? _upgradedTreatmentSteps;
  String _diagnoseError = "";

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  bool get _isHistory => widget.historyScan != null;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    if (_isHistory) {
      _hydrateFromHistory();
    } else {
      _runPrediction();
    }
  }

  @override
  void dispose() {
    _tfliteService.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _hydrateFromHistory() {
    final scan = widget.historyScan!;
    _result = TFLiteResult(
      label: scan.predictedDisease,
      index: 0,
      confidence: scan.confidenceScore,
    );
    _isLoading = false;
    _savedScanId = scan.scanId;
    _isSaved = true;
    _fadeController.forward();
  }

  Future<void> _runPrediction() async {
    try {
      final result = await _tfliteService.predict(widget.imagePath!);
      if (mounted) {
        setState(() {
          _result = result;
          _isLoading = false;
        });
        _fadeController.forward();
        _saveScanToFirebase();
      }
    } catch (e, stackTrace) {
      print("Error running model: $e\n$stackTrace");
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveScanToFirebase() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _result == null) return;

    setState(() => _isSaving = true);

    try {
      GeoPoint? gpsCoordinates;
      try {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always) {
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low,
            timeLimit: const Duration(seconds: 5),
          );
          gpsCoordinates = GeoPoint(position.latitude, position.longitude);
        }
      } catch (_) {}

      final scanId = await _firestoreService.saveScan(
        uid: user.uid,
        predictedDisease: _result!.label,
        confidenceScore: _result!.confidence,
        confidenceLabel: _result!.confidenceLabel,
        scanType: 'identify',
        gpsCoordinates: gpsCoordinates,
      );

      final imageUrl = await _storageService.uploadScanImage(
        uid: user.uid,
        scanId: scanId,
        localImagePath: widget.imagePath!,
      );

      await _firestoreService.updateScanImageUrl(user.uid, scanId, imageUrl);

      if (mounted) {
        setState(() {
          _isSaved = true;
          _savedScanId = scanId;
        });
      }
    } catch (e) {
      print('Error saving scan: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// POST to /diagnose, upgrade the Firestore scan doc, then push the
  /// Diagnose result screen with the treatment steps populated.
  Future<void> _onDiagnoseThisLeaf() async {
    if (_result == null || _isDiagnosing) return;

    // If we already have treatment steps (user re-entered screen via
    // history after upgrading), jump straight to the Diagnose screen.
    if (_hasUpgraded && _upgradedTreatmentSteps != null) {
      _openDiagnoseResult(_upgradedTreatmentSteps!);
      return;
    }

    setState(() {
      _isDiagnosing = true;
      _diagnoseError = "";
    });

    try {
      final steps = await _diagnoseService.getTreatmentSteps(
        disease: _result!.label,
        confidence: double.parse(
            (_result!.confidence * 100).toStringAsFixed(1)),
      );

      // Persist the upgrade
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && _savedScanId != null) {
        try {
          await _firestoreService.upgradeScanToDiagnose(
            uid: user.uid,
            scanId: _savedScanId!,
            treatmentSteps: steps,
          );
        } catch (e) {
          print('Failed to upgrade scan to diagnose: $e');
        }
      }

      if (!mounted) return;
      setState(() {
        _isDiagnosing = false;
        _hasUpgraded = true;
        _upgradedTreatmentSteps = steps;
      });
      _openDiagnoseResult(steps);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDiagnosing = false;
        _diagnoseError =
            "Treatment advice unavailable. Please check your connection and try again.";
      });
    }
  }

  void _openDiagnoseResult(List<String> steps) {
    if (_result == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DiagnoseResultScreen.preloaded(
          label: _result!.label,
          confidence: _result!.confidence,
          treatmentSteps: steps,
          localImagePath: widget.imagePath,
          remoteImageUrl: widget.historyScan?.imageUrl,
          upgradedFromIdentify: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F0);
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Identify Results",
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF309249),
                  ),
                ),
              ),
            )
          else if (_isSaved)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Icon(Icons.cloud_done, color: Color(0xFF309249), size: 24),
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero Image ──
            Stack(
              alignment: Alignment.topCenter,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 350,
                  child: _buildHeroImage(isDark),
                ),
                if (_isLoading)
                  Container(
                    width: double.infinity,
                    height: 350,
                    color: Colors.black54,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(
                          color: Color(0xFF4CAF50),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Identifying...",
                          style: GoogleFonts.spaceGrotesk(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Status Badge
                if (!_isLoading && _result != null)
                  Positioned(
                    top: 20,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _result!.label == 'Healthy'
                              ? const Color(0xFF4CAF50)
                              : Colors.redAccent,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          _result!.displayName.toUpperCase() +
                              (_result!.label != 'Healthy' ? " DETECTED" : ""),
                          style: GoogleFonts.spaceGrotesk(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            // ── Error State ──
            if (_errorMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _errorMessage,
                  style: const TextStyle(color: Colors.red),
                ),
              ),

            // ── Confidence Section ──
            if (!_isLoading && _result != null)
              FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  children: [
                    // Confidence strip
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      color: isDark
                          ? const Color(0xFF2C2C2C)
                          : const Color(0xFFE8F5E9),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _getConfidenceIcon(_result!.confidence),
                            color: TFLiteService.getConfidenceColor(
                                _result!.confidence),
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _result!.confidenceLabel,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: TFLiteService.getConfidenceColor(
                                  _result!.confidence),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Diagnose This Leaf CTA ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                      child: _buildDiagnoseCta(isDark),
                    ),

                    // Detailed info card
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black
                                  .withOpacity(isDark ? 0.4 : 0.08),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Detection Summary",
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 20),
                            _buildInfoRow(
                              "Disease",
                              _result!.displayName,
                              isDark,
                              icon: Icons.local_florist,
                            ),
                            const SizedBox(height: 16),
                            _buildInfoRow(
                              "Confidence",
                              _result!.confidencePercent,
                              isDark,
                              icon: Icons.analytics_outlined,
                              valueColor: TFLiteService.getConfidenceColor(
                                  _result!.confidence),
                            ),
                            const SizedBox(height: 16),
                            _buildInfoRow(
                              "Status",
                              _result!.confidenceLabel,
                              isDark,
                              icon: _getConfidenceIcon(_result!.confidence),
                            ),

                            // Retake hint for very low confidence
                            if (_result!.confidence < 0.40) ...[
                              const SizedBox(height: 20),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF44336)
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFF44336)
                                        .withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.camera_alt,
                                      color: Color(0xFFF44336),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        "Please retake the photo with better lighting and focus.",
                                        style: GoogleFonts.spaceGrotesk(
                                          fontSize: 13,
                                          color: const Color(0xFFF44336),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
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

  Widget _buildHeroImage(bool isDark) {
    // History mode: load from Cloud Storage URL
    if (_isHistory) {
      final url = widget.historyScan!.imageUrl;
      if (url != null && url.isNotEmpty) {
        return CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            color: isDark ? Colors.grey[900] : Colors.grey[200],
            alignment: Alignment.center,
            child: const CircularProgressIndicator(color: Color(0xFF309249)),
          ),
          errorWidget: (_, __, ___) => Container(
            color: isDark ? Colors.grey[900] : Colors.grey[200],
            alignment: Alignment.center,
            child: Icon(Icons.broken_image,
                size: 64, color: Colors.grey[500]),
          ),
        );
      }
      return Container(
        color: isDark ? Colors.grey[900] : Colors.grey[200],
        alignment: Alignment.center,
        child: Icon(Icons.eco, size: 64, color: Colors.grey[500]),
      );
    }
    // Live scan: local file
    return Image.file(File(widget.imagePath!), fit: BoxFit.cover);
  }

  Widget _buildDiagnoseCta(bool isDark) {
    // Determine whether we already have treatment info. If the history scan
    // is already a "diagnose" type, collapse the CTA into a "View Treatment"
    // shortcut so we never call /diagnose twice for the same scan.
    final historyHasTreatment = _isHistory &&
        widget.historyScan!.scanType == 'diagnose' &&
        (widget.historyScan!.treatmentSteps?.isNotEmpty ?? false);
    final alreadyUpgraded = _hasUpgraded;
    final isViewOnly = historyHasTreatment || alreadyUpgraded;

    if (_isDiagnosing) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFF309249).withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF309249),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              "Analyzing treatment...",
              style: GoogleFonts.spaceGrotesk(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF309249),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              if (isViewOnly && historyHasTreatment) {
                _openDiagnoseResult(widget.historyScan!.treatmentSteps!);
              } else {
                _onDiagnoseThisLeaf();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF309249),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            child: Text(
              isViewOnly ? "View Treatment" : "Diagnose This Leaf 🌿",
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
        if (_diagnoseError.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF44336).withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFF44336).withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.wifi_off,
                    color: Color(0xFFF44336), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _diagnoseError,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      color: const Color(0xFFF44336),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoRow(
    String label,
    String value,
    bool isDark, {
    IconData? icon,
    Color? valueColor,
  }) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 20,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
          const SizedBox(width: 12),
        ],
        Text(
          "$label: ",
          style: GoogleFonts.spaceGrotesk(
            fontSize: 15,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: valueColor ?? (isDark ? Colors.white : Colors.black87),
            ),
          ),
        ),
      ],
    );
  }

  IconData _getConfidenceIcon(double confidence) {
    if (confidence >= 0.80) return Icons.check_circle;
    if (confidence >= 0.60) return Icons.info;
    if (confidence >= 0.40) return Icons.warning_amber_rounded;
    return Icons.error_outline;
  }
}
