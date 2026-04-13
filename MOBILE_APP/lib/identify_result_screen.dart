import 'dart:io';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'diagnose_result_screen.dart';
import 'models/scan_model.dart';
import 'services/tflite_service.dart';
import 'services/diagnose_service.dart';
import 'services/firestore_service.dart';
import 'services/storage_service.dart';
import 'widgets/disease_carousel.dart';
import 'core/config/app_config.dart';

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

  // Low confidence flow (Improvement 8)
  bool _showLowConfidenceWarning = false;
  bool _continuedAnyway = false;

  // GradCAM state (Improvement 4)
  bool _showGradCam = false;
  bool _isLoadingGradCam = false;
  String? _gradCamImageBase64;

  // Translation state (Improvement 3)
  bool _isFilipino = false;
  bool _isTranslating = false;
  final Map<String, String> _translations = {};

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

    _loadLanguagePreference();

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

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isFilipino = prefs.getBool('preferFilipino') ?? false;
      });
    }
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
    _continuedAnyway = true; // History items were already accepted
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

        // Improvement 9: Not Tomato — show retake prompt immediately
        if (result.label == 'Not_Tomato') {
          // Do not save to Firestore
          return;
        }

        // Improvement 8: Low confidence (<60%) — show retake prompt
        if (result.confidence < 0.60) {
          setState(() => _showLowConfidenceWarning = true);
          // Don't save yet — wait for user to tap "Continue Anyway"
          return;
        }

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

  void _onContinueAnyway() {
    setState(() {
      _showLowConfidenceWarning = false;
      _continuedAnyway = true;
    });
    _saveScanToFirebase();
  }

  void _onRetakePhoto() {
    Navigator.pop(context);
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

  Future<void> _onDiagnoseThisLeaf() async {
    if (_result == null || _isDiagnosing) return;

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

  // ── GradCAM (Improvement 4) ──
  Future<void> _toggleGradCam() async {
    if (_showGradCam) {
      setState(() => _showGradCam = false);
      return;
    }
    if (_gradCamImageBase64 != null) {
      setState(() => _showGradCam = true);
      return;
    }

    setState(() => _isLoadingGradCam = true);

    try {
      final imageBytes = widget.imagePath != null
          ? await File(widget.imagePath!).readAsBytes()
          : null;
      if (imageBytes == null) {
        setState(() => _isLoadingGradCam = false);
        return;
      }

      final response = await http.post(
        Uri.parse(AppConfig.gradcamUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'image_base64': base64Encode(imageBytes),
          'predicted_class_index': _result!.index,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _gradCamImageBase64 = data['gradcam_image_base64'];
            _showGradCam = true;
            _isLoadingGradCam = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingGradCam = false);
      }
    } catch (e) {
      print('GradCAM error: $e');
      if (mounted) setState(() => _isLoadingGradCam = false);
    }
  }

  // ── Translation (Improvement 3) ──
  Future<void> _toggleLanguage() async {
    final newValue = !_isFilipino;
    setState(() => _isFilipino = newValue);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('preferFilipino', newValue);

    if (newValue && _result != null) {
      await _translateContent();
    }
  }

  Future<void> _translateContent() async {
    if (_result == null) return;

    final textsToTranslate = <String>[
      _result!.displayName,
      _result!.confidenceLabel,
      'Detection Summary',
      'Disease',
      'Confidence',
      'Status',
      'Diagnose This Leaf',
      'Your tomato leaf appears healthy!',
      'No disease detected. Keep up your current care routine.',
    ];

    // Check cache
    final prefs = await SharedPreferences.getInstance();
    final uncached = <String>[];
    for (final text in textsToTranslate) {
      final cached = prefs.getString('translate_$text');
      if (cached != null) {
        _translations[text] = cached;
      } else {
        uncached.add(text);
      }
    }

    if (uncached.isEmpty) {
      if (mounted) setState(() {});
      return;
    }

    setState(() => _isTranslating = true);

    try {
      final response = await http.post(
        Uri.parse(AppConfig.translateUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'texts': uncached,
          'target_language': 'tl',
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final translated = List<String>.from(data['translations'] ?? []);
        for (int i = 0; i < uncached.length && i < translated.length; i++) {
          _translations[uncached[i]] = translated[i];
          await prefs.setString('translate_${uncached[i]}', translated[i]);
        }
      }
    } catch (e) {
      print('Translation error: $e');
    }

    if (mounted) setState(() => _isTranslating = false);
  }

  String _t(String text) {
    if (!_isFilipino) return text;
    return _translations[text] ?? text;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F0);
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    // Improvement 9: Not Tomato — full-screen retake prompt
    if (!_isLoading && _result != null && _result!.label == 'Not_Tomato' && !_isHistory) {
      return _buildNotTomatoScreen(isDark);
    }

    // Improvement 8: Low confidence retake prompt
    if (_showLowConfidenceWarning && !_continuedAnyway) {
      return _buildLowConfidenceScreen(isDark);
    }

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
          // Translation toggle (Improvement 3)
          if (!_isLoading && _result != null && _result!.label != 'Not_Tomato')
            TextButton(
              onPressed: _toggleLanguage,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF309249).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF309249).withOpacity(0.3),
                  ),
                ),
                child: Text(
                  _isFilipino ? "FIL" : "EN",
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF309249),
                  ),
                ),
              ),
            ),
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
            // ── Low confidence warning banner (Improvement 8) ──
            if (_continuedAnyway && _result != null && _result!.confidence < 0.60)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                color: const Color(0xFFF44336).withOpacity(0.15),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Color(0xFFF44336), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isFilipino
                            ? "Mababang kumpiyansa - maaaring hindi tumpak ang diagnosis na ito"
                            : "Low confidence result \u2014 this diagnosis may not be accurate",
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 12,
                          color: const Color(0xFFF44336),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Translation loading indicator ──
            if (_isTranslating)
              const LinearProgressIndicator(
                color: Color(0xFF309249),
                backgroundColor: Colors.transparent,
                minHeight: 2,
              ),

            // ── Hero Image ──
            Stack(
              alignment: Alignment.topCenter,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 350,
                  child: _showGradCam && _gradCamImageBase64 != null
                      ? Image.memory(
                          base64Decode(_gradCamImageBase64!),
                          fit: BoxFit.cover,
                        )
                      : _buildHeroImage(isDark),
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
                // GradCAM loading overlay
                if (_isLoadingGradCam)
                  Container(
                    width: double.infinity,
                    height: 350,
                    color: Colors.black38,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(
                      color: Color(0xFF4CAF50),
                    ),
                  ),
                // GradCAM toggle button (Improvement 4)
                if (!_isLoading && _result != null && widget.imagePath != null &&
                    _result!.label != 'Healthy')
                  Positioned(
                    top: 20,
                    right: 16,
                    child: GestureDetector(
                      onTap: _toggleGradCam,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _showGradCam ? Icons.visibility_off : Icons.visibility,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
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

            // ── GradCAM label ──
            if (_showGradCam && _gradCamImageBase64 != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFFFF3E0),
                child: Text(
                  _isFilipino
                      ? "Ang mga lugar na naka-highlight sa pula ay kung saan nakatuon ang modelo"
                      : "Areas highlighted in red indicate where the model focused",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    color: isDark ? Colors.orange[200] : Colors.orange[800],
                  ),
                ),
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

            // ── Healthy message (Improvement 6) ──
            if (!_isLoading && _result != null && _result!.label == 'Healthy')
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
                            _t(_result!.confidenceLabel),
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

                    // Healthy positive message
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
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: Color(0xFF4CAF50),
                              size: 56,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _t("Your tomato leaf appears healthy!"),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF4CAF50),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _t("No disease detected. Keep up your current care routine."),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 14,
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Detection Summary
                            _buildInfoRow(
                              _t("Disease"),
                              _t(_result!.displayName),
                              isDark,
                              icon: Icons.local_florist,
                            ),
                            const SizedBox(height: 12),
                            _buildInfoRow(
                              _t("Confidence"),
                              _result!.confidencePercent,
                              isDark,
                              icon: Icons.analytics_outlined,
                              valueColor: TFLiteService.getConfidenceColor(
                                  _result!.confidence),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Carousel for Healthy
                    DiseaseCarousel(diseaseLabel: _result!.label),
                    const SizedBox(height: 24),
                  ],
                ),
              ),

            // ── Disease detected content (not Healthy, not Not_Tomato) ──
            if (!_isLoading &&
                _result != null &&
                _result!.label != 'Healthy' &&
                _result!.label != 'Not_Tomato')
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
                            _t(_result!.confidenceLabel),
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
                              _t("Detection Summary"),
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 20),
                            _buildInfoRow(
                              _t("Disease"),
                              _t(_result!.displayName),
                              isDark,
                              icon: Icons.local_florist,
                            ),
                            const SizedBox(height: 16),
                            _buildInfoRow(
                              _t("Confidence"),
                              _result!.confidencePercent,
                              isDark,
                              icon: Icons.analytics_outlined,
                              valueColor: TFLiteService.getConfidenceColor(
                                  _result!.confidence),
                            ),
                            const SizedBox(height: 16),
                            _buildInfoRow(
                              _t("Status"),
                              _t(_result!.confidenceLabel),
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

                    // ── Disease Comparison Carousel (Improvement 1) ──
                    DiseaseCarousel(diseaseLabel: _result!.label),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Not Tomato full-screen retake (Improvement 9) ──
  Widget _buildNotTomatoScreen(bool isDark) {
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F0);
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Scan Result",
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.4 : 0.1),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("🍅", style: const TextStyle(fontSize: 56)),
                const SizedBox(height: 20),
                Text(
                  _isFilipino
                      ? "Hindi ito mukhang dahon ng kamatis."
                      : "This doesn't look like a tomato leaf.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _isFilipino
                      ? "Ang TomoLeafNet ay espesyal na ginawa para sa pagtuklas ng sakit ng dahon ng kamatis."
                      : "TomoLeafNet is designed specifically for tomato leaf disease detection.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 14,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF44336).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isFilipino ? "Siguraduhing:" : "Please make sure to:",
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildBullet(
                        _isFilipino
                            ? "I-scan lamang ang dahon ng kamatis"
                            : "Scan only tomato plant leaves",
                        isDark,
                      ),
                      _buildBullet(
                        _isFilipino
                            ? "Siguraduhing malinaw ang dahon at pumupuno sa kahon"
                            : "Ensure the leaf is clearly visible and fills the box",
                        isDark,
                      ),
                      _buildBullet(
                        _isFilipino
                            ? "Iwasan ang pag-scan ng lupa, tangkay, prutas, o ibang halaman"
                            : "Avoid scanning soil, stems, fruits, or other plants",
                        isDark,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _onRetakePhoto,
                        icon: const Icon(Icons.camera_alt, size: 18),
                        label: Text(
                          _isFilipino ? "Kunan Muli" : "Retake Photo",
                          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF309249),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          // The camera screen is still in the stack
                        },
                        icon: const Icon(Icons.image, size: 18),
                        label: Text(
                          _isFilipino ? "Pumili mula Gallery" : "Choose from Gallery",
                          style: GoogleFonts.spaceGrotesk(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF309249),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: const BorderSide(color: Color(0xFF309249)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Low Confidence retake screen (Improvement 8) ──
  Widget _buildLowConfidenceScreen(bool isDark) {
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F0);
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final confPercent = (_result!.confidence * 100).toStringAsFixed(0);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Scan Result",
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.4 : 0.1),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFF44336), size: 56),
                const SizedBox(height: 16),
                Text(
                  _isFilipino
                      ? "Hindi kami kumpiyansa sa resultang ito."
                      : "We're not confident about this result.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isFilipino
                      ? "Kumpiyansa: $confPercent% — Masyadong mababa para sa maaasahang diagnosis."
                      : "Confidence: $confPercent% \u2014 This is too low for a reliable diagnosis.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 14,
                    color: const Color(0xFFF44336),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.05)
                        : Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isFilipino
                            ? "Para sa mas magandang resulta:"
                            : "For best results:",
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildBullet(
                        _isFilipino
                            ? "Kumuha ng larawan sa natural na liwanag sa labas"
                            : "Take the photo in natural outdoor lighting",
                        isDark,
                      ),
                      _buildBullet(
                        _isFilipino
                            ? "Lumapit sa apektadong dahon (15\u201330 cm)"
                            : "Get close to the affected leaf (15\u201330 cm)",
                        isDark,
                      ),
                      _buildBullet(
                        _isFilipino
                            ? "Siguraduhing pumupuno ang dahon sa camera box"
                            : "Make sure the leaf fills the camera box",
                        isDark,
                      ),
                      _buildBullet(
                        _isFilipino
                            ? "Iwasan ang malabo o madilim na mga larawan"
                            : "Avoid blurry or shaded images",
                        isDark,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _onRetakePhoto,
                    icon: const Icon(Icons.camera_alt, size: 18),
                    label: Text(
                      _isFilipino ? "Kunan Muli" : "Retake Photo",
                      style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF309249),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _onContinueAnyway,
                    child: Text(
                      _isFilipino ? "Ituloy Pa Rin \u2192" : "Continue Anyway \u2192",
                      style: GoogleFonts.spaceGrotesk(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBullet(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "\u2022  ",
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontSize: 14,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                height: 1.4,
              ),
            ),
          ),
        ],
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
    return Image.file(File(widget.imagePath!), fit: BoxFit.cover);
  }

  Widget _buildDiagnoseCta(bool isDark) {
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
              isViewOnly
                  ? "View Treatment"
                  : _t("Diagnose This Leaf") + " 🌿",
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
