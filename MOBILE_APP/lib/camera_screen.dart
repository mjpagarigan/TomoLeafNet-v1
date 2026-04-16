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

  final LeafDetectorService _leafDetectorService = LeafDetectorService();
  DetectionResult? _detectionResult;
  Timer? _detectionTimer;
  CameraImage? _latestFrame;

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
      final previous = _detectionResult;
      final shouldUpdate = previous == null ||
          previous.label != result.label ||
          (previous.confidence - result.confidence).abs() >= 0.05;

      if (shouldUpdate) {
        setState(() {
          _detectionResult = result;
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
          : " ${( _detectionResult!.confidence * 100).toStringAsFixed(1)}%";
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

  Future<String> _cropToSquare(String imagePath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final croppedPath = imagePath.replaceAll('.jpg', '_cropped.jpg');

      // Run expensive image decode + crop + encode in a background isolate
      // so the UI thread stays responsive during the transition.
      final croppedBytes = await compute(_cropToSquareIsolate, bytes);
      if (croppedBytes == null) return imagePath;

      await File(croppedPath).writeAsBytes(croppedBytes);
      return croppedPath;
    } catch (e) {
      debugPrint("Crop error: $e, falling back to original");
      return imagePath;
    }
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
      final croppedPath = await _cropToSquare(image.path);

      if (!mounted) return;
      setState(() => _isProcessing = false);

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

      final croppedPath = await _cropToSquare(pickedFile.path);
      if (!mounted) return;

      setState(() => _isProcessing = false);
      navigated = true;
      await _navigateToResult(croppedPath);
    } finally {
      if (!navigated && mounted) {
        setState(() => _isProcessing = false);
        _maybeStartDetection();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Color(0xFF309249))),
      );
    }

    final isIdentify = widget.scanType == 'identify';
    final modeColor = isIdentify ? const Color(0xFF4CAF50) : const Color(0xFF78909C);
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
                      style: GoogleFonts.spaceGrotesk(
                          color: Colors.white, fontSize: 16),
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
                        icon: const Icon(Icons.close, color: Colors.white, size: 30),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: modeColor.withAlpha(64),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: modeColor.withAlpha(128)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isIdentify ? Icons.search : Icons.healing,
                              color: modeColor,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              modeLabel,
                              style: GoogleFonts.spaceGrotesk(
                                color: modeColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.info_outline, color: Colors.white, size: 30),
                    ],
                  ),
                ),

                const Spacer(),

                // Detection status label
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 15),
                  decoration: BoxDecoration(
                    color: _viewfinderColor.withAlpha(50),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _viewfinderColor.withAlpha(120)),
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
                              style: GoogleFonts.spaceGrotesk(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _statusSubtitle,
                              style: GoogleFonts.spaceGrotesk(
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
                        onTap: _pickFromGallery,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(8)
                          ),
                          padding: const EdgeInsets.all(12),
                          child: const Icon(Icons.image, color: Colors.white),
                        ),
                      ),

                      GestureDetector(
                        onTap: _handleCaptureTap,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF309249),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),

                      IconButton(
                        icon: Icon(_getFlashIcon(), color: Colors.white),
                        onPressed: _toggleFlash,
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
    final double top =
        (size.height - boxSize) / 2 - LeafDetectorService.viewfinderVerticalOffset;
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
      ..quadraticBezierTo(left + boxSize, top + boxSize, left + boxSize - r, top + boxSize)
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

/// Top-level function for compute() — runs image crop in a background isolate.
/// Decodes JPEG bytes, center-crops to square, re-encodes at quality 90.
Uint8List? _cropToSquareIsolate(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  final int minDim =
      decoded.width < decoded.height ? decoded.width : decoded.height;
  final int cropX = (decoded.width - minDim) ~/ 2;
  final int cropY = (decoded.height - minDim) ~/ 2;

  final cropped = img.copyCrop(
    decoded,
    x: cropX,
    y: cropY,
    width: minDim,
    height: minDim,
  );

  return Uint8List.fromList(img.encodeJpg(cropped, quality: 90));
}
