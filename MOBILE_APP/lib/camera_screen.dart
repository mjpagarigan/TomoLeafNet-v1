import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'identify_result_screen.dart';
import 'diagnose_result_screen.dart';
import 'main.dart'; // To access global 'cameras' list

class CameraScreen extends StatefulWidget {
  /// The scan type determines which result screen to navigate to.
  /// Must be "identify" or "diagnose".
  final String scanType;

  const CameraScreen({super.key, required this.scanType});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  FlashMode _flashMode = FlashMode.off;

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
    // Select the first back camera
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

  /// Navigate to the appropriate result screen based on scanType.
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

    try {
      await _controller!.setFlashMode(_flashMode);
      final image = await _controller!.takePicture();
      if (mounted) {
        _navigateToResult(image.path);
      }
    } catch (e) {
      print("Error taking picture: $e");
    }
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null && mounted) {
      _navigateToResult(pickedFile.path);
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

    // Show which mode is active
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

          // 2. Overlay (Scanner Frame)
          CustomPaint(
            size: Size.infinite,
            painter: ScannerOverlayPainter(),
          ),

          // 3. UI Controls
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
                      // Mode indicator badge
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
                           "Ensure the plant is in focus and well lighted",
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
                      // Gallery Button
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

                      // Shutter Button
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

                       // Flash/Torch Button
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

class ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final double cornerLength = 50.0;
    final double margin = 40.0;
    
    // Calculate the scanning box (centered square)
    final double boxSize = size.width - (margin * 2);
    final double topOffset = (size.height - boxSize) / 2 - 50;

    final Path path = Path();

    // Top Left
    path.moveTo(margin, topOffset + cornerLength);
    path.lineTo(margin, topOffset);
    path.lineTo(margin + cornerLength, topOffset);

    // Top Right
    path.moveTo(size.width - margin - cornerLength, topOffset);
    path.lineTo(size.width - margin, topOffset);
    path.lineTo(size.width - margin, topOffset + cornerLength);

    // Bottom Right
    path.moveTo(size.width - margin, topOffset + boxSize - cornerLength);
    path.lineTo(size.width - margin, topOffset + boxSize);
    path.lineTo(size.width - margin - cornerLength, topOffset + boxSize);

    // Bottom Left
    path.moveTo(margin + cornerLength, topOffset + boxSize);
    path.lineTo(margin, topOffset + boxSize);
    path.lineTo(margin, topOffset + boxSize - cornerLength);
    
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
