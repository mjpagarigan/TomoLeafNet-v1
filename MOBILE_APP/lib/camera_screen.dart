import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'identify_result_screen.dart';
import 'diagnose_result_screen.dart';
import 'services/tflite_service.dart';
import 'main.dart'; // To access global 'cameras' list

class CameraScreen extends StatefulWidget {
  final String scanType;

  const CameraScreen({super.key, required this.scanType});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  FlashMode _flashMode = FlashMode.off;
  bool _isProcessing = false;

  // Real-time detection state
  final TFLiteService _tfliteService = TFLiteService();
  bool _isModelReady = false;
  bool _isAnalyzing = false;
  Color _viewfinderColor = const Color(0xFF4CAF50); // default green
  String _detectionLabel = "";
  double _detectionConfidence = 0.0;
  bool _isTomatoLeaf = true;
  int _consecutiveNotTomato = 0;
  int _consecutiveTomato = 0;
  static const int _debounceCount = 3; // require 3 consecutive same results

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      await _tfliteService.loadModel();
      if (mounted) {
        setState(() => _isModelReady = true);
      }
    } catch (e) {
      print("TFLite model load error: $e");
    }
  }

  Future<void> _initializeCamera() async {
    if (cameras.isEmpty) {
      print("No cameras found");
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
        _startImageStream();
      }
    } catch (e) {
      print("Camera initialization error: $e");
    }
  }

  /// Start the camera image stream for real-time leaf detection.
  void _startImageStream() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    _controller!.startImageStream((CameraImage cameraImage) {
      if (_isAnalyzing || !_isModelReady || _isProcessing) return;
      _isAnalyzing = true;
      _processFrame(cameraImage);
    });
  }

  /// Stop the image stream (before taking a picture or disposing).
  Future<void> _stopImageStream() async {
    try {
      await _controller?.stopImageStream();
    } catch (_) {}
  }

  /// Process a single camera frame for tomato leaf detection.
  Future<void> _processFrame(CameraImage cameraImage) async {
    try {
      // Convert YUV420/BGRA camera image to RGBA bytes on a background isolate
      final rgbaBytes = await compute(_convertCameraImage, _CameraImageData(
        planes: cameraImage.planes.map((p) => _PlaneData(
          bytes: Uint8List.fromList(p.bytes),
          bytesPerRow: p.bytesPerRow,
          bytesPerPixel: p.bytesPerPixel,
        )).toList(),
        width: cameraImage.width,
        height: cameraImage.height,
        formatGroupRaw: cameraImage.format.group.index,
      ));

      if (rgbaBytes == null || !_isModelReady || !mounted) {
        _isAnalyzing = false;
        return;
      }

      // Run inference on the viewfinder region
      final result = _tfliteService.runInferenceOnFrame(
        rgbaBytes,
        cameraImage.width,
        cameraImage.height,
      );

      final isNotTomato = result.label == 'Not_Tomato';

      // Debounce: require consecutive same-class predictions
      if (isNotTomato) {
        _consecutiveNotTomato++;
        _consecutiveTomato = 0;
      } else {
        _consecutiveTomato++;
        _consecutiveNotTomato = 0;
      }

      if (mounted) {
        if (_consecutiveNotTomato >= _debounceCount && _isTomatoLeaf) {
          setState(() {
            _isTomatoLeaf = false;
            _viewfinderColor = const Color(0xFFE53935); // red
            _detectionLabel = "Not a tomato leaf";
            _detectionConfidence = result.confidence;
          });
        } else if (_consecutiveTomato >= _debounceCount && !_isTomatoLeaf) {
          setState(() {
            _isTomatoLeaf = true;
            _viewfinderColor = const Color(0xFF4CAF50); // green
            _detectionLabel = result.displayName;
            _detectionConfidence = result.confidence;
          });
        } else if (_isTomatoLeaf && _consecutiveTomato >= _debounceCount) {
          // Update label for current tomato class
          setState(() {
            _detectionLabel = result.displayName;
            _detectionConfidence = result.confidence;
          });
        }
      }
    } catch (e) {
      print("Frame processing error: $e");
    } finally {
      // Throttle: wait 400ms before processing next frame
      await Future.delayed(const Duration(milliseconds: 400));
      _isAnalyzing = false;
    }
  }

  @override
  void dispose() {
    _tfliteService.dispose();
    _controller?.dispose();
    super.dispose();
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
      print("Flash mode error: $e");
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

  /// Crop an image file to a square centered region, then navigate to result.
  Future<void> _cropAndNavigate(String imagePath) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final bytes = await File(imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        _navigateToResult(imagePath);
        return;
      }

      final int minDim = decoded.width < decoded.height
          ? decoded.width
          : decoded.height;
      final int cropX = (decoded.width - minDim) ~/ 2;
      final int cropY = (decoded.height - minDim) ~/ 2;

      final cropped = img.copyCrop(
        decoded,
        x: cropX,
        y: cropY,
        width: minDim,
        height: minDim,
      );

      final croppedPath = imagePath.replaceAll('.jpg', '_cropped.jpg');
      final croppedFile = File(croppedPath);
      await croppedFile.writeAsBytes(img.encodeJpg(cropped, quality: 90));

      if (mounted) {
        _navigateToResult(croppedPath);
      }
    } catch (e) {
      print("Crop error: $e, falling back to original");
      if (mounted) {
        _navigateToResult(imagePath);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _navigateToResult(String imagePath) {
    final Widget resultScreen;
    if (widget.scanType == 'diagnose') {
      resultScreen = DiagnoseResultScreen(imagePath: imagePath);
    } else {
      resultScreen = IdentifyResultScreen(imagePath: imagePath);
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => resultScreen),
    );
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isProcessing) return;
    if (!_isTomatoLeaf) return; // Block capture when not a tomato leaf

    try {
      // Stop the stream before taking a picture
      await _stopImageStream();
      await _controller!.setFlashMode(_flashMode);
      final image = await _controller!.takePicture();
      if (mounted) {
        _cropAndNavigate(image.path);
      }
    } catch (e) {
      print("Error taking picture: $e");
      // Restart stream if capture fails
      if (mounted) _startImageStream();
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isProcessing) return;
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null && mounted) {
      _cropAndNavigate(pickedFile.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Color(0xFF13EC13))),
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
                      "Processing...",
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
                if (_detectionLabel.isNotEmpty)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
                    decoration: BoxDecoration(
                      color: _isTomatoLeaf
                          ? const Color(0xFF4CAF50).withAlpha(50)
                          : const Color(0xFFE53935).withAlpha(50),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isTomatoLeaf
                            ? const Color(0xFF4CAF50).withAlpha(100)
                            : const Color(0xFFE53935).withAlpha(100),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isTomatoLeaf ? Icons.check_circle : Icons.warning_rounded,
                          color: _isTomatoLeaf
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFE53935),
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isTomatoLeaf
                                    ? "Tomato leaf detected"
                                    : "Not a tomato leaf",
                                style: GoogleFonts.spaceGrotesk(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (!_isTomatoLeaf)
                                Text(
                                  "Reposition to scan a tomato leaf",
                                  style: GoogleFonts.spaceGrotesk(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                // Tip Box (shown when no detection yet)
                if (_detectionLabel.isEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                         Container(
                           width: 40, height: 40,
                           decoration: BoxDecoration(
                             borderRadius: BorderRadius.circular(8),
                             color: const Color(0xFF13EC13).withAlpha(50),
                           ),
                           child: const Icon(Icons.eco, color: Color(0xFF13EC13)),
                         ),
                         const SizedBox(width: 15),
                         Expanded(
                           child: Text(
                             "Position the tomato leaf inside the box",
                             style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 13),
                           ),
                         )
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

                      // Shutter button — disabled (dimmed) when not a tomato leaf
                      GestureDetector(
                        onTap: _isTomatoLeaf ? _takePicture : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _isTomatoLeaf ? Colors.white : Colors.white38,
                              width: 4,
                            ),
                            color: _isTomatoLeaf ? Colors.white : Colors.white24,
                          ),
                          child: Container(
                            margin: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isTomatoLeaf ? Colors.white : Colors.white24,
                            ),
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

/// Convert a CameraImage (YUV420 or BGRA) to RGBA bytes.
/// Runs on a background isolate via [compute] to avoid UI jank.
Uint8List? _convertCameraImage(_CameraImageData data) {
  final int width = data.width;
  final int height = data.height;

  try {
    if (data.formatGroupRaw == ImageFormatGroup.yuv420.index &&
        data.planes.length >= 3) {
      // YUV420 → RGBA (Android)
      final yPlane = data.planes[0];
      final uPlane = data.planes[1];
      final vPlane = data.planes[2];

      final rgba = Uint8List(width * height * 4);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int yIndex = y * yPlane.bytesPerRow + x;
          final int uvIndex = (y ~/ 2) * uPlane.bytesPerRow +
              (x ~/ 2) * (uPlane.bytesPerPixel ?? 1);

          final int yVal = yPlane.bytes[yIndex];
          final int uVal = uvIndex < uPlane.bytes.length
              ? uPlane.bytes[uvIndex]
              : 128;
          final int vVal = uvIndex < vPlane.bytes.length
              ? vPlane.bytes[uvIndex]
              : 128;

          // YUV to RGB conversion
          int r = (yVal + 1.370705 * (vVal - 128)).round().clamp(0, 255);
          int g = (yVal - 0.337633 * (uVal - 128) - 0.698001 * (vVal - 128))
              .round()
              .clamp(0, 255);
          int b = (yVal + 1.732446 * (uVal - 128)).round().clamp(0, 255);

          final int rgbaIdx = (y * width + x) * 4;
          rgba[rgbaIdx] = r;
          rgba[rgbaIdx + 1] = g;
          rgba[rgbaIdx + 2] = b;
          rgba[rgbaIdx + 3] = 255;
        }
      }
      return rgba;
    } else if (data.planes.length == 1) {
      // BGRA → RGBA (iOS)
      final plane = data.planes[0];
      final rgba = Uint8List(width * height * 4);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int srcIdx = y * plane.bytesPerRow + x * 4;
          final int dstIdx = (y * width + x) * 4;

          if (srcIdx + 3 < plane.bytes.length) {
            rgba[dstIdx] = plane.bytes[srcIdx + 2];     // R (from BGRA)
            rgba[dstIdx + 1] = plane.bytes[srcIdx + 1]; // G
            rgba[dstIdx + 2] = plane.bytes[srcIdx];     // B
            rgba[dstIdx + 3] = 255;
          }
        }
      }
      return rgba;
    }
  } catch (e) {
    // Return null on error — the frame will be skipped
  }
  return null;
}

/// Data classes for passing camera image data to isolate via [compute].
class _CameraImageData {
  final List<_PlaneData> planes;
  final int width;
  final int height;
  final int formatGroupRaw;

  _CameraImageData({
    required this.planes,
    required this.width,
    required this.height,
    required this.formatGroupRaw,
  });
}

class _PlaneData {
  final Uint8List bytes;
  final int bytesPerRow;
  final int? bytesPerPixel;

  _PlaneData({
    required this.bytes,
    required this.bytesPerRow,
    this.bytesPerPixel,
  });
}

/// Custom painter that draws a centered square viewfinder with a dark
/// semi-transparent overlay outside the box and colored rounded corners.
class SquareViewfinderPainter extends CustomPainter {
  final Color cornerColor;

  SquareViewfinderPainter({this.cornerColor = const Color(0xFF4CAF50)});

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate the centered square box (80% of screen width)
    final double boxSize = size.width * 0.80;
    final double left = (size.width - boxSize) / 2;
    final double top = (size.height - boxSize) / 2 - 40;
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
