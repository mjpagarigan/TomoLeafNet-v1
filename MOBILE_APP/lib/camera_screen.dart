import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'result_screen.dart';
import 'main.dart'; // To access global 'cameras' list

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

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

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      // Ensure flash mode is explicitly set before capture to prevent auto-flash loop
      await _controller!.setFlashMode(_flashMode);
      final image = await _controller!.takePicture();
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ResultScreen(imagePath: image.path),
          ),
        );
      }
    } catch (e) {
      print("Error taking picture: $e");
    }
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ResultScreen(imagePath: pickedFile.path),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.green)),
      );
    }

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
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                       Container(
                         width: 40, height: 40,
                         decoration: BoxDecoration(
                           borderRadius: BorderRadius.circular(8),
                           color: Colors.green.withAlpha(50),
                         ),
                         child: const Icon(Icons.eco, color: Colors.green),
                       ),
                       const SizedBox(width: 15),
                       Expanded(
                         child: Text(
                           "Ensure the plant is in focus and well lighted",
                           style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
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
                            borderRadius: BorderRadius.circular(12)
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
                            color: Colors.white, // Inner white circle
                          ),
                          child: Container(
                            margin: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white, // Inner solid
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
    final double topOffset = (size.height - boxSize) / 2 - 50; // shift up slightly

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

    // Add rounded corners
    // (Simplified for now with straight lines, but looks like corners)
    
    canvas.drawPath(path, paint);

    // Optional: Darken background outside the box (scrim)
    final scaffoldPaint = Paint()..color = Colors.black45;
    // can draw rects around...
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
