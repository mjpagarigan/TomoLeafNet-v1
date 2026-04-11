import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'models/scan_model.dart';
import 'services/tflite_service.dart';
import 'services/diagnose_service.dart';
import 'services/firestore_service.dart';
import 'services/storage_service.dart';

/// Diagnose Result Screen — disease detection + AI-generated treatment steps.
///
/// Three modes:
///   1. Live scan (imagePath) — runs TFLite + /diagnose pipeline and saves.
///   2. History view (historyScan) — rehydrates from a Firestore scan document.
///   3. Preloaded (label/confidence/steps) — shows pre-fetched results after
///      upgrading from the Identify flow.
class DiagnoseResultScreen extends StatefulWidget {
  final String? imagePath;
  final ScanModel? historyScan;
  final String? preloadedLabel;
  final double? preloadedConfidence;
  final List<String>? preloadedSteps;
  final String? preloadedLocalImagePath;
  final String? preloadedRemoteImageUrl;
  final bool upgradedFromIdentify;

  const DiagnoseResultScreen({super.key, required this.imagePath})
      : historyScan = null,
        preloadedLabel = null,
        preloadedConfidence = null,
        preloadedSteps = null,
        preloadedLocalImagePath = null,
        preloadedRemoteImageUrl = null,
        upgradedFromIdentify = false;

  const DiagnoseResultScreen.history({super.key, required this.historyScan})
      : imagePath = null,
        preloadedLabel = null,
        preloadedConfidence = null,
        preloadedSteps = null,
        preloadedLocalImagePath = null,
        preloadedRemoteImageUrl = null,
        upgradedFromIdentify = false;

  DiagnoseResultScreen.preloaded({
    super.key,
    required String label,
    required double confidence,
    required List<String> treatmentSteps,
    String? localImagePath,
    String? remoteImageUrl,
    this.upgradedFromIdentify = false,
  })  : imagePath = null,
        historyScan = null,
        preloadedLabel = label,
        preloadedConfidence = confidence,
        preloadedSteps = treatmentSteps,
        preloadedLocalImagePath = localImagePath,
        preloadedRemoteImageUrl = remoteImageUrl;

  @override
  State<DiagnoseResultScreen> createState() => _DiagnoseResultScreenState();
}

class _DiagnoseResultScreenState extends State<DiagnoseResultScreen>
    with SingleTickerProviderStateMixin {
  final _tfliteService = TFLiteService();
  final _diagnoseService = DiagnoseService();
  final _firestoreService = FirestoreService();
  final _storageService = StorageService();

  bool _isDetecting = true;
  TFLiteResult? _result;
  String _errorMessage = "";

  bool _isLoadingTreatment = false;
  List<String>? _treatmentSteps;
  String _treatmentError = "";

  bool _isSaving = false;
  bool _isSaved = false;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  bool get _isHistory => widget.historyScan != null;
  bool get _isPreloaded => widget.preloadedLabel != null;

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
    } else if (_isPreloaded) {
      _hydrateFromPreloaded();
    } else {
      _runPipeline();
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
    _treatmentSteps = scan.treatmentSteps;
    _isDetecting = false;
    _isSaved = true;
    _fadeController.forward();
  }

  void _hydrateFromPreloaded() {
    _result = TFLiteResult(
      label: widget.preloadedLabel!,
      index: 0,
      confidence: widget.preloadedConfidence!,
    );
    _treatmentSteps = widget.preloadedSteps;
    _isDetecting = false;
    _isSaved = true;
    _fadeController.forward();
  }

  /// Full pipeline: TFLite inference → Groq treatment steps → Firestore save
  Future<void> _runPipeline() async {
    try {
      final result = await _tfliteService.predict(widget.imagePath!);
      if (!mounted) return;

      setState(() {
        _result = result;
        _isDetecting = false;
        _isLoadingTreatment = true;
      });
      _fadeController.forward();

      try {
        final steps = await _diagnoseService.getTreatmentSteps(
          disease: result.label,
          confidence: double.parse(
              (result.confidence * 100).toStringAsFixed(1)),
        );
        if (mounted) {
          setState(() {
            _treatmentSteps = steps;
            _isLoadingTreatment = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _treatmentError =
                "Treatment advice unavailable. Please check your connection and try again.";
            _isLoadingTreatment = false;
          });
        }
      }

      _saveScanToFirebase();
    } catch (e, stackTrace) {
      print("Error running model: $e\n$stackTrace");
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isDetecting = false;
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
        scanType: 'diagnose',
        gpsCoordinates: gpsCoordinates,
        treatmentSteps: _treatmentSteps,
      );

      final imageUrl = await _storageService.uploadScanImage(
        uid: user.uid,
        scanId: scanId,
        localImagePath: widget.imagePath!,
      );

      await _firestoreService.updateScanImageUrl(user.uid, scanId, imageUrl);

      if (mounted) setState(() => _isSaved = true);
    } catch (e) {
      print('Error saving scan: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
          "Diagnosis Results",
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
                if (_isDetecting)
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
                          "Diagnosing...",
                          style: GoogleFonts.spaceGrotesk(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Status Badge
                if (!_isDetecting && _result != null)
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

            // ── Detection + Treatment Results ──
            if (!_isDetecting && _result != null)
              FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                            "${_result!.confidenceLabel}  •  ${_result!.confidencePercent}",
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: TFLiteService.getConfidenceColor(
                                  _result!.confidence),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Upgraded from Identify note ──
                    if (widget.upgradedFromIdentify)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF309249).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF309249).withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline,
                                  color: Color(0xFF309249), size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "Identified via Identify, diagnosed via AI",
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 13,
                                    color: const Color(0xFF309249),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // ── How to Treat Section ──
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.healing,
                                color: const Color(0xFF309249),
                                size: 24,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                "How to Treat",
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Loading state
                          if (_isLoadingTreatment)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(32),
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
                                children: [
                                  const SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: Color(0xFF309249),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    "Analyzing treatment...",
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 15,
                                      color: isDark
                                          ? Colors.grey[400]
                                          : Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Error state
                          if (_treatmentError.isNotEmpty &&
                              !_isLoadingTreatment)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF44336)
                                    .withOpacity(0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFF44336)
                                      .withOpacity(0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.wifi_off,
                                    color: Color(0xFFF44336),
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _treatmentError,
                                      style: GoogleFonts.spaceGrotesk(
                                        fontSize: 14,
                                        color: isDark
                                            ? Colors.red[300]
                                            : const Color(0xFFF44336),
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Treatment steps
                          if (_treatmentSteps != null &&
                              _treatmentSteps!.isNotEmpty &&
                              !_isLoadingTreatment)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
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
                                children: _treatmentSteps!
                                    .asMap()
                                    .entries
                                    .map((entry) => _buildTreatmentStep(
                                          entry.key + 1,
                                          entry.value,
                                          isDark,
                                          isLast: entry.key ==
                                              _treatmentSteps!.length - 1,
                                        ))
                                    .toList(),
                              ),
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
    );
  }

  Widget _buildHeroImage(bool isDark) {
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

    if (_isPreloaded) {
      if (widget.preloadedLocalImagePath != null) {
        return Image.file(
          File(widget.preloadedLocalImagePath!),
          fit: BoxFit.cover,
        );
      }
      if (widget.preloadedRemoteImageUrl != null) {
        return CachedNetworkImage(
          imageUrl: widget.preloadedRemoteImageUrl!,
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

  Widget _buildTreatmentStep(
    int number,
    String step,
    bool isDark, {
    bool isLast = false,
  }) {
    String cleanStep = step.replaceFirst(RegExp(r'^\d+[\.\)]\s*'), '');

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF309249).withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$number',
              style: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: const Color(0xFF309249),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                cleanStep,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 15,
                  color: isDark ? Colors.white.withOpacity(0.9) : Colors.black87,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getConfidenceIcon(double confidence) {
    if (confidence >= 0.80) return Icons.check_circle;
    if (confidence >= 0.60) return Icons.info;
    if (confidence >= 0.40) return Icons.warning_amber_rounded;
    return Icons.error_outline;
  }
}
