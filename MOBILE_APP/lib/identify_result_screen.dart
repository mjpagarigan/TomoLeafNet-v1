import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'services/tflite_service.dart';
import 'services/firestore_service.dart';
import 'services/storage_service.dart';

/// Identify Result Screen — disease detection only, no treatment info.
///
/// Displays the captured leaf image, detected disease name, and confidence
/// label. Saves the result to Firestore as an "identify" type scan.
class IdentifyResultScreen extends StatefulWidget {
  final String imagePath;

  const IdentifyResultScreen({super.key, required this.imagePath});

  @override
  State<IdentifyResultScreen> createState() => _IdentifyResultScreenState();
}

class _IdentifyResultScreenState extends State<IdentifyResultScreen>
    with SingleTickerProviderStateMixin {
  final _tfliteService = TFLiteService();
  final _firestoreService = FirestoreService();
  final _storageService = StorageService();

  bool _isLoading = true;
  TFLiteResult? _result;
  String _errorMessage = "";

  // Firebase save state
  bool _isSaving = false;
  bool _isSaved = false;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

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
    _runPrediction();
  }

  @override
  void dispose() {
    _tfliteService.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _runPrediction() async {
    try {
      final result = await _tfliteService.predict(widget.imagePath);
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
        localImagePath: widget.imagePath,
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
                Container(
                  width: double.infinity,
                  height: 350,
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: FileImage(File(widget.imagePath)),
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: _isLoading
                      ? Container(
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
                        )
                      : null,
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
