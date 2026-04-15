import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Color;

import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Shared TFLite inference service used by both Identify and Diagnose flows.
///
/// Singleton — models are loaded once and shared across all result screens,
/// avoiding repeated 3MB+ asset loads every time a scan result is displayed.
class TFLiteService {
  // ── Singleton ──────────────────────────────────────────────────────
  static final TFLiteService _instance = TFLiteService._internal();
  factory TFLiteService() => _instance;
  TFLiteService._internal();

  Interpreter? _interpreter;
  Interpreter? _camInterpreter;
  List<String>? _labels;

  /// Output index for predictions [1,5] in the CAM model.
  int _camPredIndex = 1;
  /// Output index for CAM maps [1,7,7,5] in the CAM model.
  int _camMapsIndex = 0;

  bool get isReady => _interpreter != null && _labels != null;
  List<String>? get labels => _labels;

  /// Load the TFLite model and class labels from assets.
  Future<void> loadModel() async {
    _interpreter = await Interpreter.fromAsset('assets/tomoleafnet_v4.tflite');

    final inputTensor = _interpreter!.getInputTensors()[0];
    final outputTensor = _interpreter!.getOutputTensors()[0];
    print("Input shape: ${inputTensor.shape}, type: ${inputTensor.type}");
    print("Output shape: ${outputTensor.shape}, type: ${outputTensor.type}");

    // Load dual-output CAM model for heatmap generation
    try {
      _camInterpreter =
          await Interpreter.fromAsset('assets/tomoleafnet_v4_cam.tflite');
      // Detect output index mapping (TFLite may reorder outputs)
      final outputs = _camInterpreter!.getOutputTensors();
      for (int i = 0; i < outputs.length; i++) {
        final shape = outputs[i].shape;
        if (shape.length == 4 && shape[3] == 5) {
          _camMapsIndex = i;
        } else if (shape.length == 2 && shape[1] == 5) {
          _camPredIndex = i;
        }
      }
      print("CAM model loaded: pred=$_camPredIndex, cam=$_camMapsIndex");
    } catch (e) {
      print("CAM model not available, falling back to occlusion: $e");
    }

    final labelData = await rootBundle.loadString('assets/labels.txt');
    _labels = labelData.split('\n').where((s) => s.trim().isNotEmpty).toList();
    print("Labels loaded: $_labels");
  }

  /// Preprocess an image file into a Float32List suitable for the model.
  ///
  /// Applies center-crop + bilinear resize to 224×224.
  /// MobileNetV3 handles normalization internally, so raw [0, 255] is passed.
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

          // MobileNetV3 handles normalization internally — pass raw [0, 255]
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

    // Find top-1 and top-2 predictions
    double top1Prob = -1.0;
    double top2Prob = -1.0;
    int top1Index = 0;
    int top2Index = 0;
    for (int i = 0; i < probabilities.length; i++) {
      if (probabilities[i] > top1Prob) {
        top2Prob = top1Prob;
        top2Index = top1Index;
        top1Prob = probabilities[i];
        top1Index = i;
      } else if (probabilities[i] > top2Prob) {
        top2Prob = probabilities[i];
        top2Index = i;
      }
    }

    final confidenceGap = top1Prob - (top2Prob < 0 ? 0.0 : top2Prob);

    return TFLiteResult(
      label: _labels![top1Index],
      index: top1Index,
      confidence: top1Prob,
      confidenceGap: confidenceGap,
      secondLabel: _labels![top2Index],
      secondIndex: top2Index,
      secondConfidence: top2Prob < 0 ? 0.0 : top2Prob,
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
          inputBuffer[bufIdx++] = rgbaBytes[pixelIdx].toDouble();       // R
          inputBuffer[bufIdx++] = rgbaBytes[pixelIdx + 1].toDouble();   // G
          inputBuffer[bufIdx++] = rgbaBytes[pixelIdx + 2].toDouble();   // B
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

  /// Generate a CAM (Class Activation Map) heatmap for the given image.
  ///
  /// Uses the dual-output CAM model that produces both predictions and a
  /// [1, 7, 7, 5] CAM tensor in a single forward pass — no extra inferences.
  /// The 7×7 CAM is bilinearly upscaled to 224×224 and blended with the
  /// original image. Returns PNG bytes.
  Future<Uint8List> generateHeatmap(String imagePath, int classIndex) async {
    if (!isReady) await loadModel();

    final baseBuffer = await preprocessImage(imagePath);

    const int imgSize = 224;
    const int camSize = 7;
    const int numClasses = 5;

    // ── Run CAM model (single inference) ─────────────────────────────
    if (_camInterpreter == null) {
      throw Exception("CAM model not loaded");
    }

    final input = baseBuffer.reshape([1, imgSize, imgSize, 3]);

    // Allocate output buffers for both outputs
    final predOutput = List.filled(1 * numClasses, 0.0).reshape([1, numClasses]);
    final camOutput = List.generate(
      1,
      (_) => List.generate(
        camSize,
        (_) => List.generate(camSize, (_) => List.filled(numClasses, 0.0)),
      ),
    );

    final outputs = <int, Object>{};
    outputs[_camPredIndex] = predOutput;
    outputs[_camMapsIndex] = camOutput;

    _camInterpreter!.runForMultipleInputs([input], outputs);

    // Extract the 7×7 CAM for the predicted class
    final preds = predOutput[0] as List<double>;
    int predClass = classIndex;
    if (predClass < 0 || predClass >= numClasses) {
      // Fallback: use argmax of predictions
      double maxP = -1;
      for (int i = 0; i < preds.length; i++) {
        if (preds[i] > maxP) {
          maxP = preds[i];
          predClass = i;
        }
      }
    }

    // Extract 7×7 CAM grid for the predicted class
    final cam7x7 = List.generate(camSize, (y) {
      return List.generate(camSize, (x) {
        final double v = camOutput[0][y][x][predClass];
        return v > 0 ? v : 0.0; // ReLU
      });
    });

    // Normalize to [0, 1]
    double camMax = 0.0;
    for (final row in cam7x7) {
      for (final v in row) {
        if (v > camMax) camMax = v;
      }
    }
    if (camMax > 0) {
      for (int y = 0; y < camSize; y++) {
        for (int x = 0; x < camSize; x++) {
          cam7x7[y][x] /= camMax;
        }
      }
    }

    // ── Bilinear upscale 7×7 → 224×224 and blend with original ──────
    // Pre-compute the HSV lookup table (256 entries)
    final lut = List<List<int>>.generate(256, (i) {
      final val = i / 255.0;
      final hue = 0.66 * (1.0 - val);
      return _hsvToRgb(hue, 1.0, 1.0);
    });

    final pixels = Uint8List(imgSize * imgSize * 4);
    for (int y = 0; y < imgSize; y++) {
      for (int x = 0; x < imgSize; x++) {
        final srcIdx = (y * imgSize + x) * 3;
        final dstIdx = (y * imgSize + x) * 4;

        // Map 224×224 pixel to 7×7 CAM grid with bilinear interpolation
        final gxCenter = (x + 0.5) * camSize / imgSize - 0.5;
        final gyCenter = (y + 0.5) * camSize / imgSize - 0.5;
        final gx0 = gxCenter.floor().clamp(0, camSize - 1);
        final gx1 = (gx0 + 1).clamp(0, camSize - 1);
        final gy0 = gyCenter.floor().clamp(0, camSize - 1);
        final gy1 = (gy0 + 1).clamp(0, camSize - 1);
        final fx = (gxCenter - gx0).clamp(0.0, 1.0);
        final fy = (gyCenter - gy0).clamp(0.0, 1.0);
        final val = cam7x7[gy0][gx0] * (1 - fx) * (1 - fy) +
            cam7x7[gy0][gx1] * fx * (1 - fy) +
            cam7x7[gy1][gx0] * (1 - fx) * fy +
            cam7x7[gy1][gx1] * fx * fy;

        final lutIdx = (val * 255).round().clamp(0, 255);
        final hsvColor = lut[lutIdx];

        final origR = baseBuffer[srcIdx].clamp(0, 255);
        final origG = baseBuffer[srcIdx + 1].clamp(0, 255);
        final origB = baseBuffer[srcIdx + 2].clamp(0, 255);

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

  /// Dispose interpreters.
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _camInterpreter?.close();
    _camInterpreter = null;
  }

  // ── Confidence helpers ──────────────────────────────────────────────

  static String getConfidenceLabel(double confidence) {
    if (confidence >= 0.80) return "High Confidence";
    if (confidence >= 0.60) return "Moderate Confidence";
    if (confidence >= 0.40) return "Low Confidence";
    return "Very Low Confidence";
  }

  static Color getConfidenceColor(double confidence) {
    if (confidence >= 0.80) return const Color(0xFF4CAF50);
    if (confidence >= 0.60) return const Color(0xFFFF9800);
    if (confidence >= 0.40) return const Color(0xFFFFC107);
    return const Color(0xFFF44336);
  }

  // ── Threshold tier helpers (PDF steps 5–8) ──────────────────────────

  /// Returns the threshold tier label for the result display header.
  static String getThresholdLabel(String label, double confidence) {
    if (label == 'Healthy') {
      if (confidence >= 0.80) return 'Confident Healthy';
      return 'Monitor';
    }
    // Disease
    if (confidence >= 0.85) return 'Confirmed';
    return 'Likely';
  }

  /// Returns the threshold tier color.
  static Color getThresholdColor(String label, double confidence) {
    if (label == 'Healthy') {
      if (confidence >= 0.80) return const Color(0xFF4CAF50); // green
      return const Color(0xFFFFC107); // amber
    }
    if (confidence >= 0.85) return const Color(0xFFF44336); // red
    return const Color(0xFFFF9800); // orange
  }

  /// Returns the threshold tier title text (PDF friendly wording).
  static String getThresholdTitle(String label, double confidence) {
    if (label == 'Healthy') {
      if (confidence >= 0.80) return 'Great news!';
      return 'Looks okay, but keep watch.';
    }
    final name = getDisplayName(label);
    if (confidence >= 0.85) return 'Confirmed: $name.';
    return 'Heads up! It might be $name.';
  }

  /// Returns the threshold tier body text (PDF friendly wording).
  static String getThresholdBody(String label, double confidence) {
    if (label == 'Healthy') {
      if (confidence >= 0.80) {
        return 'Your tomato leaf appears to be completely healthy. Keep up the great work!';
      }
      return 'Your plant seems mostly healthy, but it\'s best to keep monitoring it for the next few days just in case.';
    }
    if (confidence >= 0.85) {
      return 'We are highly confident your plant has this issue. Check out the details and comparison photos below to see if they match your plant.';
    }
    return 'We\'re seeing some signs of this issue. Let\'s review the symptoms together to make sure.';
  }

  /// Returns the threshold tier icon string.
  static String getThresholdIcon(String label, double confidence) {
    if (label == 'Healthy') {
      if (confidence >= 0.80) return '🟢';
      return '🟡';
    }
    if (confidence >= 0.85) return '🔴';
    return '🟠';
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

  /// Stable threshold-state identifiers for analytics and contribution routing.
  static String getThresholdState(String label, double confidence) {
    if (label == 'Healthy') {
      return confidence >= 0.80 ? 'confidentHealthy' : 'monitor';
    }
    if (label == 'Not_Tomato') return 'rejection';
    return confidence >= 0.85 ? 'confidentDisease' : 'likely';
  }

  /// Internal mapping of the app's PDF-inspired threshold states.
  static int getThresholdStateNumber(String label, double confidence) {
    switch (getThresholdState(label, confidence)) {
      case 'likely':
        return 6;
      case 'confidentDisease':
        return 7;
      case 'confidentHealthy':
        return 8;
      case 'monitor':
        return 5;
      default:
        return 0;
    }
  }
}

/// Result of a single TFLite inference run.
class TFLiteResult {
  final String label;
  final int index;
  final double confidence;
  final String? secondLabel;
  final int? secondIndex;
  final double secondConfidence;

  /// Gap between top-1 and top-2 confidence. A small gap (<0.15) means the
  /// model is uncertain even if the absolute confidence is above 60%.
  final double confidenceGap;

  const TFLiteResult({
    required this.label,
    required this.index,
    required this.confidence,
    this.secondLabel,
    this.secondIndex,
    this.secondConfidence = 0.0,
    this.confidenceGap = 1.0,
  });

  /// True when the model's top two predictions are close together,
  /// indicating ambiguity regardless of absolute confidence.
  bool get isAmbiguous => confidenceGap < 0.15 && confidence < 0.80;

  String get displayName => TFLiteService.getDisplayName(label);
  String get confidenceLabel => TFLiteService.getConfidenceLabel(confidence);
  String get confidencePercent =>
      '${(confidence * 100).toStringAsFixed(1)}%';
  String get thresholdState =>
      TFLiteService.getThresholdState(label, confidence);
  int get thresholdStateNumber =>
      TFLiteService.getThresholdStateNumber(label, confidence);
}

/// Helper to await a [ui.Image] from [ui.decodeImageFromPixels].
class _ImageCompleter {
  final _completer = Completer<ui.Image>();
  Future<ui.Image> get future => _completer.future;
  void complete(ui.Image image) => _completer.complete(image);
}
