import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'identify_result_screen.dart';
import 'diagnose_result_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _initializeCamera();
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
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      await _controller!.setFlashMode(FlashMode.off);
      if (mounted) {
        setState(() {
          _flashMode = FlashMode.off;
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      print("Camera initialization error: $e");
    }
  }

  @override
  void dispose() {
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

    try {
      await _controller!.setFlashMode(_flashMode);
      final image = await _controller!.takePicture();
      if (mounted) {
        _cropAndNavigate(image.path);
      }
    } catch (e) {
      print("Error taking picture: $e");
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

          // 2. Square viewfinder overlay with dark edges (Improvement 7)
          CustomPaint(
            size: Size.infinite,
            painter: SquareViewfinderPainter(),
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
                          color: modeColor.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: modeColor.withOpacity(0.5)),
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

                // Tip Box
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

                      GestureDetector(
                        onTap: _takePicture,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                            color: Colors.white,
                          ),
                          child: Container(
                            margin: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
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

/// Custom painter that draws a centered square viewfinder with a dark
/// semi-transparent overlay outside the box and green rounded corners.
class SquareViewfinderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Calculate the centered square box (80% of screen width)
    final double boxSize = size.width * 0.80;
    final double left = (size.width - boxSize) / 2;
    final double top = (size.height - boxSize) / 2 - 40;
    final Rect boxRect = Rect.fromLTWH(left, top, boxSize, boxSize);

    // Draw the dark overlay outside the box
    final overlayPaint = Paint()
      ..color = Colors.black.withOpacity(0.60)
      ..style = PaintingStyle.fill;

    // Create a path covering everything except the box
    final overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(boxRect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(overlayPath, overlayPaint);

    // Draw the green rounded corner brackets
    final cornerPaint = Paint()
      ..color = const Color(0xFF4CAF50)
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final double cornerLength = 40.0;
    final double r = 16.0; // corner radius

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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
