import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
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
    _interpreter = await Interpreter.fromAsset('assets/tomoleafnet_v4.tflite');

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
  /// Applies center-crop + bilinear resize to 224×224, then normalizes
  /// pixel values to [-1, 1] range matching MobileNetV3 preprocessing.
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

          // MobileNetV3 normalization: [0, 255] -> [-1, 1]
          inputBuffer[bufIdx++] = value / 127.5 - 1.0;
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

    // Find top-1 and top-2 predictions
    double top1Prob = -1.0;
    double top2Prob = -1.0;
    int top1Index = 0;
    for (int i = 0; i < probabilities.length; i++) {
      if (probabilities[i] > top1Prob) {
        top2Prob = top1Prob;
        top1Prob = probabilities[i];
        top1Index = i;
      } else if (probabilities[i] > top2Prob) {
        top2Prob = probabilities[i];
      }
    }

    final confidenceGap = top1Prob - (top2Prob < 0 ? 0.0 : top2Prob);

    return TFLiteResult(
      label: _labels![top1Index],
      index: top1Index,
      confidence: top1Prob,
      confidenceGap: confidenceGap,
    );
  }

  /// Run inference on raw RGBA pixel bytes from a camera frame.
  ///
  /// [rgbaBytes] — raw RGBA pixel data.
  /// [width], [height] — frame dimensions.
  /// [viewfinderFraction] — the fraction of width used for the viewfinder box
  ///   (e.g., 0.80 means 80% of width).
  /// Extracts the square viewfinder region, resizes to 224×224, normalizes,
  /// and returns the prediction.
  TFLiteResult runInferenceOnFrame(
    Uint8List rgbaBytes,
    int width,
    int height, {
    double viewfinderFraction = 0.80,
  }) {
    if (_interpreter == null || _labels == null) {
      throw Exception("Model not loaded. Call loadModel() first.");
    }

    // Calculate the viewfinder box region (matches SquareViewfinderPainter)
    final int boxSize = (width * viewfinderFraction).round();
    final int cropX = (width - boxSize) ~/ 2;
    final int cropY = (height - boxSize) ~/ 2 - (40 * height ~/ 800);

    // Clamp to valid bounds
    final int safeX = cropX.clamp(0, width - 1);
    final int safeY = cropY.clamp(0, height - 1);
    final int safeW = boxSize.clamp(1, width - safeX);
    final int safeH = boxSize.clamp(1, height - safeY);

    const int targetSize = 224;
    final inputBuffer = Float32List(1 * targetSize * targetSize * 3);
    int bufIdx = 0;

    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {
        // Map to source pixel in the viewfinder region (nearest neighbor for speed)
        final int srcX = safeX + (x * safeW ~/ targetSize);
        final int srcY = safeY + (y * safeH ~/ targetSize);
        final int pixelIdx = (srcY * width + srcX) * 4;

        if (pixelIdx + 2 < rgbaBytes.length) {
          inputBuffer[bufIdx++] = rgbaBytes[pixelIdx] / 127.5 - 1.0;       // R
          inputBuffer[bufIdx++] = rgbaBytes[pixelIdx + 1] / 127.5 - 1.0;   // G
          inputBuffer[bufIdx++] = rgbaBytes[pixelIdx + 2] / 127.5 - 1.0;   // B
        } else {
          inputBuffer[bufIdx++] = 0.0;
          inputBuffer[bufIdx++] = 0.0;
          inputBuffer[bufIdx++] = 0.0;
        }
      }
    }

    return runInference(inputBuffer);
  }

  /// Convenience: load model, preprocess image, and run inference in one call.
  Future<TFLiteResult> predict(String imagePath) async {
    if (!isReady) await loadModel();
    final buffer = await preprocessImage(imagePath);
    return runInference(buffer);
  }

  /// Generate an occlusion sensitivity heatmap for the given image.
  ///
  /// Divides the 224×224 preprocessed image into a grid, occludes each patch
  /// with gray, re-runs inference, and measures the confidence drop. Returns
  /// PNG bytes of the heatmap overlaid on the original image.
  Future<Uint8List> generateHeatmap(String imagePath, int classIndex) async {
    if (!isReady) await loadModel();

    final baseBuffer = await preprocessImage(imagePath);
    final baseResult = runInference(baseBuffer);
    final baseConfidence = baseResult.confidence;

    const int imgSize = 224;
    const int gridSize = 4; // 4x4 grid = 16 inferences (fast)
    const int patchSize = imgSize ~/ gridSize; // 56

    // Compute importance for each grid cell, yielding to UI between rows
    final importance = List.generate(gridSize, (_) => List.filled(gridSize, 0.0));

    for (int gy = 0; gy < gridSize; gy++) {
      for (int gx = 0; gx < gridSize; gx++) {
        final occluded = Float32List.fromList(baseBuffer);
        final yStart = gy * patchSize;
        final xStart = gx * patchSize;

        for (int y = yStart; y < math.min(yStart + patchSize, imgSize); y++) {
          for (int x = xStart; x < math.min(xStart + patchSize, imgSize); x++) {
            final idx = (y * imgSize + x) * 3;
            occluded[idx] = 0.0;     // Gray in [-1, 1] normalized space
            occluded[idx + 1] = 0.0;
            occluded[idx + 2] = 0.0;
          }
        }

        final result = runInference(occluded);
        final drop = baseConfidence - result.confidence;
        importance[gy][gx] = drop.clamp(0.0, 1.0);
      }
      // Yield to the UI thread after each row so the spinner stays smooth
      await Future.delayed(Duration.zero);
    }

    // Normalize importance to [0, 1]
    double maxImp = 0.0;
    for (final row in importance) {
      for (final v in row) {
        if (v > maxImp) maxImp = v;
      }
    }
    if (maxImp > 0) {
      for (int gy = 0; gy < gridSize; gy++) {
        for (int gx = 0; gx < gridSize; gx++) {
          importance[gy][gx] /= maxImp;
        }
      }
    }

    // Pre-compute the HSV lookup table (256 entries) to avoid per-pixel calls
    final lut = List<List<int>>.generate(256, (i) {
      final val = i / 255.0;
      final hue = 0.66 * (1.0 - val);
      return _hsvToRgb(hue, 1.0, 1.0);
    });

    // Build RGBA pixel buffer: blend original image with heatmap color
    final pixels = Uint8List(imgSize * imgSize * 4);
    for (int y = 0; y < imgSize; y++) {
      for (int x = 0; x < imgSize; x++) {
        final srcIdx = (y * imgSize + x) * 3;
        final dstIdx = (y * imgSize + x) * 4;

        // Bilinear interpolation of the grid importance
        final gxCenter = (x + 0.5) / patchSize - 0.5;
        final gyCenter = (y + 0.5) / patchSize - 0.5;
        final gx0 = gxCenter.floor().clamp(0, gridSize - 1);
        final gx1 = (gx0 + 1).clamp(0, gridSize - 1);
        final gy0 = gyCenter.floor().clamp(0, gridSize - 1);
        final gy1 = (gy0 + 1).clamp(0, gridSize - 1);
        final fx = (gxCenter - gx0).clamp(0.0, 1.0);
        final fy = (gyCenter - gy0).clamp(0.0, 1.0);
        final val = importance[gy0][gx0] * (1 - fx) * (1 - fy) +
            importance[gy0][gx1] * fx * (1 - fy) +
            importance[gy1][gx0] * (1 - fx) * fy +
            importance[gy1][gx1] * fx * fy;

        // Use LUT for the colormap
        final lutIdx = (val * 255).round().clamp(0, 255);
        final hsvColor = lut[lutIdx];

        // Convert from [-1, 1] back to [0, 255] for display blending
        final origR = ((baseBuffer[srcIdx] + 1.0) * 127.5).clamp(0, 255);
        final origG = ((baseBuffer[srcIdx + 1] + 1.0) * 127.5).clamp(0, 255);
        final origB = ((baseBuffer[srcIdx + 2] + 1.0) * 127.5).clamp(0, 255);

        pixels[dstIdx] = ((origR * 0.6) + (hsvColor[0] * 0.4)).round().clamp(0, 255);
        pixels[dstIdx + 1] = ((origG * 0.6) + (hsvColor[1] * 0.4)).round().clamp(0, 255);
        pixels[dstIdx + 2] = ((origB * 0.6) + (hsvColor[2] * 0.4)).round().clamp(0, 255);
        pixels[dstIdx + 3] = 255;
      }
    }

    // Encode to PNG using dart:ui
    final completer = _ImageCompleter();
    ui.decodeImageFromPixels(
      pixels,
      imgSize,
      imgSize,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw Exception('Failed to encode heatmap to PNG');
    return byteData.buffer.asUint8List();
  }

  /// Convert HSV (h: 0-1, s: 0-1, v: 0-1) to RGB (0-255 each).
  static List<int> _hsvToRgb(double h, double s, double v) {
    final i = (h * 6).floor();
    final f = h * 6 - i;
    final p = v * (1 - s);
    final q = v * (1 - f * s);
    final t = v * (1 - (1 - f) * s);
    double r, g, b;
    switch (i % 6) {
      case 0: r = v; g = t; b = p; break;
      case 1: r = q; g = v; b = p; break;
      case 2: r = p; g = v; b = t; break;
      case 3: r = p; g = q; b = v; break;
      case 4: r = t; g = p; b = v; break;
      default: r = v; g = p; b = q; break;
    }
    return [(r * 255).round(), (g * 255).round(), (b * 255).round()];
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
      'Early_Blight': 'Early Blight',
      'Healthy': 'Healthy',
      'Leaf_Miner': 'Leaf Miner',
      'Leaf_Mold': 'Leaf Mold',
      'Not_Tomato': 'Not a Tomato Leaf',
    };
    return names[label] ?? label.replaceAll('_', ' ');
  }
}

/// Result of a single TFLite inference run.
class TFLiteResult {
  final String label;
  final int index;
  final double confidence;

  /// Gap between top-1 and top-2 confidence. A small gap (<0.15) means the
  /// model is uncertain even if the absolute confidence is above 60%.
  final double confidenceGap;

  const TFLiteResult({
    required this.label,
    required this.index,
    required this.confidence,
    this.confidenceGap = 1.0,
  });

  /// True when the model's top two predictions are close together,
  /// indicating ambiguity regardless of absolute confidence.
  bool get isAmbiguous => confidenceGap < 0.15 && confidence < 0.80;

  String get displayName => TFLiteService.getDisplayName(label);
  String get confidenceLabel => TFLiteService.getConfidenceLabel(confidence);
  String get confidencePercent =>
      '${(confidence * 100).toStringAsFixed(1)}%';
}

/// Helper to await a [ui.Image] from [ui.decodeImageFromPixels].
class _ImageCompleter {
  final _completer = Completer<ui.Image>();
  Future<ui.Image> get future => _completer.future;
  void complete(ui.Image image) => _completer.complete(image);
}
