import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Color;

import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Shared TFLite inference service used by both Identify and Diagnose flows.
///
/// Encapsulates model loading, image preprocessing, and inference to avoid
/// code duplication between the two result screens.
class TFLiteService {
  Interpreter? _interpreter;
  List<String>? _labels;

  bool get isReady => _interpreter != null && _labels != null;
  List<String>? get labels => _labels;

  /// Load the TFLite model and class labels from assets.
  Future<void> loadModel() async {
    _interpreter = await Interpreter.fromAsset('assets/tomoleafnet_v3.tflite');

    final inputTensor = _interpreter!.getInputTensors()[0];
    final outputTensor = _interpreter!.getOutputTensors()[0];
    print("Input shape: ${inputTensor.shape}, type: ${inputTensor.type}");
    print("Output shape: ${outputTensor.shape}, type: ${outputTensor.type}");

    final labelData = await rootBundle.loadString('assets/labels.txt');
    _labels = labelData.split('\n').where((s) => s.trim().isNotEmpty).toList();
    print("Labels loaded: $_labels");
  }

  /// Preprocess an image file into a Float32List suitable for the model.
  ///
  /// Applies center-crop + bilinear resize to 224×224 and returns raw RGB
  /// float values (0-255 range, no normalization — matches training).
  Future<Float32List> preprocessImage(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();

    final originalCodec = await ui.instantiateImageCodec(bytes);
    final originalFrame = await originalCodec.getNextFrame();
    final originalImage = originalFrame.image;
    final int origW = originalImage.width;
    final int origH = originalImage.height;

    final int minDim = origW < origH ? origW : origH;
    final int cropX = (origW - minDim) ~/ 2;
    final int cropY = (origH - minDim) ~/ 2;

    final fullByteData =
        await originalImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (fullByteData == null) throw Exception("Failed to get image byte data");
    final fullPixels = fullByteData.buffer.asUint8List();

    const int targetSize = 224;
    final inputBuffer = Float32List(1 * targetSize * targetSize * 3);
    int bufIdx = 0;

    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {
        final double srcX = cropX + (x + 0.5) * minDim / targetSize - 0.5;
        final double srcY = cropY + (y + 0.5) * minDim / targetSize - 0.5;

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

          final double value = v00 * (1 - xFrac) * (1 - yFrac) +
              v10 * xFrac * (1 - yFrac) +
              v01 * (1 - xFrac) * yFrac +
              v11 * xFrac * yFrac;

          inputBuffer[bufIdx++] = value;
        }
      }
    }

    return inputBuffer;
  }

  /// Run inference on the preprocessed image buffer.
  ///
  /// Returns a [TFLiteResult] with the predicted label, index, and
  /// confidence score.
  TFLiteResult runInference(Float32List inputBuffer) {
    if (_interpreter == null || _labels == null) {
      throw Exception("Model not loaded. Call loadModel() first.");
    }

    final input = inputBuffer.reshape([1, 224, 224, 3]);
    final numClasses = _labels!.length;
    final output = List.filled(1 * numClasses, 0.0).reshape([1, numClasses]);

    _interpreter!.run(input, output);

    final probabilities = output[0] as List<double>;

    double maxProb = probabilities[0];
    int maxIndex = 0;
    for (int i = 1; i < probabilities.length; i++) {
      if (probabilities[i] > maxProb) {
        maxProb = probabilities[i];
        maxIndex = i;
      }
    }

    return TFLiteResult(
      label: _labels![maxIndex],
      index: maxIndex,
      confidence: maxProb,
    );
  }

  /// Convenience: load model, preprocess image, and run inference in one call.
  Future<TFLiteResult> predict(String imagePath) async {
    if (!isReady) await loadModel();
    final buffer = await preprocessImage(imagePath);
    return runInference(buffer);
  }

  /// Dispose the interpreter.
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }

  // ── Confidence helpers ──────────────────────────────────────────────

  static String getConfidenceLabel(double confidence) {
    if (confidence >= 0.80) return "High Confidence";
    if (confidence >= 0.60) return "Moderate Confidence";
    if (confidence >= 0.40) return "Low Confidence";
    return "Very Low Confidence — Please retake the photo";
  }

  static Color getConfidenceColor(double confidence) {
    if (confidence >= 0.80) return const Color(0xFF4CAF50);
    if (confidence >= 0.60) return const Color(0xFFFF9800);
    if (confidence >= 0.40) return const Color(0xFFFFC107);
    return const Color(0xFFF44336);
  }

  static String getDisplayName(String label) {
    const names = {
      'Bacterial_Spot': 'Bacterial Spot',
      'Early_Blight': 'Early Blight',
      'Healthy': 'Healthy Leaf',
      'Late_Blight': 'Late Blight',
      'Septoria': 'Septoria Leaf Spot',
    };
    return names[label] ?? label.replaceAll('_', ' ');
  }
}

/// Result of a single TFLite inference run.
class TFLiteResult {
  final String label;
  final int index;
  final double confidence;

  const TFLiteResult({
    required this.label,
    required this.index,
    required this.confidence,
  });

  String get displayName => TFLiteService.getDisplayName(label);
  String get confidenceLabel => TFLiteService.getConfidenceLabel(confidence);
  String get confidencePercent =>
      '${(confidence * 100).toStringAsFixed(1)}%';
}
