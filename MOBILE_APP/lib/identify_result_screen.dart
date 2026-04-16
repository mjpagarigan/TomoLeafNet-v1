import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'app_session.dart';
import 'diagnose_result_screen.dart';
import 'models/scan_model.dart';
import 'services/tflite_service.dart';
import 'services/community_contribution_service.dart';
import 'services/diagnostic_guide_service.dart';
import 'services/firestore_service.dart';
import 'services/heatmap_image_service.dart';
import 'services/storage_service.dart';
import 'widgets/disease_carousel.dart';
import 'widgets/scan_rating_section.dart';
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
  final _firestoreService = FirestoreService();
  final _storageService = StorageService();

  bool _isLoading = true;
  TFLiteResult? _result;
  String _errorMessage = "";

  // Firebase save state (live scan only)
  bool _isSaving = false;
  bool _isSaved = false;
  String? _savedScanId;
  String? _savedImageUrl;
  GeoPoint? _savedGpsCoordinates;

  // Diagnose This Leaf upgrade state
  bool _isDiagnosing = false;
  bool _hasUpgraded = false;
  String _diagnoseError = "";

  // Low confidence flow (Improvement 8)
  bool _showLowConfidenceWarning = false;
  bool _continuedAnyway = false;

  // Heatmap state (Improvement 4 — on-device occlusion sensitivity)
  bool _showGradCam = false;
  bool _isLoadingGradCam = false;
  Uint8List? _heatmapBytes;

  // Translation state (Improvement 3)
  bool _isFilipino = false;
  bool _isTranslating = false;
  final Map<String, String> _translations = {};

  String? _selectedRating;
  String? _ratingConfirmationMessage;
  String? _contributionPromptStatus;
  String? _correctionRequestStatus;
  String? _correctionRequestedDisease;
  bool _isContributionUploading = false;
  double _contributionProgress = 0.0;
  String? _contributionStatusMessage;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  bool get _isHistory => widget.historyScan != null;
  bool get _isGuest => AppSession.instance.isGuest;
  String? get _historyImageUrl => widget.historyScan?.previewImageUrl;

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
    // TFLiteService is a singleton — don't dispose it per screen.
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
      index: TFLiteService.getLabelIndex(scan.predictedDisease),
      confidence: scan.confidenceScore,
    );
    _isLoading = false;
    _savedScanId = scan.scanId;
    _savedImageUrl = scan.imageUrl;
    _savedGpsCoordinates = scan.gpsCoordinates;
    _isSaved = true;
    _continuedAnyway = true; // History items were already accepted
    _selectedRating = scan.userRating;
    _contributionPromptStatus = scan.contributionPromptStatus;
    _correctionRequestStatus = scan.correctionRequestStatus;
    _correctionRequestedDisease = scan.correctionRequestedDisease;
    _ratingConfirmationMessage = _confirmationMessageFor(scan.userRating);
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

        // Improvement 8: Low confidence (<60%) or ambiguous top-2 gap
        if (result.confidence < 0.60 || result.isAmbiguous) {
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
    if (_isGuest) return;
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
        disease2: _result!.secondLabel,
        confidenceScore: _result!.confidence,
        secondConfidence: _result!.secondConfidence,
        confidenceLabel: _result!.confidenceLabel,
        thresholdState: _result!.thresholdState,
        scanType: 'identify',
        gpsCoordinates: gpsCoordinates,
      );

      final uploaded = await _storageService.uploadScanImage(
        uid: user.uid,
        scanId: scanId,
        localImagePath: widget.imagePath!,
      );

      await _firestoreService.updateScanImageUrls(
        uid: user.uid,
        scanId: scanId,
        imageUrl: uploaded.imageUrl,
        thumbnailUrl: uploaded.thumbnailUrl,
      );

      if (mounted) {
        setState(() {
          _isSaved = true;
          _savedScanId = scanId;
          _savedImageUrl = uploaded.imageUrl;
          _savedGpsCoordinates = gpsCoordinates;
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

    if (_hasUpgraded) {
      _openDiagnoseResult();
      return;
    }

    setState(() {
      _isDiagnosing = true;
      _diagnoseError = "";
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && _savedScanId != null) {
        try {
          await _firestoreService.upgradeScanToDiagnose(
            uid: user.uid,
            scanId: _savedScanId!,
            treatmentSteps:
                DiagnosticGuideService.getEnglishRemedies(_result!.label),
          );
        } catch (e) {
          print('Failed to upgrade scan to diagnose: $e');
        }
      }

      if (!mounted) return;
      setState(() {
        _isDiagnosing = false;
        _hasUpgraded = true;
      });
      _openDiagnoseResult();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDiagnosing = false;
        _diagnoseError = 'Unable to open the diagnostic guide right now.';
      });
    }
  }

  void _openDiagnoseResult() {
    if (_result == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DiagnoseResultScreen.preloaded(
          label: _result!.label,
          confidence: _result!.confidence,
          scanId: _savedScanId,
          localImagePath: widget.imagePath,
          remoteImageUrl: _savedImageUrl ?? _historyImageUrl,
          upgradedFromIdentify: true,
        ),
      ),
    );
  }

  // ── Heatmap (Improvement 4 — on-device occlusion sensitivity) ──
  Future<void> _toggleGradCam() async {
    if (_showGradCam) {
      setState(() => _showGradCam = false);
      return;
    }
    if (_heatmapBytes != null) {
      setState(() => _showGradCam = true);
      return;
    }

    if (_result == null) return;

    setState(() => _isLoadingGradCam = true);

    try {
      final imagePath = await HeatmapImageService.resolveImagePath(
        localImagePath: widget.imagePath,
        remoteImageUrl: _historyImageUrl,
        cacheKey: _savedScanId ?? widget.historyScan?.scanId ?? _result!.label,
      );
      if (imagePath == null) {
        throw Exception('No image available for Grad-CAM.');
      }

      final bytes = await _tfliteService.generateHeatmap(
        imagePath,
        _result!.index,
      );
      if (mounted) {
        setState(() {
          _heatmapBytes = bytes;
          _showGradCam = true;
          _isLoadingGradCam = false;
        });
      }
    } catch (e) {
      print('Heatmap error: $e');
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
      final response = await http
          .post(
            Uri.parse(AppConfig.translateUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'texts': uncached,
              'target_language': 'tl',
            }),
          )
          .timeout(const Duration(seconds: 15));

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
    const englishOnlyLabels = {
      'Diagnose This Leaf',
    };
    if (englishOnlyLabels.contains(text)) return text;
    if (!_isFilipino) return text;
    return _translations[text] ?? text;
  }

  bool get _canShowGradCamButton {
    if (_isLoading || _result == null) return false;
    if (_result!.label == 'Healthy') return false;
    return widget.imagePath != null || _historyImageUrl != null;
  }

  bool get _canReportPrediction {
    return !_isGuest && _savedScanId != null && _result != null;
  }

  bool get _hasPendingCorrectionRequest {
    return _correctionRequestStatus == 'pending';
  }

  Future<void> _reportWrongPrediction() async {
    final result = _result;
    final user = FirebaseAuth.instance.currentUser;
    final scanId = _savedScanId;
    if (result == null ||
        user == null ||
        scanId == null ||
        _hasPendingCorrectionRequest) {
      return;
    }

    final correctedDisease = await _showCorrectionSheet(result.label);
    if (!mounted ||
        correctedDisease == null ||
        correctedDisease == result.label) {
      return;
    }

    try {
      await _firestoreService.submitScanCorrectionRequest(
        uid: user.uid,
        scanId: scanId,
        requestedDisease: correctedDisease,
        currentPredictedDisease: result.label,
        confidenceScore: result.confidence,
        scanType: _isHistory ? widget.historyScan!.scanType : 'identify',
        imageDownloadUrl: _savedImageUrl ?? _historyImageUrl,
      );

      if (!mounted) return;
      setState(() {
        _correctionRequestStatus = 'pending';
        _correctionRequestedDisease = correctedDisease;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Correction request sent for ${TFLiteService.getDisplayName(correctedDisease)}. Waiting for admin approval.',
            style: GoogleFonts.spaceGrotesk(),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to save the correction right now.',
            style: GoogleFonts.spaceGrotesk(),
          ),
        ),
      );
    }
  }

  Future<String?> _showCorrectionSheet(String currentLabel) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Correct scan result',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose the correct result for this scan. This will be sent to the admin and marked as waiting for approval.',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 14,
                    height: 1.45,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                if (_hasPendingCorrectionRequest) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFC107).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'A correction request for ${TFLiteService.getDisplayName(_correctionRequestedDisease ?? currentLabel)} is already pending.',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                ...TFLiteService.supportedLabels.map((label) {
                  final isSelected = label == currentLabel;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: isSelected || _hasPendingCorrectionRequest
                        ? null
                        : () => Navigator.pop(ctx, label),
                    leading: Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.bug_report_outlined,
                      color: isSelected
                          ? const Color(0xFF309249)
                          : const Color(0xFFF44336),
                    ),
                    title: Text(
                      TFLiteService.getDisplayName(label),
                      style: GoogleFonts.spaceGrotesk(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    subtitle: isSelected
                        ? Text(
                            'Current saved result',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 12,
                              color:
                                  isDark ? Colors.grey[500] : Colors.grey[600],
                            ),
                          )
                        : null,
                    trailing: isSelected
                        ? const Icon(
                            Icons.lock_outline,
                            size: 18,
                            color: Color(0xFF309249),
                          )
                        : null,
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  bool get _canShowRating {
    if (_result == null) return false;
    if (_result!.label == 'Not_Tomato') return false;
    if (_savedScanId == null) return false;
    return _result!.thresholdStateNumber >= 6 &&
        _result!.thresholdStateNumber <= 8;
  }

  bool get _shouldAskForContribution {
    if (_result == null) return false;
    return _selectedRating == 'thumbs_up' &&
        _contributionPromptStatus == null &&
        (_result!.thresholdState == 'confidentHealthy' ||
            _result!.thresholdState == 'confidentDisease' ||
            _result!.thresholdState == 'likely');
  }

  Future<void> _handleRating(String rating) async {
    if (_selectedRating != null || !_canShowRating) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _savedScanId == null) return;

    setState(() {
      _selectedRating = rating;
      _ratingConfirmationMessage = _confirmationMessageFor(rating);
    });

    await _firestoreService.updateScanFeedback(
      uid: user.uid,
      scanId: _savedScanId!,
      userRating: rating,
    );

    if (!_shouldAskForContribution) return;

    final profile = await _firestoreService.getUserProfile(user.uid);
    if (profile?.contributionOptOut == true) {
      setState(() => _contributionPromptStatus = 'opted_out');
      return;
    }

    if (!mounted) return;
    final accepted = await _showContributionPrompt();
    if (accepted == true) {
      await _startContributionUpload(user.uid);
    } else if (accepted == false) {
      await _firestoreService.updateScanContributionPromptStatus(
        uid: user.uid,
        scanId: _savedScanId!,
        contributionPromptStatus: 'declined',
      );
      if (mounted) {
        setState(() => _contributionPromptStatus = 'declined');
      }
    }
  }

  Future<bool?> _showContributionPrompt() {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Help TomoLeafNet get smarter!',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Your scan looks great and you confirmed it's accurate.\nWould you like to share this image anonymously to help\ntrain our model and improve results for other farmers?",
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      height: 1.5,
                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'What we collect:',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...const [
                    'Your leaf image (anonymous)',
                    'Detected disease or healthy status',
                    'Confidence score',
                    'Threshold state',
                    'Date and location (region only, not exact GPS)',
                  ].map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '• $item',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 13,
                          height: 1.5,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'We will never collect your name, account details, or exact location. Contributions are stored with an internal owner link only so you can view your stats and request deletion later.',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      height: 1.5,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF309249),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Yes, help improve TomoLeafNet',
                        style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        'No thanks',
                        style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _startContributionUpload(String uid) async {
    if (_result == null || _savedScanId == null) return;

    setState(() {
      _isContributionUploading = true;
      _contributionProgress = 0.0;
      _contributionStatusMessage = null;
    });

    try {
      final uploadResult =
          await CommunityContributionService.instance.contributeScan(
        ownerUid: uid,
        scanId: _savedScanId!,
        predictedDisease: _result!.label,
        disease2: _result!.secondLabel,
        topConfidence: _result!.confidence,
        secondConfidence: _result!.secondConfidence,
        thresholdState: _result!.thresholdState,
        localImagePath: widget.imagePath,
        remoteImageUrl: _savedImageUrl ?? _historyImageUrl,
        gpsCoordinates:
            _savedGpsCoordinates ?? widget.historyScan?.gpsCoordinates,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _contributionProgress = progress);
        },
      );

      if (!mounted) return;
      setState(() {
        _isContributionUploading = false;
        _contributionPromptStatus = 'accepted';
        _contributionStatusMessage = uploadResult.uploaded
            ? 'Contribution uploaded! Thank you for helping Filipino farmers. 🌿'
            : "Upload failed. We'll try again when you're connected.";
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isContributionUploading = false;
        _contributionStatusMessage =
            "Upload failed. We'll try again when you're connected.";
      });
    }
  }

  String? _confirmationMessageFor(String? rating) {
    switch (rating) {
      case 'thumbs_up':
        return 'Thanks for the feedback! 🌿';
      case 'thumbs_down':
        return "Thanks! We'll work on improving this.";
      default:
        return null;
    }
  }

  Widget _buildRatingAndContributionSection(bool isDark) {
    if (!_canShowRating) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        children: [
          ScanRatingSection(
            selectedRating: _selectedRating,
            confirmationMessage: _ratingConfirmationMessage,
            enabled: _savedScanId != null && !_isContributionUploading,
            onThumbsUp: () => _handleRating('thumbs_up'),
            onThumbsDown: () => _handleRating('thumbs_down'),
          ),
          if (_isContributionUploading ||
              _contributionStatusMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isContributionUploading
                      ? const Color(0xFF309249).withOpacity(0.25)
                      : (_contributionStatusMessage
                                  ?.startsWith('Contribution uploaded') ??
                              false)
                          ? const Color(0xFF309249).withOpacity(0.25)
                          : Colors.orangeAccent.withOpacity(0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isContributionUploading
                        ? 'Uploading your contribution...'
                        : _contributionStatusMessage!,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  if (_isContributionUploading) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: _contributionProgress <= 0
                          ? null
                          : _contributionProgress.clamp(0.0, 1.0),
                      color: const Color(0xFF309249),
                      backgroundColor:
                          const Color(0xFF309249).withOpacity(0.12),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppSession>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F0);
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    // Improvement 9: Not Tomato — full-screen retake prompt
    if (!_isLoading &&
        _result != null &&
        _result!.label == 'Not_Tomato' &&
        !_isHistory) {
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
          if (!_isGuest && _isSaving)
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
          else if (!_isGuest && _isSaved)
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
            if (_continuedAnyway &&
                _result != null &&
                _result!.confidence < 0.60)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
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
                  child: _showGradCam && _heatmapBytes != null
                      ? Image.memory(
                          _heatmapBytes!,
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
                if (_canShowGradCamButton)
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
                          _showGradCam
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                if (_canReportPrediction)
                  Positioned(
                    top: _canShowGradCamButton ? 84 : 20,
                    right: 16,
                    child: GestureDetector(
                      onTap: _hasPendingCorrectionRequest
                          ? null
                          : _reportWrongPrediction,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (_hasPendingCorrectionRequest
                                  ? const Color(0xFFFFC107)
                                  : const Color(0xFFF44336))
                              .withOpacity(0.92),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _hasPendingCorrectionRequest
                              ? Icons.hourglass_top_rounded
                              : Icons.warning_amber_rounded,
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
            if (_showGradCam && _heatmapBytes != null)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                color:
                    isDark ? const Color(0xFF2C2C2C) : const Color(0xFFFFF3E0),
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
                    // Threshold tier strip (Step 5: Monitor / Step 8: Confident Healthy)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      color: isDark
                          ? const Color(0xFF2C2C2C)
                          : const Color(0xFFE8F5E9),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            TFLiteService.getThresholdIcon(
                                _result!.label, _result!.confidence),
                            style: const TextStyle(fontSize: 20),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _t(TFLiteService.getThresholdLabel(
                                _result!.label, _result!.confidence)),
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: TFLiteService.getThresholdColor(
                                  _result!.label, _result!.confidence),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Healthy message
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
                              color:
                                  Colors.black.withOpacity(isDark ? 0.4 : 0.08),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Icon(
                              _result!.confidence >= 0.80
                                  ? Icons.check_circle
                                  : Icons.visibility,
                              color: TFLiteService.getThresholdColor(
                                  _result!.label, _result!.confidence),
                              size: 56,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _t(TFLiteService.getThresholdTitle(
                                  _result!.label, _result!.confidence)),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: TFLiteService.getThresholdColor(
                                    _result!.label, _result!.confidence),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _t(TFLiteService.getThresholdBody(
                                  _result!.label, _result!.confidence)),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 14,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
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

                    _buildRatingAndContributionSection(isDark),

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
                    // Threshold tier strip (Step 6: Likely / Step 7: Confirmed)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      color: isDark
                          ? const Color(0xFF2C2C2C)
                          : const Color(0xFFE8F5E9),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            TFLiteService.getThresholdIcon(
                                _result!.label, _result!.confidence),
                            style: const TextStyle(fontSize: 20),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _t(TFLiteService.getThresholdTitle(
                                _result!.label, _result!.confidence)),
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: TFLiteService.getThresholdColor(
                                  _result!.label, _result!.confidence),
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
                              color:
                                  Colors.black.withOpacity(isDark ? 0.4 : 0.08),
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

                            if (_result!.label == 'Early_Blight' ||
                                _result!.label == 'Leaf_Miner' ||
                                _result!.label == 'Leaf_Mold') ...[
                              const SizedBox(height: 20),
                              Divider(
                                  color:
                                      isDark ? Colors.white24 : Colors.black12),
                              const SizedBox(height: 16),
                              Text(
                                "Description",
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _getDiseaseInfo(
                                    _result!.label, false)['description']!,
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 14,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                "Symptoms",
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _getDiseaseInfo(
                                    _result!.label, false)['symptoms']!,
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 14,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                  height: 1.5,
                                ),
                              ),
                            ],

                            // Retake hint for very low confidence
                            if (_result!.confidence < 0.40) ...[
                              const SizedBox(height: 20),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFFF44336).withOpacity(0.1),
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

                    _buildRatingAndContributionSection(isDark),

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
          icon: Icon(Icons.arrow_back,
              color: Theme.of(context).colorScheme.onSurface),
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
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _onRetakePhoto,
                    icon: const Icon(Icons.camera_alt, size: 18),
                    label: Text(
                      _isFilipino ? "Kunan Muli" : "Retake Photo",
                      style:
                          GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
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
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      // The camera screen is still in the stack
                    },
                    icon: const Icon(Icons.image, size: 18),
                    label: Text(
                      _isFilipino
                          ? "Pumili mula Gallery"
                          : "Choose from Gallery",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.spaceGrotesk(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
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
          icon: Icon(Icons.arrow_back,
              color: Theme.of(context).colorScheme.onSurface),
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
                      style:
                          GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
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
                      _isFilipino
                          ? "Ituloy Pa Rin \u2192"
                          : "Continue Anyway \u2192",
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
      final url = _historyImageUrl;
      if (url != null && url.isNotEmpty) {
        return CachedNetworkImage(
          imageUrl: url,
          memCacheWidth: 1080,
          memCacheHeight: 700,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            color: isDark ? Colors.grey[900] : Colors.grey[200],
            alignment: Alignment.center,
            child: const CircularProgressIndicator(color: Color(0xFF309249)),
          ),
          errorWidget: (_, __, ___) => Container(
            color: isDark ? Colors.grey[900] : Colors.grey[200],
            alignment: Alignment.center,
            child: Icon(Icons.broken_image, size: 64, color: Colors.grey[500]),
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
    final historyHasGuide =
        _isHistory && widget.historyScan!.scanType == 'diagnose';
    final alreadyUpgraded = _hasUpgraded;
    final isViewOnly = historyHasGuide || alreadyUpgraded;

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
              "Opening guide...",
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
              if (isViewOnly && historyHasGuide) {
                _openDiagnoseResult();
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
                  ? "View Diagnostic Guide"
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
                const Icon(Icons.wifi_off, color: Color(0xFFF44336), size: 20),
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

  Map<String, String> _getDiseaseInfo(String label, bool isFilipino) {
    const useEnglishOnly = true;
    switch (label) {
      case 'Early_Blight':
        return {
          'description': useEnglishOnly
              ? "A common fungal disease caused by Alternaria solani."
              : isFilipino
                  ? "Isang karaniwang sakit na dala ng fungus na Alternaria solani."
                  : "A common fungal disease caused by Alternaria solani.",
          'symptoms': useEnglishOnly
              ? "Dark, concentric rings or bullseye spots on older leaves, yellowing of surrounding tissue, and premature leaf drop."
              : isFilipino
                  ? "Maiitim at pabilog na batik sa mga lumang dahon, paninilaw ng paligid ng batik, at maagang pagkalagas ng dahon."
                  : "Dark, concentric rings or bullseye spots on older leaves, yellowing of surrounding tissue, and premature leaf drop."
        };
      case 'Leaf_Miner':
        return {
          'description': useEnglishOnly
              ? "Damage caused by insect larvae living and feeding inside the leaf tissue."
              : isFilipino
                  ? "Pinsala na dulot ng uod ng insekto na naninirahan at kumakain sa loob ng dahon."
                  : "Damage caused by insect larvae living and feeding inside the leaf tissue.",
          'symptoms': useEnglishOnly
              ? "White or grayish winding trails or tunnels (mines) on the leaves."
              : isFilipino
                  ? "Puti o abuhin na paliku-likong linya o tunnel (mines) sa mga dahon."
                  : "White or grayish winding trails or tunnels (mines) on the leaves."
        };
      case 'Leaf_Mold':
        return {
          'description': useEnglishOnly
              ? "A fungal disease caused by Passalora fulva, common in high humidity."
              : isFilipino
                  ? "Isang sakit na dala ng fungus na Passalora fulva, karaniwan sa mga lugar na mataas ang halumigmig."
                  : "A fungal disease caused by Passalora fulva, common in high humidity.",
          'symptoms': useEnglishOnly
              ? "Pale green or yellow spots on the upper leaf surface, with olive-green to brown velvety mold on the underside."
              : isFilipino
                  ? "Maputlang berde o dilaw na batik sa ibabaw ng dahon, at may tila pelus na amag na kulay olive-green hanggang kayumanggi sa ilalim."
                  : "Pale green or yellow spots on the upper leaf surface, with olive-green to brown velvety mold on the underside."
        };
      default:
        return {'description': "", 'symptoms': ""};
    }
  }

  IconData _getConfidenceIcon(double confidence) {
    if (confidence >= 0.80) return Icons.check_circle;
    if (confidence >= 0.60) return Icons.info;
    if (confidence >= 0.40) return Icons.warning_amber_rounded;
    return Icons.error_outline;
  }
}
