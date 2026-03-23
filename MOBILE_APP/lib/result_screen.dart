import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart';

class ResultScreen extends StatefulWidget {
  final String imagePath;

  const ResultScreen({super.key, required this.imagePath});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  // TFLite Variables
  Interpreter? _interpreter;
  List<String>? _labels;
  bool _isLoading = true;
  String _label = "Analyzing...";
  double _confidence = 0.0;
  String _errorMessage = "";

  // Disease information database
  static const Map<String, Map<String, dynamic>> _diseaseInfo = {
    'Bacterial_Spot': {
      'displayName': 'Bacterial Spot',
      'about': 'Bacterial Spot is caused by Xanthomonas bacteria. It creates small, water-soaked spots on leaves that turn brown and may have a yellow halo.',
      'tips': [
        {'icon': Icons.water_drop, 'text': 'Avoid overhead watering to reduce spread.'},
        {'icon': Icons.cut, 'text': 'Remove and destroy infected plant parts.'},
        {'icon': Icons.shield, 'text': 'Apply copper-based bactericide.'},
      ],
    },
    'Early_Blight': {
      'displayName': 'Early Blight',
      'about': 'Early Blight is caused by the fungus Alternaria solani. It manifests as dark, concentric ring patterns (target spots) on older, lower leaves.',
      'tips': [
        {'icon': Icons.water_drop, 'text': 'Water at the base of the plant, not the leaves.'},
        {'icon': Icons.cut, 'text': 'Prune infected leaves immediately.'},
        {'icon': Icons.shield, 'text': 'Apply copper-based fungicide.'},
      ],
    },
    'Healthy': {
      'displayName': 'Healthy Leaf',
      'about': 'This tomato leaf appears healthy with no signs of disease. The leaf shows normal color and structure.',
      'tips': [
        {'icon': Icons.water_drop, 'text': 'Continue regular watering schedule.'},
        {'icon': Icons.wb_sunny, 'text': 'Ensure adequate sunlight (6-8 hours).'},
        {'icon': Icons.compost, 'text': 'Maintain balanced fertilization.'},
      ],
    },
    'Late_Blight': {
      'displayName': 'Late Blight',
      'about': 'Late Blight is caused by the oomycete Phytophthora infestans. It causes large, dark, water-soaked lesions and can rapidly destroy entire plants.',
      'tips': [
        {'icon': Icons.delete, 'text': 'Remove and destroy infected plants immediately.'},
        {'icon': Icons.shield, 'text': 'Apply fungicide (chlorothalonil or mancozeb).'},
        {'icon': Icons.air, 'text': 'Improve air circulation between plants.'},
      ],
    },
    'Septoria': {
      'displayName': 'Septoria Leaf Spot',
      'about': 'Septoria Leaf Spot is caused by the fungus Septoria lycopersici. It creates small, circular spots with dark borders and gray centers on lower leaves.',
      'tips': [
        {'icon': Icons.cut, 'text': 'Remove infected lower leaves promptly.'},
        {'icon': Icons.water_drop, 'text': 'Use drip irrigation instead of overhead watering.'},
        {'icon': Icons.shield, 'text': 'Apply chlorothalonil or copper fungicide.'},
      ],
    },
  };

  @override
  void initState() {
    super.initState();
    _loadModelAndPredict();
  }

  /// Load image, center-crop to square, resize to 224x224, keep [0, 255] range.
  /// This MUST match the Python preprocessing in test_image.py / test.py:
  ///   1. Load image at original size
  ///   2. Center crop to square (min(h,w) x min(h,w))
  ///   3. Resize to 224x224
  ///   4. Pixel values stay in [0, 255] float32 (NO normalization to [0,1])
  Future<Float32List> _preprocessImage(String imagePath) async {
    // Read the image file
    final bytes = await File(imagePath).readAsBytes();

    // Step 1: Decode at ORIGINAL size first (for center crop)
    final originalCodec = await ui.instantiateImageCodec(bytes);
    final originalFrame = await originalCodec.getNextFrame();
    final originalImage = originalFrame.image;
    final int origW = originalImage.width;
    final int origH = originalImage.height;
    print("Original image size: ${origW}x${origH}");

    // Step 2: Center crop to square
    final int minDim = origW < origH ? origW : origH;
    final int cropX = (origW - minDim) ~/ 2;
    final int cropY = (origH - minDim) ~/ 2;
    print("Center crop: offset=($cropX, $cropY), size=${minDim}x${minDim}");

    // Get full image pixel data
    final fullByteData = await originalImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (fullByteData == null) throw Exception("Failed to get image byte data");
    final fullPixels = fullByteData.buffer.asUint8List();

    // Step 3: Crop and resize to 224x224 using bilinear interpolation
    const int targetSize = 224;
    final inputBuffer = Float32List(1 * targetSize * targetSize * 3);
    int bufIdx = 0;

    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {
        // Map target pixel to source coordinate (within the cropped region)
        final double srcX = cropX + (x + 0.5) * minDim / targetSize - 0.5;
        final double srcY = cropY + (y + 0.5) * minDim / targetSize - 0.5;

        // Bilinear interpolation
        final int x0 = srcX.floor().clamp(0, origW - 1);
        final int x1 = (x0 + 1).clamp(0, origW - 1);
        final int y0 = srcY.floor().clamp(0, origH - 1);
        final int y1 = (y0 + 1).clamp(0, origH - 1);

        final double xFrac = srcX - x0;
        final double yFrac = srcY - y0;

        for (int c = 0; c < 3; c++) {
          final double v00 = fullPixels[(y0 * origW + x0) * 4 + c].toDouble();
          final double v10 = fullPixels[(y0 * origW + x1) * 4 + c].toDouble();
          final double v01 = fullPixels[(y1 * origW + x0) * 4 + c].toDouble();
          final double v11 = fullPixels[(y1 * origW + x1) * 4 + c].toDouble();

          // Bilinear blend
          final double value = v00 * (1 - xFrac) * (1 - yFrac) +
                               v10 * xFrac * (1 - yFrac) +
                               v01 * (1 - xFrac) * yFrac +
                               v11 * xFrac * yFrac;

          // Keep in [0, 255] range — DO NOT normalize to [0, 1]!
          inputBuffer[bufIdx++] = value;
        }
      }
    }

    print("Preprocessed buffer: length=${inputBuffer.length}, "
        "first 6 values=[${inputBuffer[0].toStringAsFixed(1)}, ${inputBuffer[1].toStringAsFixed(1)}, ${inputBuffer[2].toStringAsFixed(1)}, "
        "${inputBuffer[3].toStringAsFixed(1)}, ${inputBuffer[4].toStringAsFixed(1)}, ${inputBuffer[5].toStringAsFixed(1)}]");

    return inputBuffer;
  }

  Future<void> _loadModelAndPredict() async {
    try {
      // 1. Load Model
      print("Loading TFLite model...");
      _interpreter = await Interpreter.fromAsset('assets/tomoleafnet_v3.tflite');

      // Print model details for debugging
      final inputTensor = _interpreter!.getInputTensors()[0];
      final outputTensor = _interpreter!.getOutputTensors()[0];
      print("Input shape: ${inputTensor.shape}, type: ${inputTensor.type}");
      print("Output shape: ${outputTensor.shape}, type: ${outputTensor.type}");

      // 2. Load Labels
      final labelData = await rootBundle.loadString('assets/labels.txt');
      _labels = labelData.split('\n').where((s) => s.trim().isNotEmpty).toList();
      print("Labels loaded: $_labels");

      // 3. Preprocess Image (center-crop to square, resize to 224x224, keep [0-255])
      print("Preprocessing image: ${widget.imagePath}");
      final inputBuffer = await _preprocessImage(widget.imagePath);

      // 4. Reshape input to [1, 224, 224, 3]
      final input = inputBuffer.reshape([1, 224, 224, 3]);

      // 5. Prepare output buffer [1, num_classes]
      final numClasses = _labels!.length;
      final output = List.filled(1 * numClasses, 0.0).reshape([1, numClasses]);

      // 6. Run inference
      print("Running inference...");
      _interpreter!.run(input, output);

      // 7. Get results — argmax across all class probabilities
      final probabilities = output[0] as List<double>;
      print("Raw output: $probabilities");

      // Find the class with the highest probability (argmax)
      double maxProb = probabilities[0];
      int maxIndex = 0;
      for (int i = 1; i < probabilities.length; i++) {
        if (probabilities[i] > maxProb) {
          maxProb = probabilities[i];
          maxIndex = i;
        }
      }

      final predictedLabel = _labels![maxIndex];
      print("Prediction: $predictedLabel (${(maxProb * 100).toStringAsFixed(1)}%)");

      if (mounted) {
        setState(() {
          _label = predictedLabel;
          _confidence = maxProb;
          _isLoading = false;
        });
      }

    } catch (e, stackTrace) {
      print("Error running model: $e");
      print("Stack trace: $stackTrace");
      if (mounted) {
        setState(() {
          _label = "Error";
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _interpreter?.close();
    super.dispose();
  }

  // Get display-friendly name for the label
  String _getDisplayName(String label) {
    return _diseaseInfo[label]?['displayName'] ?? label.replaceAll('_', ' ');
  }

  // Get disease info
  Map<String, dynamic>? _getDiseaseInfo(String label) {
    return _diseaseInfo[label];
  }

  // --- Confidence helpers ---

  String _getConfidenceLabel(double confidence) {
    if (confidence >= 0.80) return "High Confidence";
    if (confidence >= 0.60) return "Moderate Confidence";
    if (confidence >= 0.40) return "Low Confidence";
    return "Very Low Confidence";
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.80) return const Color(0xFF4CAF50); // Green
    if (confidence >= 0.60) return const Color(0xFFFF9800); // Orange
    if (confidence >= 0.40) return const Color(0xFFFFC107); // Yellow/Amber
    return const Color(0xFFF44336); // Red
  }

  IconData _getConfidenceIcon(double confidence) {
    if (confidence >= 0.80) return Icons.check_circle;
    if (confidence >= 0.60) return Icons.info;
    if (confidence >= 0.40) return Icons.warning_amber_rounded;
    return Icons.error_outline;
  }

  @override
  Widget build(BuildContext context) {
    final diseaseData = _getDiseaseInfo(_label);
    final confidenceColor = _getConfidenceColor(_confidence);
    final confidenceLabel = _getConfidenceLabel(_confidence);
    final confidenceIcon = _getConfidenceIcon(_confidence);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text("Result", style: GoogleFonts.poppins(color: Colors.white)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Image Preview ---
            Container(
              width: double.infinity,
              height: 300,
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: FileImage(File(widget.imagePath)),
                  fit: BoxFit.cover,
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: _isLoading
                ? Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(128),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(30),
                        bottomRight: Radius.circular(30),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: Colors.green),
                        const SizedBox(height: 16),
                        Text(
                          "Analyzing leaf...",
                          style: GoogleFonts.poppins(color: Colors.white, fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : null,
            ),

            const SizedBox(height: 20),

            // --- Result Card ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Error display
                  if (_errorMessage.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withAlpha(51),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red),
                      ),
                      child: Text(
                        _errorMessage,
                        style: GoogleFonts.poppins(color: Colors.red[300], fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Disease name
                  Text(
                    _isLoading ? "Identifying..." : _getDisplayName(_label),
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  if (!_isLoading) ...[
                    const SizedBox(height: 16),

                    // --- Confidence Card ---
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: confidenceColor.withAlpha(25),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: confidenceColor.withAlpha(80)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Confidence label with icon
                          Row(
                            children: [
                              Icon(confidenceIcon, color: confidenceColor, size: 22),
                              const SizedBox(width: 8),
                              Text(
                                confidenceLabel,
                                style: GoogleFonts.poppins(
                                  color: confidenceColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Progress bar
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: _confidence,
                              minHeight: 10,
                              backgroundColor: Colors.white.withAlpha(25),
                              valueColor: AlwaysStoppedAnimation<Color>(confidenceColor),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Raw percentage (secondary, de-emphasized)
                          Text(
                            "${(_confidence * 100).toStringAsFixed(1)}% match",
                            style: GoogleFonts.poppins(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // --- Retake prompt for very low confidence ---
                    if (_confidence < 0.40) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF44336).withAlpha(20),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFF44336).withAlpha(60)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.camera_alt, color: Color(0xFFF44336), size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "Try retaking the photo with better lighting and a closer view of the leaf for a more accurate result.",
                                style: GoogleFonts.poppins(
                                  color: Colors.red[300],
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // --- About Section ---
                    if (diseaseData != null) ...[
                      _buildSectionTitle("About"),
                      const SizedBox(height: 10),
                      Text(
                        diseaseData['about'] as String,
                        style: GoogleFonts.poppins(color: Colors.grey[400], height: 1.5),
                      ),

                      const SizedBox(height: 20),
                      _buildSectionTitle(
                        _label == 'Healthy' ? "Care Tips" : "Treatment"
                      ),
                      const SizedBox(height: 10),
                      ...(diseaseData['tips'] as List).map((tip) =>
                        _buildTip(tip['icon'] as IconData, tip['text'] as String)
                      ),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.poppins(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildTip(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.green, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.poppins(color: Colors.grey[300]),
            ),
          ),
        ],
      ),
    );
  }
}
