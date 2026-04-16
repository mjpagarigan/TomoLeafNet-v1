import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'models/scan_model.dart';
import 'services/tflite_service.dart';
import 'services/community_contribution_service.dart';
import 'services/diagnose_service.dart';
import 'services/firestore_service.dart';
import 'services/storage_service.dart';
import 'widgets/disease_carousel.dart';
import 'widgets/scan_rating_section.dart';
import 'core/config/app_config.dart';
import 'models/reminder_model.dart';
import 'screens/reminders_screen.dart';

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
  final String? preloadedScanId;
  final String? preloadedLocalImagePath;
  final String? preloadedRemoteImageUrl;
  final bool upgradedFromIdentify;

  const DiagnoseResultScreen({super.key, required this.imagePath})
      : historyScan = null,
        preloadedLabel = null,
        preloadedConfidence = null,
        preloadedSteps = null,
        preloadedScanId = null,
        preloadedLocalImagePath = null,
        preloadedRemoteImageUrl = null,
        upgradedFromIdentify = false;

  const DiagnoseResultScreen.history({super.key, required this.historyScan})
      : imagePath = null,
        preloadedLabel = null,
        preloadedConfidence = null,
        preloadedSteps = null,
        preloadedScanId = null,
        preloadedLocalImagePath = null,
        preloadedRemoteImageUrl = null,
        upgradedFromIdentify = false;

  DiagnoseResultScreen.preloaded({
    super.key,
    required String label,
    required double confidence,
    required List<String> treatmentSteps,
    String? scanId,
    String? localImagePath,
    String? remoteImageUrl,
    this.upgradedFromIdentify = false,
  })  : imagePath = null,
        historyScan = null,
        preloadedLabel = label,
        preloadedConfidence = confidence,
        preloadedSteps = treatmentSteps,
        preloadedScanId = scanId,
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
  String? _savedScanId;
  String? _savedImageUrl;
  GeoPoint? _savedGpsCoordinates;

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
  bool _isContributionUploading = false;
  double _contributionProgress = 0.0;
  String? _contributionStatusMessage;

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

    _loadLanguagePreference();

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
    _treatmentSteps = scan.treatmentSteps;
    _isDetecting = false;
    _savedScanId = scan.scanId;
    _savedImageUrl = scan.imageUrl;
    _savedGpsCoordinates = scan.gpsCoordinates;
    _isSaved = true;
    _continuedAnyway = true;
    _selectedRating = scan.userRating;
    _contributionPromptStatus = scan.contributionPromptStatus;
    _ratingConfirmationMessage = _confirmationMessageFor(scan.userRating);
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
    _savedScanId = widget.preloadedScanId;
    _savedImageUrl = widget.preloadedRemoteImageUrl;
    _isSaved = true;
    _continuedAnyway = true;
    _fadeController.forward();
  }

  /// Full pipeline: TFLite inference -> Groq treatment steps -> Firestore save
  Future<void> _runPipeline() async {
    try {
      final result = await _tfliteService.predict(widget.imagePath!);
      if (!mounted) return;

      setState(() {
        _result = result;
        _isDetecting = false;
      });
      _fadeController.forward();

      // Improvement 9: Not Tomato — don't proceed
      if (result.label == 'Not_Tomato') {
        return;
      }

      // Improvement 8: Low confidence (<60%) or ambiguous top-2 gap
      if (result.confidence < 0.60 || result.isAmbiguous) {
        setState(() => _showLowConfidenceWarning = true);
        return;
      }

      // Improvement 6: Healthy — show care tips, no treatment
      if (result.label == 'Healthy') {
        _saveScanToFirebase();
        return;
      }

      setState(() => _isLoadingTreatment = true);
      await _fetchTreatment(result);
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

  Future<void> _fetchTreatment(TFLiteResult result) async {
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
          _treatmentError = e.toString().replaceFirst('Exception: ', '');
          _isLoadingTreatment = false;
        });
      }
    }
  }

  Future<void> _onContinueAnyway() async {
    setState(() {
      _showLowConfidenceWarning = false;
      _continuedAnyway = true;
    });

    if (_result != null && _result!.label != 'Healthy') {
      setState(() => _isLoadingTreatment = true);
      await _fetchTreatment(_result!);
    }
    await _saveScanToFirebase();
  }

  String get _reminderPlantName {
    if (widget.historyScan != null) return widget.historyScan!.predictedDisease;
    if (_result != null) return _result!.label;
    return 'Tomato';
  }

  String? get _reminderPlantImageUrl {
    if (_isHistory) return widget.historyScan?.imageUrl;
    return widget.preloadedRemoteImageUrl;
  }

  Future<void> _showReminderCategorySheet() async {
    if (FirebaseAuth.instance.currentUser == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please sign in to add reminders.',
            style: GoogleFonts.spaceGrotesk(),
          ),
        ),
      );
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final categories = [
      ReminderCategory.watering,
      ReminderCategory.fertilize,
      ReminderCategory.checkSoil,
      ReminderCategory.supportStems,
      ReminderCategory.other,
    ];

    final picked = await showModalBottomSheet<ReminderCategory>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isFilipino ? 'Magdagdag ng Paalala' : 'Add Reminder',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isFilipino
                  ? 'Anong uri ng paalala ang gusto mong itakda para sa iyong kamatis?'
                  : 'Which type of reminder would you like to set for your tomato plant?',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 14,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            ...categories.map(
              (category) => ListTile(
                onTap: () => Navigator.pop(ctx, category),
                leading: Icon(category.icon, color: const Color(0xFF309249)),
                title: Text(
                  category.label,
                  style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                subtitle: Text(
                  _isFilipino
                      ? 'Mag-set ng ${category.label.toLowerCase()} na paalala'
                      : 'Set a ${category.label.toLowerCase()} reminder',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (picked == null || !mounted) return;

    await showReminderEditorSheet(
      context: context,
      category: picked,
      initialPlantName: _reminderPlantName,
      initialPlantImageUrl: _reminderPlantImageUrl,
    );
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
        disease2: _result!.secondLabel,
        confidenceScore: _result!.confidence,
        secondConfidence: _result!.secondConfidence,
        confidenceLabel: _result!.confidenceLabel,
        thresholdState: _result!.thresholdState,
        scanType: 'diagnose',
        gpsCoordinates: gpsCoordinates,
        treatmentSteps: _treatmentSteps,
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

  // ── Heatmap (on-device occlusion sensitivity) ──
  Future<void> _toggleGradCam() async {
    if (_showGradCam) {
      setState(() => _showGradCam = false);
      return;
    }
    if (_heatmapBytes != null) {
      setState(() => _showGradCam = true);
      return;
    }

    String? imagePath = widget.imagePath ?? widget.preloadedLocalImagePath;
    if (imagePath == null || _result == null) return;

    setState(() => _isLoadingGradCam = true);
    try {
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

  // ── Translation ──
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
      'How to Treat',
      'Identified via Identify, diagnosed via AI',
      'Great news! No treatment needed.',
      'Your plant looks healthy. Here are some tips to keep it that way:',
      ..._treatmentSteps ?? [],
    ];

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
        localImagePath: widget.imagePath ?? widget.preloadedLocalImagePath,
        remoteImageUrl: _savedImageUrl ??
            widget.historyScan?.imageUrl ??
            widget.preloadedRemoteImageUrl,
        gpsCoordinates: _savedGpsCoordinates ?? widget.historyScan?.gpsCoordinates,
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
          if (_isContributionUploading || _contributionStatusMessage != null) ...[
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
                      : (_contributionStatusMessage?.startsWith('Contribution uploaded') ??
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
                      backgroundColor: const Color(0xFF309249).withOpacity(0.12),
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

  // Healthy care tips
  static const _healthyCareTips = [
    'Water your tomato plants deeply but infrequently, keeping the soil consistently moist.',
    'Ensure your plants get 6-8 hours of sunlight daily for optimal growth.',
    'Apply balanced fertilizer every 2-3 weeks during the growing season.',
    'Prune suckers regularly to improve airflow and prevent disease.',
    'Monitor for pests like aphids and whiteflies — early detection is key.',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F0);
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    // Improvement 9: Not Tomato retake screen
    if (!_isDetecting && _result != null && _result!.label == 'Not_Tomato' &&
        !_isHistory && !_isPreloaded) {
      return _buildNotTomatoScreen(isDark);
    }

    // Improvement 8: Low confidence retake
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
          "Diagnosis Results",
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          // Translation toggle
          if (!_isDetecting && _result != null && _result!.label != 'Not_Tomato')
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
            // Low confidence warning banner
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

            // Translation loading
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
                // GradCAM toggle button
                if (!_isDetecting && _result != null &&
                    (widget.imagePath != null || widget.preloadedLocalImagePath != null) &&
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

            // GradCAM label
            if (_showGradCam && _heatmapBytes != null)
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

            // ── Detection + Treatment Results ──
            if (!_isDetecting && _result != null)
              FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Threshold tier strip (Steps 5-8)
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
                          Flexible(
                            child: Text(
                              "${_t(TFLiteService.getThresholdTitle(_result!.label, _result!.confidence))}  \u2022  ${_result!.confidencePercent}",
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: TFLiteService.getThresholdColor(
                                    _result!.label, _result!.confidence),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Upgraded from Identify note
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
                                  _t("Identified via Identify, diagnosed via AI"),
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

                    // ── Healthy: Care tips instead of treatment (Improvement 6) ──
                    if (_result!.label == 'Healthy')
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(isDark ? 0.4 : 0.08),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  const Icon(Icons.eco,
                                      color: Color(0xFF4CAF50), size: 48),
                                  const SizedBox(height: 12),
                                  Text(
                                    _t("Great news! No treatment needed."),
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF4CAF50),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _t("Your plant looks healthy. Here are some tips to keep it that way:"),
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 14,
                                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                                      height: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  ...List.generate(
                                    _healthyCareTips.length,
                                    (i) => _buildTreatmentStep(
                                      i + 1,
                                      _healthyCareTips[i],
                                      isDark,
                                      isLast: i == _healthyCareTips.length - 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    // ── How to Treat Section (disease detected) ──
                    if (_result!.label != 'Healthy' && _result!.label != 'Not_Tomato')
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // --- Added Disease Description and Symptoms ---
                            if (_result!.label == 'Early_Blight' || _result!.label == 'Leaf_Miner' || _result!.label == 'Leaf_Mold') ...[
                              Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: const Color(0xFF309249),
                                    size: 24,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    _isFilipino ? "Tungkol sa Sakit" : "About the Disease",
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(isDark ? 0.4 : 0.08),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _isFilipino ? "Paglalarawan" : "Description",
                                      style: GoogleFonts.spaceGrotesk(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _getDiseaseInfo(_result!.label, _isFilipino)['description']!,
                                      style: GoogleFonts.spaceGrotesk(
                                        fontSize: 14,
                                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                                        height: 1.5,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _isFilipino ? "Mga Sintomas" : "Symptoms",
                                      style: GoogleFonts.spaceGrotesk(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _getDiseaseInfo(_result!.label, _isFilipino)['symptoms']!,
                                      style: GoogleFonts.spaceGrotesk(
                                        fontSize: 14,
                                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 32),
                            ],
                            // ----------------------------------------------

                            Row(
                              children: [
                                Icon(
                                  Icons.healing,
                                  color: const Color(0xFF309249),
                                  size: 24,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _t("How to Treat"),
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
                                            _t(entry.value),
                                            isDark,
                                            isLast: entry.key ==
                                                _treatmentSteps!.length - 1,
                                          ))
                                      .toList(),
                                ),
                              ),
                            const SizedBox(height: 20),
                            _buildReminderCta(isDark),
                          ],
                        ),
                      ),

                    _buildRatingAndContributionSection(isDark),

                    // ── Disease Carousel (Improvement 1) ──
                    if (_result!.label != 'Not_Tomato')
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

  // ── Not Tomato retake screen ──
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
        title: Text("Scan Result",
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
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
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _onRetakePhoto,
                        icon: const Icon(Icons.camera_alt, size: 18),
                        label: Text("Retake Photo",
                            style: GoogleFonts.spaceGrotesk(
                                fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF309249),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.image, size: 18),
                        label: Text("Gallery",
                            style: GoogleFonts.spaceGrotesk(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF309249),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
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

  // ── Low Confidence retake screen ──
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
        title: Text("Scan Result",
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
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
                  "We're not confident about this result.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Confidence: $confPercent% \u2014 This is too low for a reliable diagnosis.",
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
                    color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("For best results:",
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.black87,
                          )),
                      const SizedBox(height: 8),
                      _buildBullet("Take the photo in natural outdoor lighting", isDark),
                      _buildBullet("Get close to the affected leaf (15\u201330 cm)", isDark),
                      _buildBullet("Make sure the leaf fills the camera box", isDark),
                      _buildBullet("Avoid blurry or shaded images", isDark),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _onRetakePhoto,
                    icon: const Icon(Icons.camera_alt, size: 18),
                    label: Text("Retake Photo",
                        style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF309249),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _onContinueAnyway,
                    child: Text("Continue Anyway \u2192",
                        style: GoogleFonts.spaceGrotesk(
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          fontWeight: FontWeight.w600,
                        )),
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
          Text("\u2022  ",
              style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  fontSize: 14)),
          Expanded(
            child: Text(text,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 13,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  height: 1.4,
                )),
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

  Widget _buildTreatmentStep(
    int number,
    String step,
    bool isDark, {
    bool isLast = false,
  }) {
    String cleanStep = step.replaceFirst(RegExp(r'^\d+[\.\)]\s*'), '');
    final baseStyle = GoogleFonts.spaceGrotesk(
      fontSize: 15,
      color: isDark ? Colors.white.withOpacity(0.9) : Colors.black87,
      height: 1.5,
    );

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
              child: RichText(
                text: TextSpan(
                  style: baseStyle,
                  children: _buildMarkdownBoldSpans(cleanStep, baseStyle),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<TextSpan> _buildMarkdownBoldSpans(String text, TextStyle baseStyle) {
    final matches = RegExp(r'\*\*(.+?)\*\*').allMatches(text);
    if (matches.isEmpty) {
      return [TextSpan(text: text)];
    }

    final spans = <TextSpan>[];
    var currentIndex = 0;

    for (final match in matches) {
      if (match.start > currentIndex) {
        spans.add(TextSpan(text: text.substring(currentIndex, match.start)));
      }

      spans.add(
        TextSpan(
          text: match.group(1) ?? '',
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ),
      );

      currentIndex = match.end;
    }

    if (currentIndex < text.length) {
      spans.add(TextSpan(text: text.substring(currentIndex)));
    }

    return spans;
  }

  Widget _buildReminderCta(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active, color: Color(0xFF309249)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _isFilipino
                      ? 'Magtakda ng paalala sa pag-aalaga'
                      : 'Set a care reminder',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _isFilipino
                ? 'Magdagdag ng reminder para sa pagdidilig, pagpapataba, o pag-check ng lupa habang ginagamot ang iyong halaman.'
                : 'Add a reminder for watering, fertilizing, or checking the soil while you treat your plant.',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showReminderCategorySheet,
              icon: const Icon(Icons.add_alert_rounded),
              label: Text(
                _isFilipino ? 'Magdagdag ng Paalala' : 'Add Reminder',
                style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF309249),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, String> _getDiseaseInfo(String label, bool isFilipino) {
    switch (label) {
      case 'Early_Blight':
        return {
          'description': isFilipino
              ? "Isang karaniwang sakit na dala ng fungus na Alternaria solani."
              : "A common fungal disease caused by Alternaria solani.",
          'symptoms': isFilipino
              ? "Maiitim at pabilog na batik sa mga lumang dahon, paninilaw ng paligid ng batik, at maagang pagkalagas ng dahon."
              : "Dark, concentric rings or bullseye spots on older leaves, yellowing of surrounding tissue, and premature leaf drop."
        };
      case 'Leaf_Miner':
        return {
          'description': isFilipino
              ? "Pinsala na dulot ng uod ng insekto na naninirahan at kumakain sa loob ng dahon."
              : "Damage caused by insect larvae living and feeding inside the leaf tissue.",
          'symptoms': isFilipino
              ? "Puti o abuhin na paliku-likong linya o tunnel (mines) sa mga dahon."
              : "White or grayish winding trails or tunnels (mines) on the leaves."
        };
      case 'Leaf_Mold':
        return {
          'description': isFilipino
              ? "Isang sakit na dala ng fungus na Passalora fulva, karaniwan sa mga lugar na mataas ang halumigmig."
              : "A fungal disease caused by Passalora fulva, common in high humidity.",
          'symptoms': isFilipino
              ? "Maputlang berde o dilaw na batik sa ibabaw ng dahon, at may tila pelus na amag na kulay olive-green hanggang kayumanggi sa ilalim."
              : "Pale green or yellow spots on the upper leaf surface, with olive-green to brown velvety mold on the underside."
        };
      default:
        return {
          'description': "",
          'symptoms': ""
        };
    }
  }

}
