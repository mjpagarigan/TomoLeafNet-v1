import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/services/leaf_detector_service.dart';
import 'diagnose_result_screen.dart';
import 'identify_result_screen.dart';
import 'widgets/guided_onboarding_tutorial.dart';
import 'widgets/tomo_ui.dart';

class CameraScreen extends StatefulWidget {
  final String scanType;

  const CameraScreen({super.key, required this.scanType});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  FlashMode _flashMode = FlashMode.off;
  bool _isProcessing = false;
  bool _isDetectorReady = false;
  bool _isProcessingFrame = false;
  bool _streamRunning = false;
  bool _isAppActive = true;
  bool _isFilipino = false;
  bool _isTutorialVisible = false;
  int _tutorialStepIndex = 0;

  final LeafDetectorService _leafDetectorService = LeafDetectorService();
  DetectionResult? _detectionResult;
  Timer? _detectionTimer;
  CameraImage? _latestFrame;

  // Temporal smoothing: require 3-of-5 recent frames to agree on "tomato_leaf"
  // before showing the green indicator. Prevents transient false positives.
  static const int _smoothingWindowSize = 5;
  static const int _smoothingThreshold = 3;
  final List<bool> _recentDetections = [];
  final GlobalKey _modeTutorialKey = GlobalKey(debugLabel: 'camera-mode-pill');
  final GlobalKey _statusTutorialKey =
      GlobalKey(debugLabel: 'camera-status-card');
  final GlobalKey _galleryTutorialKey =
      GlobalKey(debugLabel: 'camera-gallery-button');
  final GlobalKey _captureTutorialKey =
      GlobalKey(debugLabel: 'camera-capture-button');
  final GlobalKey _flashTutorialKey =
      GlobalKey(debugLabel: 'camera-flash-button');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLanguagePreference();
    _initializeCamera();
    _loadDetectorModel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detectionTimer?.cancel();
    _leafDetectorService.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isAppActive = true;
      _maybeStartDetection();
      return;
    }

    _isAppActive = false;
    _stopImageStream();
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _isFilipino = prefs.getBool('preferFilipino') ?? false;
    });
  }

  Future<void> _loadDetectorModel() async {
    try {
      await _leafDetectorService.loadModel();
      if (!mounted) return;

      setState(() => _isDetectorReady = true);
      _maybeStartDetection();
    } catch (e) {
      debugPrint("Leaf detector load error: $e");
    }
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      debugPrint("No cameras found");
      return;
    }
    final camera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first);

    _controller = CameraController(
      camera,
      ResolutionPreset.medium, // Use medium for faster stream processing
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _controller!.initialize();
      await _controller!.setFlashMode(FlashMode.off);
      if (mounted) {
        setState(() {
          _flashMode = FlashMode.off;
          _isCameraInitialized = true;
        });
        _maybeStartDetection();
      }
    } catch (e) {
      debugPrint("Camera initialization error: $e");
    }
  }

  Future<void> _maybeStartDetection() async {
    if (!_isAppActive ||
        _isProcessing ||
        !_isDetectorReady ||
        !_isCameraInitialized ||
        _controller == null ||
        !_controller!.value.isInitialized ||
        _streamRunning) {
      return;
    }

    await _startImageStream();
  }

  Future<void> _startImageStream() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _streamRunning ||
        _isProcessing) {
      return;
    }

    try {
      await _controller!.startImageStream((CameraImage cameraImage) {
        if (!_isDetectorReady || _isProcessing || _isProcessingFrame) return;

        _latestFrame = cameraImage;
        _detectionTimer ??= Timer(
          const Duration(milliseconds: 500),
          () {
            _detectionTimer = null;
            final frame = _latestFrame;
            if (frame != null) {
              _processFrame(frame);
            }
          },
        );
      });
      _streamRunning = true;
    } catch (e) {
      debugPrint("Image stream start error: $e");
    }
  }

  Future<void> _stopImageStream() async {
    _detectionTimer?.cancel();
    _detectionTimer = null;
    _latestFrame = null;
    _recentDetections.clear();

    if (!_streamRunning) {
      return;
    }

    try {
      await _controller?.stopImageStream();
    } catch (_) {
      // Ignore repeated stop requests from lifecycle transitions.
    } finally {
      _streamRunning = false;
    }
  }

  Future<void> _processFrame(CameraImage cameraImage) async {
    if (_isProcessingFrame || !_isDetectorReady || !_isAppActive) {
      return;
    }

    _isProcessingFrame = true;
    try {
      final result = await _leafDetectorService.detect(cameraImage);
      if (!mounted || _isProcessing) return;

      // Temporal smoothing: track recent frame results
      _recentDetections.add(result.isTomatoLeaf);
      if (_recentDetections.length > _smoothingWindowSize) {
        _recentDetections.removeAt(0);
      }
      final positiveCount = _recentDetections.where((d) => d).length;
      final smoothedIsTomato = positiveCount >= _smoothingThreshold;

      // Build a smoothed result that reflects the temporal consensus
      final smoothedResult = DetectionResult(
        label: smoothedIsTomato
            ? LeafDetectorService.tomatoLeafLabel
            : LeafDetectorService.notTomatoLeafLabel,
        confidence: result.confidence,
      );

      final previous = _detectionResult;
      final shouldUpdate = previous == null ||
          previous.label != smoothedResult.label ||
          (previous.confidence - smoothedResult.confidence).abs() >= 0.05;

      if (shouldUpdate) {
        setState(() {
          _detectionResult = smoothedResult;
        });
      }
    } catch (e) {
      debugPrint("Frame processing error: $e");
    } finally {
      _isProcessingFrame = false;
    }
  }

  Future<void> _tearDownCameraResources() async {
    _detectionTimer?.cancel();
    _detectionTimer = null;
    _latestFrame = null;
    _detectionResult = null;
    _streamRunning = false;
    _isProcessingFrame = false;

    try {
      await _controller?.stopImageStream();
    } catch (_) {}

    _leafDetectorService.dispose();
    await _controller?.dispose();
    _controller = null;

    if (mounted) {
      setState(() {
        _isCameraInitialized = false;
        _isDetectorReady = false;
      });
    } else {
      _isCameraInitialized = false;
      _isDetectorReady = false;
    }
  }

  bool get _isTomatoLeafDetected => _detectionResult?.isTomatoLeaf ?? false;

  Color get _viewfinderColor =>
      _isTomatoLeafDetected ? const Color(0xFF4CAF50) : const Color(0xFFE53935);

  String get _statusTitle {
    if (_isTomatoLeafDetected) {
      return _isFilipino
          ? "Natukoy ang dahon ng kamatis!"
          : "Tomato leaf detected!";
    }

    return _isFilipino
        ? "Ituro ang kamera sa dahon ng kamatis."
        : "Point the camera at a tomato leaf.";
  }

  String get _statusSubtitle {
    if (_isTomatoLeafDetected) {
      final confidence = _detectionResult == null
          ? ""
          : " ${(_detectionResult!.confidence * 100).toStringAsFixed(1)}%";
      return _isFilipino
          ? "Handa nang kumuha.$confidence"
          : "Ready to capture.$confidence";
    }

    return _isFilipino
        ? "Tagapagpahiwatig lamang ito. Maaari ka pa ring kumuha ng larawan."
        : "This is only an indicator. You can still capture a photo.";
  }

  void _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    FlashMode next;
    switch (_flashMode) {
      case FlashMode.off:
        next = FlashMode.torch;
        break;
      case FlashMode.torch:
        next = FlashMode.auto;
        break;
      case FlashMode.auto:
        next = FlashMode.off;
        break;
      default:
        next = FlashMode.off;
    }

    try {
      await _controller!.setFlashMode(next);
      if (mounted) {
        setState(() => _flashMode = next);
      }
    } catch (e) {
      debugPrint("Flash mode error: $e");
    }
  }

  IconData _getFlashIcon() {
    switch (_flashMode) {
      case FlashMode.off:
        return Icons.flash_off;
      case FlashMode.torch:
        return Icons.flash_on;
      case FlashMode.auto:
        return Icons.flash_auto;
      default:
        return Icons.flash_off;
    }
  }

  Future<String?> _openCropper(String imagePath) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _CropScreen(
          imagePath: imagePath,
          isFilipino: _isFilipino,
        ),
      ),
    );
    return result;
  }

  Future<void> _navigateToResult(String imagePath) async {
    final Widget resultScreen;
    if (widget.scanType == 'diagnose') {
      resultScreen = DiagnoseResultScreen(imagePath: imagePath);
    } else {
      resultScreen = IdentifyResultScreen(imagePath: imagePath);
    }

    await _tearDownCameraResources();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => resultScreen),
    );

    if (mounted) {
      await _loadDetectorModel();
      await _initializeCamera();
    }
  }

  Future<void> _handleCaptureTap() async {
    if (_isProcessing) return;
    await _takePicture();
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isProcessing) return;

    bool navigated = false;

    try {
      setState(() => _isProcessing = true);
      await _stopImageStream();
      await _controller!.setFlashMode(_flashMode);
      final image = await _controller!.takePicture();

      if (!mounted) return;
      setState(() => _isProcessing = false);

      // Open interactive cropper — user can frame the leaf precisely
      final croppedPath = await _openCropper(image.path);
      if (croppedPath == null || !mounted) return;

      navigated = true;
      await _navigateToResult(croppedPath);
    } catch (e) {
      debugPrint("Error taking picture: $e");
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    } finally {
      if (!navigated && mounted) {
        setState(() => _isProcessing = false);
        _maybeStartDetection();
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isProcessing) return;

    bool navigated = false;
    final picker = ImagePicker();

    try {
      setState(() => _isProcessing = true);
      await _stopImageStream();

      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null || !mounted) {
        return;
      }

      if (!mounted) return;
      setState(() => _isProcessing = false);

      // Open interactive cropper — user can frame the leaf precisely
      final croppedPath = await _openCropper(pickedFile.path);
      if (croppedPath == null || !mounted) return;

      navigated = true;
      await _navigateToResult(croppedPath);
    } finally {
      if (!navigated && mounted) {
        setState(() => _isProcessing = false);
        _maybeStartDetection();
      }
    }
  }

  Future<void> _showTutorial() async {
    if (!mounted) return;
    setState(() {
      _tutorialStepIndex = 0;
      _isTutorialVisible = true;
    });
  }

  List<TutorialStepData> _buildCameraTutorialSteps() {
    return [
      TutorialStepData(
        targetKey: _modeTutorialKey,
        pageIndex: 0,
        icon: widget.scanType == 'identify' ? Icons.search : Icons.healing,
        title:
            widget.scanType == 'identify' ? 'Identify mode' : 'Diagnose mode',
        description: widget.scanType == 'identify'
            ? 'Use Identify for a quick result when you want to know what the leaf likely is.'
            : 'Use Diagnose when you want the full disease result with guide details and next-step help.',
        preferredPlacement: TutorialCardPlacement.below,
      ),
      TutorialStepData(
        targetKey: _statusTutorialKey,
        pageIndex: 0,
        icon: Icons.center_focus_strong,
        title: 'Watch the capture guide',
        description:
            'Keep the tomato leaf inside the frame. The message below tells you when the camera likely sees a tomato leaf clearly.',
        preferredPlacement: TutorialCardPlacement.above,
      ),
      TutorialStepData(
        targetKey: _galleryTutorialKey,
        pageIndex: 0,
        icon: Icons.photo_library_outlined,
        title: 'Pick from gallery',
        description:
            'Tap here if you already have a leaf photo saved on your phone and want to scan it instead of taking a new one.',
        preferredPlacement: TutorialCardPlacement.above,
      ),
      TutorialStepData(
        targetKey: _captureTutorialKey,
        pageIndex: 0,
        icon: Icons.camera_alt_rounded,
        title: 'Capture the leaf',
        description:
            'Tap the green camera button to take the photo. The app will crop it and open the result screen right after capture.',
        preferredPlacement: TutorialCardPlacement.above,
      ),
      TutorialStepData(
        targetKey: _flashTutorialKey,
        pageIndex: 0,
        icon: Icons.flash_on,
        title: 'Adjust the flash',
        description:
            'Use this button if the leaf is too dark. You can switch between flash off, torch, and auto depending on the lighting.',
        preferredPlacement: TutorialCardPlacement.above,
      ),
    ];
  }

  void _goToTutorialStep(int index) {
    final steps = _buildCameraTutorialSteps();
    if (steps.isEmpty) return;
    setState(() {
      _tutorialStepIndex = index.clamp(0, steps.length - 1);
    });
  }

  void _closeTutorial() {
    if (!mounted) return;
    setState(() => _isTutorialVisible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body:
            Center(child: CircularProgressIndicator(color: Color(0xFF3CB45A))),
      );
    }

    final isIdentify = widget.scanType == 'identify';
    final modeColor =
        isIdentify ? TomoPalette.primary : const Color(0xFF78909C);
    final modeLabel = isIdentify ? "Identify Mode" : "Diagnose Mode";

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Camera Preview (Full Screen)
          SizedBox(
            height: MediaQuery.of(context).size.height,
            width: MediaQuery.of(context).size.width,
            child: CameraPreview(_controller!),
          ),

          // 2. Square viewfinder overlay with dynamic color
          CustomPaint(
            size: Size.infinite,
            painter: SquareViewfinderPainter(cornerColor: _viewfinderColor),
          ),

          // 3. Processing overlay
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF4CAF50)),
                    const SizedBox(height: 16),
                    Text(
                      _isFilipino ? "Pinoproseso..." : "Processing...",
                      style:
                          GoogleFonts.dmSans(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),

          // 4. UI Controls
          SafeArea(
            child: Column(
              children: [
                // Top Bar
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.white, size: 30),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Container(
                        key: _modeTutorialKey,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.12),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: modeColor,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: modeColor.withOpacity(0.6),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              modeLabel,
                              style: GoogleFonts.dmSans(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(56),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                        child: IconButton(
                          tooltip: 'Tutorial',
                          onPressed: _showTutorial,
                          icon: const Icon(
                            Icons.info_outline,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Detection status label
                AnimatedContainer(
                  key: _statusTutorialKey,
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 15),
                  decoration: BoxDecoration(
                    color: _viewfinderColor.withAlpha(40),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _viewfinderColor.withAlpha(120)),
                    boxShadow: [
                      BoxShadow(
                        color: _viewfinderColor.withOpacity(0.18),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isTomatoLeafDetected
                            ? Icons.check_circle
                            : Icons.warning_rounded,
                        color: _viewfinderColor,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _statusTitle,
                              style: GoogleFonts.dmSans(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _statusSubtitle,
                              style: GoogleFonts.dmSans(
                                color: Colors.white70,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                // Bottom Controls
                Padding(
                  padding: const EdgeInsets.only(bottom: 30),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      GestureDetector(
                        key: _galleryTutorialKey,
                        onTap: _pickFromGallery,
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.1),
                            ),
                          ),
                          child: const Icon(Icons.grid_on, color: Colors.white),
                        ),
                      ),
                      GestureDetector(
                        key: _captureTutorialKey,
                        onTap: _handleCaptureTap,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 78,
                          height: 78,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const RadialGradient(
                              colors: [
                                Color(0xFF56CB74),
                                Color(0xFF2F8D4A),
                              ],
                            ),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.25),
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    const Color(0xFF3CB45A).withOpacity(0.35),
                                blurRadius: 24,
                                spreadRadius: 2,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                      GestureDetector(
                        key: _flashTutorialKey,
                        onTap: _toggleFlash,
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.1),
                            ),
                          ),
                          child: Icon(_getFlashIcon(), color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (_isTutorialVisible)
            OnboardingTutorialOverlay(
              key: ValueKey('camera-tutorial-step-$_tutorialStepIndex'),
              steps: _buildCameraTutorialSteps(),
              currentStepIndex: _tutorialStepIndex,
              onBack: _tutorialStepIndex == 0
                  ? null
                  : () => _goToTutorialStep(_tutorialStepIndex - 1),
              onNext: () {
                final lastIndex = _buildCameraTutorialSteps().length - 1;
                if (_tutorialStepIndex >= lastIndex) {
                  _closeTutorial();
                } else {
                  _goToTutorialStep(_tutorialStepIndex + 1);
                }
              },
              onSkip: _closeTutorial,
            ),
        ],
      ),
    );
  }
}

/// Custom painter that draws a centered square viewfinder with a dark
/// semi-transparent overlay outside the box and colored rounded corners.
class SquareViewfinderPainter extends CustomPainter {
  final Color cornerColor;

  SquareViewfinderPainter({this.cornerColor = const Color(0xFF4CAF50)});

  @override
  void paint(Canvas canvas, Size size) {
    final double boxSize = size.width * LeafDetectorService.viewfinderFraction;
    final double left = (size.width - boxSize) / 2;
    final double top = (size.height - boxSize) / 2 -
        LeafDetectorService.viewfinderVerticalOffset;
    final Rect boxRect = Rect.fromLTWH(left, top, boxSize, boxSize);

    // Draw the dark overlay outside the box
    final overlayPaint = Paint()
      ..color = Colors.black.withAlpha(153) // 0.60 opacity
      ..style = PaintingStyle.fill;

    // Create a path covering everything except the box
    final overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(boxRect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(overlayPath, overlayPaint);

    // Draw the colored rounded corner brackets
    final cornerPaint = Paint()
      ..color = cornerColor
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const double cornerLength = 40.0;
    const double r = 16.0; // corner radius

    // Top Left
    final topLeftPath = Path()
      ..moveTo(left, top + cornerLength)
      ..lineTo(left, top + r)
      ..quadraticBezierTo(left, top, left + r, top)
      ..lineTo(left + cornerLength, top);
    canvas.drawPath(topLeftPath, cornerPaint);

    // Top Right
    final topRightPath = Path()
      ..moveTo(left + boxSize - cornerLength, top)
      ..lineTo(left + boxSize - r, top)
      ..quadraticBezierTo(left + boxSize, top, left + boxSize, top + r)
      ..lineTo(left + boxSize, top + cornerLength);
    canvas.drawPath(topRightPath, cornerPaint);

    // Bottom Right
    final bottomRightPath = Path()
      ..moveTo(left + boxSize, top + boxSize - cornerLength)
      ..lineTo(left + boxSize, top + boxSize - r)
      ..quadraticBezierTo(
          left + boxSize, top + boxSize, left + boxSize - r, top + boxSize)
      ..lineTo(left + boxSize - cornerLength, top + boxSize);
    canvas.drawPath(bottomRightPath, cornerPaint);

    // Bottom Left
    final bottomLeftPath = Path()
      ..moveTo(left + cornerLength, top + boxSize)
      ..lineTo(left + r, top + boxSize)
      ..quadraticBezierTo(left, top + boxSize, left, top + boxSize - r)
      ..lineTo(left, top + boxSize - cornerLength);
    canvas.drawPath(bottomLeftPath, cornerPaint);
  }

  @override
  bool shouldRepaint(covariant SquareViewfinderPainter oldDelegate) =>
      oldDelegate.cornerColor != cornerColor;
}

// ─────────────────────────────────────────────────────────────────────
// Flutter-native crop screen with draggable 1:1 crop box.
// Drag the box center to move, drag corners to resize (stays square).
// ─────────────────────────────────────────────────────────────────────

class _CropScreen extends StatefulWidget {
  final String imagePath;
  final bool isFilipino;

  const _CropScreen({required this.imagePath, required this.isFilipino});

  @override
  State<_CropScreen> createState() => _CropScreenState();
}

enum _CropPreset { fit, full }

class _CropScreenState extends State<_CropScreen> {
  bool _isCropping = false;
  bool _isSquareMode = false;
  bool _showGrid = true;
  Size? _sourceImageSize;
  Rect _imageRect = Rect.zero;
  Rect _cropRect = Rect.zero;

  static const double _minCropWidth = 96;
  static const double _minCropHeight = 96;
  static const double _handleTouchSize = 44;

  @override
  void initState() {
    super.initState();
    _loadImageSize();
  }

  Future<void> _loadImageSize() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (!mounted || decoded == null) return;
      setState(() {
        _sourceImageSize = Size(
          decoded.width.toDouble(),
          decoded.height.toDouble(),
        );
      });
    } catch (e) {
      debugPrint('Crop image decode error: $e');
      if (!mounted) return;
      setState(() {
        _sourceImageSize = const Size(1, 1);
      });
    }
  }

  Rect _containRect(Size viewport, Size source) {
    final sourceAspect = source.width / source.height;
    final viewAspect = viewport.width / viewport.height;

    if (sourceAspect > viewAspect) {
      final width = viewport.width;
      final height = width / sourceAspect;
      return Rect.fromLTWH(0, (viewport.height - height) / 2, width, height);
    }

    final height = viewport.height;
    final width = height * sourceAspect;
    return Rect.fromLTWH((viewport.width - width) / 2, 0, width, height);
  }

  void _syncImageRect(Size viewport) {
    final source = _sourceImageSize;
    if (source == null || viewport.isEmpty) return;

    final nextRect = _containRect(viewport, source);
    final changed = (_imageRect.left - nextRect.left).abs() > 0.5 ||
        (_imageRect.top - nextRect.top).abs() > 0.5 ||
        (_imageRect.width - nextRect.width).abs() > 0.5 ||
        (_imageRect.height - nextRect.height).abs() > 0.5;

    if (!changed) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _imageRect = nextRect;
        _cropRect = _defaultCropRect(_CropPreset.fit);
      });
    });
  }

  Rect _defaultCropRect(_CropPreset preset) {
    if (_imageRect == Rect.zero) return Rect.zero;

    if (_isSquareMode) {
      final availableWidth = preset == _CropPreset.full
          ? _imageRect.width - 16
          : _imageRect.width * 0.82;
      final availableHeight = preset == _CropPreset.full
          ? _imageRect.height - 16
          : _imageRect.height * 0.82;
      final side =
          availableWidth < availableHeight ? availableWidth : availableHeight;
      return _clampCropRect(
        Rect.fromCenter(
          center: _imageRect.center,
          width: side,
          height: side,
        ),
      );
    }

    if (preset == _CropPreset.full) {
      return _clampCropRect(
        Rect.fromLTWH(
          _imageRect.left + 8,
          _imageRect.top + 8,
          _imageRect.width - 16,
          _imageRect.height - 16,
        ),
      );
    }

    return _clampCropRect(
      Rect.fromLTWH(
        _imageRect.left + (_imageRect.width * 0.08),
        _imageRect.top + (_imageRect.height * 0.08),
        _imageRect.width * 0.84,
        _imageRect.height * 0.68,
      ),
    );
  }

  Rect _clampCropRect(Rect rect) {
    if (_imageRect == Rect.zero) return rect;

    double width = rect.width;
    double height = rect.height;

    if (_isSquareMode) {
      final side = width < height ? width : height;
      width = side < _minCropWidth ? _minCropWidth : side;
      height = width;
    } else {
      width = width < _minCropWidth ? _minCropWidth : width;
      height = height < _minCropHeight ? _minCropHeight : height;
    }

    if (width > _imageRect.width) width = _imageRect.width;
    if (height > _imageRect.height) height = _imageRect.height;

    double left = rect.left;
    double top = rect.top;

    if (left < _imageRect.left) left = _imageRect.left;
    if (top < _imageRect.top) top = _imageRect.top;
    if (left + width > _imageRect.right) left = _imageRect.right - width;
    if (top + height > _imageRect.bottom) top = _imageRect.bottom - height;

    return Rect.fromLTWH(left, top, width, height);
  }

  void _setPreset(_CropPreset preset) {
    if (_imageRect == Rect.zero) return;
    setState(() {
      _cropRect = _defaultCropRect(preset);
    });
  }

  void _toggleSquareMode() {
    if (_imageRect == Rect.zero) return;

    setState(() {
      _isSquareMode = !_isSquareMode;
      if (_cropRect == Rect.zero) {
        _cropRect = _defaultCropRect(_CropPreset.fit);
        return;
      }

      final center = _cropRect.center;
      if (_isSquareMode) {
        final side = _cropRect.width < _cropRect.height
            ? _cropRect.width
            : _cropRect.height;
        _cropRect = _clampCropRect(
          Rect.fromCenter(center: center, width: side, height: side),
        );
      } else {
        final width = (_cropRect.width * 1.18).clamp(
          _minCropWidth,
          _imageRect.width,
        );
        final height = (_cropRect.height * 0.82).clamp(
          _minCropHeight,
          _imageRect.height,
        );
        _cropRect = _clampCropRect(
          Rect.fromCenter(center: center, width: width, height: height),
        );
      }
    });
  }

  void _resetCrop() {
    _setPreset(_CropPreset.fit);
  }

  void _onMoveCrop(DragUpdateDetails details) {
    if (_cropRect == Rect.zero) return;
    setState(() {
      _cropRect = _clampCropRect(
        _cropRect.shift(details.delta),
      );
    });
  }

  Rect _resizeSquareFromCorner(int corner, Offset delta) {
    final rect = _cropRect;
    switch (corner) {
      case 0:
        final anchor = Offset(rect.right, rect.bottom);
        final side = (anchor.dx - (rect.left + delta.dx)).abs().clamp(
            _minCropWidth,
            _imageRect.width < _imageRect.height
                ? _imageRect.width
                : _imageRect.height);
        return Rect.fromLTWH(anchor.dx - side, anchor.dy - side, side, side);
      case 1:
        final anchor = Offset(rect.left, rect.bottom);
        final side = ((rect.right + delta.dx) - anchor.dx).abs().clamp(
            _minCropWidth,
            _imageRect.width < _imageRect.height
                ? _imageRect.width
                : _imageRect.height);
        return Rect.fromLTWH(anchor.dx, anchor.dy - side, side, side);
      case 2:
        final anchor = Offset(rect.left, rect.top);
        final side = ((rect.right + delta.dx) - anchor.dx).abs().clamp(
            _minCropWidth,
            _imageRect.width < _imageRect.height
                ? _imageRect.width
                : _imageRect.height);
        return Rect.fromLTWH(anchor.dx, anchor.dy, side, side);
      default:
        final anchor = Offset(rect.right, rect.top);
        final side = (anchor.dx - (rect.left + delta.dx)).abs().clamp(
            _minCropWidth,
            _imageRect.width < _imageRect.height
                ? _imageRect.width
                : _imageRect.height);
        return Rect.fromLTWH(anchor.dx - side, anchor.dy, side, side);
    }
  }

  void _onCornerDrag(int corner, DragUpdateDetails details) {
    if (_cropRect == Rect.zero) return;

    setState(() {
      if (_isSquareMode) {
        _cropRect = _clampCropRect(
          _resizeSquareFromCorner(corner, details.delta),
        );
        return;
      }

      Rect next = _cropRect;
      switch (corner) {
        case 0:
          next = Rect.fromLTRB(
            next.left + details.delta.dx,
            next.top + details.delta.dy,
            next.right,
            next.bottom,
          );
          break;
        case 1:
          next = Rect.fromLTRB(
            next.left,
            next.top + details.delta.dy,
            next.right + details.delta.dx,
            next.bottom,
          );
          break;
        case 2:
          next = Rect.fromLTRB(
            next.left,
            next.top,
            next.right + details.delta.dx,
            next.bottom + details.delta.dy,
          );
          break;
        case 3:
          next = Rect.fromLTRB(
            next.left + details.delta.dx,
            next.top,
            next.right,
            next.bottom + details.delta.dy,
          );
          break;
      }
      _cropRect = _clampCropRect(next);
    });
  }

  void _onEdgeDrag(int edge, DragUpdateDetails details) {
    if (_cropRect == Rect.zero) return;

    setState(() {
      if (_isSquareMode) {
        final rect = _cropRect;
        switch (edge) {
          case 0:
            final anchorBottom = rect.bottom;
            final side = (anchorBottom - (rect.top + details.delta.dy))
                .abs()
                .clamp(
                    _minCropWidth,
                    _imageRect.width < _imageRect.height
                        ? _imageRect.width
                        : _imageRect.height);
            _cropRect = _clampCropRect(
              Rect.fromCenter(
                center: Offset(rect.center.dx, anchorBottom - side / 2),
                width: side,
                height: side,
              ),
            );
            break;
          case 1:
            final anchorLeft = rect.left;
            final side = ((rect.right + details.delta.dx) - anchorLeft)
                .abs()
                .clamp(
                    _minCropWidth,
                    _imageRect.width < _imageRect.height
                        ? _imageRect.width
                        : _imageRect.height);
            _cropRect = _clampCropRect(
              Rect.fromCenter(
                center: Offset(anchorLeft + side / 2, rect.center.dy),
                width: side,
                height: side,
              ),
            );
            break;
          case 2:
            final anchorTop = rect.top;
            final side = ((rect.bottom + details.delta.dy) - anchorTop)
                .abs()
                .clamp(
                    _minCropWidth,
                    _imageRect.width < _imageRect.height
                        ? _imageRect.width
                        : _imageRect.height);
            _cropRect = _clampCropRect(
              Rect.fromCenter(
                center: Offset(rect.center.dx, anchorTop + side / 2),
                width: side,
                height: side,
              ),
            );
            break;
          case 3:
            final anchorRight = rect.right;
            final side = (anchorRight - (rect.left + details.delta.dx))
                .abs()
                .clamp(
                    _minCropWidth,
                    _imageRect.width < _imageRect.height
                        ? _imageRect.width
                        : _imageRect.height);
            _cropRect = _clampCropRect(
              Rect.fromCenter(
                center: Offset(anchorRight - side / 2, rect.center.dy),
                width: side,
                height: side,
              ),
            );
            break;
        }
        return;
      }

      Rect next = _cropRect;
      switch (edge) {
        case 0:
          next = Rect.fromLTRB(
            next.left,
            next.top + details.delta.dy,
            next.right,
            next.bottom,
          );
          break;
        case 1:
          next = Rect.fromLTRB(
            next.left,
            next.top,
            next.right + details.delta.dx,
            next.bottom,
          );
          break;
        case 2:
          next = Rect.fromLTRB(
            next.left,
            next.top,
            next.right,
            next.bottom + details.delta.dy,
          );
          break;
        case 3:
          next = Rect.fromLTRB(
            next.left + details.delta.dx,
            next.top,
            next.right,
            next.bottom,
          );
          break;
      }
      _cropRect = _clampCropRect(next);
    });
  }

  String _buildCroppedPath() {
    final lastDot = widget.imagePath.lastIndexOf('.');
    if (lastDot <= 0) {
      return '${widget.imagePath}_cropped.jpg';
    }
    final basePath = widget.imagePath.substring(0, lastDot);
    return '${basePath}_cropped.jpg';
  }

  Future<void> _cropAndReturn() async {
    if (_isCropping || _cropRect == Rect.zero || _imageRect == Rect.zero) {
      return;
    }
    setState(() => _isCropping = true);
    final navigator = Navigator.of(context);

    try {
      final normLeft = ((_cropRect.left - _imageRect.left) / _imageRect.width)
          .clamp(0.0, 1.0);
      final normTop = ((_cropRect.top - _imageRect.top) / _imageRect.height)
          .clamp(0.0, 1.0);
      final normRight = ((_cropRect.right - _imageRect.left) / _imageRect.width)
          .clamp(0.0, 1.0);
      final normBottom =
          ((_cropRect.bottom - _imageRect.top) / _imageRect.height)
              .clamp(0.0, 1.0);

      final bytes = await File(widget.imagePath).readAsBytes();
      final croppedBytes = await compute(
        _cropImageIsolate,
        _CropParams(
          imageBytes: bytes,
          left: normLeft,
          top: normTop,
          right: normRight,
          bottom: normBottom,
        ),
      );

      if (croppedBytes == null || !mounted) {
        navigator.pop(widget.imagePath);
        return;
      }

      final croppedPath = _buildCroppedPath();
      await File(croppedPath).writeAsBytes(croppedBytes);
      if (mounted) {
        navigator.pop(croppedPath);
      }
    } catch (e) {
      debugPrint('Crop error: $e');
      if (mounted) {
        navigator.pop(widget.imagePath);
      }
    }
  }

  Widget _buildCornerHandle(int corner, double left, double top) {
    return Positioned(
      left: left - (_handleTouchSize / 2),
      top: top - (_handleTouchSize / 2),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => _onCornerDrag(corner, details),
        child: const SizedBox(
          width: _handleTouchSize,
          height: _handleTouchSize,
        ),
      ),
    );
  }

  Widget _buildEdgeHandle(
    int edge, {
    required double left,
    required double top,
    required double width,
    required double height,
  }) {
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => _onEdgeDrag(edge, details),
        child: SizedBox(
          width: width,
          height: height,
        ),
      ),
    );
  }

  Widget _buildQuickAction({
    required bool isActive,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: TomoDecorations.card(
          isDark: true,
          radius: 16,
          color: isActive
              ? TomoPalette.surfaceRaised
              : Colors.white.withOpacity(0.06),
          elevated: false,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? TomoPalette.primary : Colors.white,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isActive
                    ? TomoPalette.primary
                    : Colors.white.withOpacity(0.58),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imageSize = _sourceImageSize;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              child: Row(
                children: [
                  Container(
                    decoration: TomoDecorations.pill(isDark: true),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context, null),
                      icon: const Icon(Icons.close_rounded),
                      color: Colors.white,
                      tooltip: 'Close',
                    ),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: TomoPalette.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.isFilipino
                              ? 'I-frame ang Dahon'
                              : 'Frame the Leaf',
                          style: GoogleFonts.dmSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    decoration: TomoDecorations.pill(isDark: true),
                    child: IconButton(
                      onPressed: () => setState(() => _showGrid = !_showGrid),
                      icon: Icon(
                        _showGrid
                            ? Icons.grid_on_rounded
                            : Icons.grid_off_rounded,
                      ),
                      color: Colors.white,
                      tooltip: 'Toggle grid',
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: TomoDecorations.pill(isDark: true),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.center_focus_strong_rounded,
                      size: 14,
                      color: TomoPalette.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.isFilipino
                          ? 'I-drag ang mga sulok, gilid, o mismong frame.'
                          : 'Drag the corners, edges, or the frame itself.',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (imageSize == null) {
                      return const Center(
                        child: CircularProgressIndicator(
                            color: TomoPalette.primary),
                      );
                    }

                    _syncImageRect(constraints.biggest);

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(widget.imagePath),
                            fit: BoxFit.contain,
                          ),
                        ),
                        if (_cropRect != Rect.zero) ...[
                          IgnorePointer(
                            child: CustomPaint(
                              size: constraints.biggest,
                              painter: _CropOverlayPainter(
                                cropRect: _cropRect,
                                showGrid: _showGrid,
                              ),
                            ),
                          ),
                          Positioned(
                            left: _cropRect.left,
                            top: _cropRect.top,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanUpdate: _onMoveCrop,
                              child: SizedBox(
                                width: _cropRect.width,
                                height: _cropRect.height,
                              ),
                            ),
                          ),
                          _buildCornerHandle(
                            0,
                            _cropRect.left,
                            _cropRect.top,
                          ),
                          _buildCornerHandle(
                            1,
                            _cropRect.right,
                            _cropRect.top,
                          ),
                          _buildCornerHandle(
                            2,
                            _cropRect.right,
                            _cropRect.bottom,
                          ),
                          _buildCornerHandle(
                            3,
                            _cropRect.left,
                            _cropRect.bottom,
                          ),
                          _buildEdgeHandle(
                            0,
                            left: _cropRect.left + (_cropRect.width * 0.3),
                            top: _cropRect.top - 10,
                            width: _cropRect.width * 0.4,
                            height: 20,
                          ),
                          _buildEdgeHandle(
                            1,
                            left: _cropRect.right - 10,
                            top: _cropRect.top + (_cropRect.height * 0.3),
                            width: 20,
                            height: _cropRect.height * 0.4,
                          ),
                          _buildEdgeHandle(
                            2,
                            left: _cropRect.left + (_cropRect.width * 0.3),
                            top: _cropRect.bottom - 10,
                            width: _cropRect.width * 0.4,
                            height: 20,
                          ),
                          _buildEdgeHandle(
                            3,
                            left: _cropRect.left - 10,
                            top: _cropRect.top + (_cropRect.height * 0.3),
                            width: 20,
                            height: _cropRect.height * 0.4,
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildQuickAction(
                    isActive: false,
                    icon: Icons.fit_screen_rounded,
                    label: 'Fit',
                    onTap: () => _setPreset(_CropPreset.fit),
                  ),
                  const SizedBox(width: 10),
                  _buildQuickAction(
                    isActive: false,
                    icon: Icons.fullscreen_rounded,
                    label: 'Full',
                    onTap: () => _setPreset(_CropPreset.full),
                  ),
                  const SizedBox(width: 10),
                  _buildQuickAction(
                    isActive: _isSquareMode,
                    icon: Icons.crop_square_rounded,
                    label: '1:1',
                    onTap: _toggleSquareMode,
                  ),
                  const SizedBox(width: 10),
                  _buildQuickAction(
                    isActive: false,
                    icon: Icons.refresh_rounded,
                    label: 'Reset',
                    onTap: _resetCrop,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton.icon(
                  onPressed: _isCropping ? null : _cropAndReturn,
                  icon: _isCropping
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.arrow_forward_rounded, size: 20),
                  label: Text(
                    _isCropping
                        ? (widget.isFilipino
                            ? 'Pinoproseso...'
                            : 'Processing...')
                        : (widget.isFilipino
                            ? 'I-crop at Suriin'
                            : 'Crop and Analyze'),
                    style: GoogleFonts.dmSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TomoPalette.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  final Rect cropRect;
  final bool showGrid;

  _CropOverlayPainter({
    required this.cropRect,
    required this.showGrid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(cropRect, const Radius.circular(6)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(overlayPath, Paint()..color = Colors.black.withAlpha(165));

    final borderPaint = Paint()
      ..color = const Color(0xFF43D65D)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(cropRect, const Radius.circular(6)),
      borderPaint,
    );

    if (showGrid) {
      final gridPaint = Paint()
        ..color = Colors.white.withAlpha(36)
        ..strokeWidth = 0.8;

      for (int i = 1; i < 3; i++) {
        final x = cropRect.left + cropRect.width * i / 3;
        canvas.drawLine(
          Offset(x, cropRect.top),
          Offset(x, cropRect.bottom),
          gridPaint,
        );
        final y = cropRect.top + cropRect.height * i / 3;
        canvas.drawLine(
          Offset(cropRect.left, y),
          Offset(cropRect.right, y),
          gridPaint,
        );
      }
    }

    final cornerPaint = Paint()
      ..color = const Color(0xFF43D65D)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLength = 22.0;
    final l = cropRect.left;
    final t = cropRect.top;
    final r = cropRect.right;
    final b = cropRect.bottom;

    canvas.drawLine(Offset(l, t + cornerLength), Offset(l, t), cornerPaint);
    canvas.drawLine(Offset(l, t), Offset(l + cornerLength, t), cornerPaint);

    canvas.drawLine(Offset(r - cornerLength, t), Offset(r, t), cornerPaint);
    canvas.drawLine(Offset(r, t), Offset(r, t + cornerLength), cornerPaint);

    canvas.drawLine(Offset(r, b - cornerLength), Offset(r, b), cornerPaint);
    canvas.drawLine(Offset(r, b), Offset(r - cornerLength, b), cornerPaint);

    canvas.drawLine(Offset(l + cornerLength, b), Offset(l, b), cornerPaint);
    canvas.drawLine(Offset(l, b), Offset(l, b - cornerLength), cornerPaint);

    final edgePaint = Paint()
      ..color = const Color(0xFF43D65D)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(cropRect.center.dx - 8, t),
      Offset(cropRect.center.dx + 8, t),
      edgePaint,
    );
    canvas.drawLine(
      Offset(cropRect.center.dx - 8, b),
      Offset(cropRect.center.dx + 8, b),
      edgePaint,
    );
    canvas.drawLine(
      Offset(l, cropRect.center.dy - 8),
      Offset(l, cropRect.center.dy + 8),
      edgePaint,
    );
    canvas.drawLine(
      Offset(r, cropRect.center.dy - 8),
      Offset(r, cropRect.center.dy + 8),
      edgePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) =>
      oldDelegate.cropRect != cropRect || oldDelegate.showGrid != showGrid;
}

class _CropParams {
  final Uint8List imageBytes;
  final double left, top, right, bottom;

  const _CropParams({
    required this.imageBytes,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });
}

/// Runs in a background isolate, crops to the selected frame, and re-encodes.
Uint8List? _cropImageIsolate(_CropParams params) {
  final decoded = img.decodeImage(params.imageBytes);
  if (decoded == null) return null;

  final w = decoded.width;
  final h = decoded.height;

  final cropX = (params.left * w).round().clamp(0, w - 1);
  final cropY = (params.top * h).round().clamp(0, h - 1);
  var cropW = ((params.right - params.left) * w).round().clamp(1, w - cropX);
  var cropH = ((params.bottom - params.top) * h).round().clamp(1, h - cropY);

  final cropped =
      img.copyCrop(decoded, x: cropX, y: cropY, width: cropW, height: cropH);
  return Uint8List.fromList(img.encodeJpg(cropped, quality: 90));
}
