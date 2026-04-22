import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class TFLiteModelSpec {
  const TFLiteModelSpec({
    required this.id,
    required this.displayName,
    required this.assetPath,
    required this.modelVersion,
    required this.description,
    required this.supportsHeatmap,
    required this.expectsNormalizedInput,
  });

  final String id;
  final String displayName;
  final String assetPath;
  final String modelVersion;
  final String description;
  final bool supportsHeatmap;
  final bool expectsNormalizedInput;
}

/// Shared TFLite inference service used by both Identify and Diagnose flows.
///
/// Singleton: models are loaded once and shared across result screens, while
/// still allowing the user to switch between bundled classifiers.
class TFLiteService {
  static const String _selectedModelPrefKey = 'selectedTfliteModelId';

  static const TFLiteModelSpec mobileNetV3LargeModel = TFLiteModelSpec(
    id: 'tomoleafnet_v6',
    displayName: 'MobileNetV3 Large (v6)',
    assetPath: 'assets/tomoleafnet_v6.tflite',
    modelVersion: 'tomoleafnet_v6',
    description: 'Default production classifier used by the current app.',
    supportsHeatmap: true,
    expectsNormalizedInput: false,
  );

  static const TFLiteModelSpec mobileNetV2Model = TFLiteModelSpec(
    id: 'tomoleafnet_v2',
    displayName: 'MobileNetV2 (v2)',
    assetPath: 'assets/tomoleafnet_v2.tflite',
    modelVersion: 'tomoleafnet_v2',
    description: 'Alternative comparison model trained with the same pipeline.',
    supportsHeatmap: false,
    expectsNormalizedInput: true,
  );

  static const List<TFLiteModelSpec> availableModels = [
    mobileNetV3LargeModel,
    mobileNetV2Model,
  ];

  static final ValueNotifier<TFLiteModelSpec> selectedModelListenable =
      ValueNotifier<TFLiteModelSpec>(mobileNetV3LargeModel);

  static const List<String> supportedLabels = [
    'Early_Blight',
    'Healthy',
    'Leaf_Miner',
    'Leaf_Mold',
    'Not_Tomato',
  ];

  static final TFLiteService _instance = TFLiteService._internal();
  factory TFLiteService() => _instance;
  TFLiteService._internal();

  Interpreter? _interpreter;
  Interpreter? _camInterpreter;
  List<String>? _labels;
  Future<void>? _camLoadFuture;
  Future<void>? _selectionLoadFuture;
  bool _selectionLoaded = false;
  String? _loadedModelId;

  /// Output index for predictions [1,5] in the CAM model.
  int _camPredIndex = 1;

  /// Output index for CAM maps [1,7,7,5] in the CAM model.
  int _camMapsIndex = 0;

  bool get isReady => _interpreter != null && _labels != null;
  List<String>? get labels => _labels;
  TFLiteModelSpec get currentModel => selectedModelListenable.value;
  String get currentModelVersion => currentModel.modelVersion;
  bool get supportsHeatmap => currentModel.supportsHeatmap;

  static TFLiteModelSpec modelFromId(String? id) {
    for (final model in availableModels) {
      if (model.id == id) return model;
    }
    return mobileNetV3LargeModel;
  }

  static String getModelDisplayName(String? modelVersion) {
    return modelFromId(modelVersion).displayName.replaceFirst(
          RegExp(r'\s*\(v\d+\)$'),
          '',
        );
  }

  Future<void> initializeModelSelection() async {
    if (_selectionLoaded) return;
    _selectionLoadFuture ??= _restoreSelectedModel();
    await _selectionLoadFuture;
  }

  Future<void> _restoreSelectedModel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final selectedId = prefs.getString(_selectedModelPrefKey);
      final restoredModel = modelFromId(selectedId);
      if (selectedModelListenable.value.id != restoredModel.id) {
        selectedModelListenable.value = restoredModel;
      }
      _selectionLoaded = true;
    } finally {
      _selectionLoadFuture = null;
    }
  }

  Future<void> setActiveModel(String modelId) async {
    await initializeModelSelection();
    final nextModel = modelFromId(modelId);
    if (nextModel.id == currentModel.id) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedModelPrefKey, nextModel.id);
    selectedModelListenable.value = nextModel;

    _closeLoadedModels();
    await loadModel(forceReload: true);
  }

  /// Load the selected TFLite model and class labels from assets.
  Future<void> loadModel({bool forceReload = false}) async {
    await initializeModelSelection();
    if (!forceReload &&
        _interpreter != null &&
        _labels != null &&
        _loadedModelId == currentModel.id) {
      return;
    }

    _interpreter?.close();
    _interpreter = null;
    _loadedModelId = null;

    if (!currentModel.supportsHeatmap) {
      _camInterpreter?.close();
      _camInterpreter = null;
      _camLoadFuture = null;
    }

    _interpreter = await Interpreter.fromAsset(currentModel.assetPath);
    _loadedModelId = currentModel.id;

    final inputTensor = _interpreter!.getInputTensors()[0];
    final outputTensor = _interpreter!.getOutputTensors()[0];
    debugPrint(
      'Loaded ${currentModel.displayName}: input ${inputTensor.shape}, '
      'type ${inputTensor.type}',
    );
    debugPrint(
      'Output shape: ${outputTensor.shape}, type: ${outputTensor.type}',
    );

    final labelData = await rootBundle.loadString('assets/labels.txt');
    _labels = labelData.split('\n').where((s) => s.trim().isNotEmpty).toList();
    debugPrint('Labels loaded: $_labels');
  }

  Future<void> _ensureCamModelLoaded() async {
    if (!supportsHeatmap) {
      throw UnsupportedError(
        '${currentModel.displayName} does not include a bundled heatmap model.',
      );
    }
    if (_camInterpreter != null) return;

    _camLoadFuture ??= () async {
      _camInterpreter =
          await Interpreter.fromAsset('assets/tomoleafnet_v4_cam.tflite');
      final outputs = _camInterpreter!.getOutputTensors();
      for (int i = 0; i < outputs.length; i++) {
        final shape = outputs[i].shape;
        if (shape.length == 4 && shape[3] == 5) {
          _camMapsIndex = i;
        } else if (shape.length == 2 && shape[1] == 5) {
          _camPredIndex = i;
        }
      }
      debugPrint('CAM model loaded: pred=$_camPredIndex, cam=$_camMapsIndex');
    }();

    try {
      await _camLoadFuture;
    } finally {
      _camLoadFuture = null;
    }
  }

  /// Preprocess an image file into a Float32List suitable for the model.
  ///
  /// Applies center-crop + bilinear resize to 224x224, then feeds either raw
  /// pixels or [-1, 1] normalized values depending on the selected model.
  Future<Float32List> preprocessImage(String imagePath) async {
    await initializeModelSelection();
    return compute(
      _preprocessImageFile,
      _PreprocessImageRequest(
        imagePath: imagePath,
        expectsNormalizedInput: currentModel.expectsNormalizedInput,
      ),
    );
  }

  /// Run inference on the preprocessed image buffer.
  ///
  /// Returns a [TFLiteResult] with the predicted label, index, and confidence.
  TFLiteResult runInference(Float32List inputBuffer) {
    if (_interpreter == null || _labels == null) {
      throw Exception('Model not loaded. Call loadModel() first.');
    }

    final input = inputBuffer.reshape([1, 224, 224, 3]);
    final numClasses = _labels!.length;
    final output = List.filled(1 * numClasses, 0.0).reshape([1, numClasses]);

    _interpreter!.run(input, output);

    final probabilities = output[0] as List<double>;

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
  TFLiteResult runInferenceOnFrame(
    Uint8List rgbaBytes,
    int width,
    int height, {
    double viewfinderFraction = 0.80,
  }) {
    if (_interpreter == null || _labels == null) {
      throw Exception('Model not loaded. Call loadModel() first.');
    }

    final int boxSize = (width * viewfinderFraction).round();
    final int cropX = (width - boxSize) ~/ 2;
    final int cropY = (height - boxSize) ~/ 2 - (40 * height ~/ 800);

    final int safeX = cropX.clamp(0, width - 1);
    final int safeY = cropY.clamp(0, height - 1);
    final int safeW = boxSize.clamp(1, width - safeX);
    final int safeH = boxSize.clamp(1, height - safeY);

    const int targetSize = 224;
    final expectsNormalizedInput = currentModel.expectsNormalizedInput;
    final inputBuffer = Float32List(1 * targetSize * targetSize * 3);
    int bufIdx = 0;

    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {
        final int srcX = safeX + (x * safeW ~/ targetSize);
        final int srcY = safeY + (y * safeH ~/ targetSize);
        final int pixelIdx = (srcY * width + srcX) * 4;

        if (pixelIdx + 2 < rgbaBytes.length) {
          final r = rgbaBytes[pixelIdx].toDouble();
          final g = rgbaBytes[pixelIdx + 1].toDouble();
          final b = rgbaBytes[pixelIdx + 2].toDouble();
          if (expectsNormalizedInput) {
            inputBuffer[bufIdx++] = r / 127.5 - 1.0;
            inputBuffer[bufIdx++] = g / 127.5 - 1.0;
            inputBuffer[bufIdx++] = b / 127.5 - 1.0;
          } else {
            inputBuffer[bufIdx++] = r;
            inputBuffer[bufIdx++] = g;
            inputBuffer[bufIdx++] = b;
          }
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
  Future<Uint8List> generateHeatmap(String imagePath, int classIndex) async {
    if (!isReady) await loadModel();
    await _ensureCamModelLoaded();

    final baseBuffer = await preprocessImage(imagePath);

    const int imgSize = 224;
    const int camSize = 7;
    const int numClasses = 5;

    if (_camInterpreter == null) {
      throw Exception('CAM model not loaded');
    }

    final input = baseBuffer.reshape([1, imgSize, imgSize, 3]);

    final predOutput =
        List.filled(1 * numClasses, 0.0).reshape([1, numClasses]);
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

    final preds = predOutput[0] as List<double>;
    int predClass = classIndex;
    if (predClass < 0 || predClass >= numClasses) {
      double maxP = -1;
      for (int i = 0; i < preds.length; i++) {
        if (preds[i] > maxP) {
          maxP = preds[i];
          predClass = i;
        }
      }
    }

    final cam7x7 = List.generate(camSize, (y) {
      return List.generate(camSize, (x) {
        final double value = camOutput[0][y][x][predClass];
        return value > 0 ? value : 0.0;
      });
    });

    double camMax = 0.0;
    for (final row in cam7x7) {
      for (final value in row) {
        if (value > camMax) camMax = value;
      }
    }
    if (camMax > 0) {
      for (int y = 0; y < camSize; y++) {
        for (int x = 0; x < camSize; x++) {
          cam7x7[y][x] /= camMax;
        }
      }
    }

    return compute(
      _buildHeatmapPng,
      _HeatmapBuildData(
        baseBuffer: baseBuffer,
        cam7x7: cam7x7,
      ),
    );
  }

  /// Dispose interpreters.
  void dispose() {
    _closeLoadedModels();
  }

  void _closeLoadedModels() {
    _interpreter?.close();
    _interpreter = null;
    _loadedModelId = null;
    _labels = null;
    _camInterpreter?.close();
    _camInterpreter = null;
    _camLoadFuture = null;
    _camPredIndex = 1;
    _camMapsIndex = 0;
  }

  static String getConfidenceLabel(double confidence) {
    if (confidence >= 0.80) return 'High Confidence';
    if (confidence >= 0.60) return 'Moderate Confidence';
    if (confidence >= 0.40) return 'Low Confidence';
    return 'Very Low Confidence';
  }

  static Color getConfidenceColor(double confidence) {
    if (confidence >= 0.80) return const Color(0xFF4CAF50);
    if (confidence >= 0.60) return const Color(0xFFFF9800);
    if (confidence >= 0.40) return const Color(0xFFFFC107);
    return const Color(0xFFF44336);
  }

  static String getThresholdLabel(String label, double confidence) {
    if (label == 'Healthy') {
      if (confidence >= 0.80) return 'Confident Healthy';
      return 'Monitor';
    }
    if (confidence >= 0.85) return 'Confirmed';
    return 'Likely';
  }

  static Color getThresholdColor(String label, double confidence) {
    if (label == 'Healthy') {
      if (confidence >= 0.80) return const Color(0xFF4CAF50);
      return const Color(0xFFFFC107);
    }
    if (confidence >= 0.85) return const Color(0xFFF44336);
    return const Color(0xFFFF9800);
  }

  static String getThresholdTitle(String label, double confidence) {
    if (label == 'Healthy') {
      if (confidence >= 0.80) return 'Great news!';
      return 'Looks okay, but keep watch.';
    }
    final name = getDisplayName(label);
    if (confidence >= 0.85) return 'Confirmed: $name.';
    return 'Heads up! It might be $name.';
  }

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

  static String getThresholdIcon(String label, double confidence) {
    if (label == 'Healthy') {
      if (confidence >= 0.80) return 'GREEN';
      return 'YELLOW';
    }
    if (confidence >= 0.85) return 'RED';
    return 'ORANGE';
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

  static int getLabelIndex(String label) {
    final index = supportedLabels.indexOf(label);
    return index >= 0 ? index : 0;
  }

  static String getThresholdState(String label, double confidence) {
    if (label == 'Healthy') {
      return confidence >= 0.80 ? 'confidentHealthy' : 'monitor';
    }
    if (label == 'Not_Tomato') return 'rejection';
    return confidence >= 0.85 ? 'confidentDisease' : 'likely';
  }

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
  const TFLiteResult({
    required this.label,
    required this.index,
    required this.confidence,
    this.secondLabel,
    this.secondIndex,
    this.secondConfidence = 0.0,
    this.confidenceGap = 1.0,
  });

  final String label;
  final int index;
  final double confidence;
  final String? secondLabel;
  final int? secondIndex;
  final double secondConfidence;

  /// Gap between top-1 and top-2 confidence.
  final double confidenceGap;

  bool get isAmbiguous => confidenceGap < 0.15 && confidence < 0.80;
  String get displayName => TFLiteService.getDisplayName(label);
  String get confidenceLabel => TFLiteService.getConfidenceLabel(confidence);
  String get confidencePercent => '${(confidence * 100).toStringAsFixed(1)}%';
  String get thresholdState =>
      TFLiteService.getThresholdState(label, confidence);
  int get thresholdStateNumber =>
      TFLiteService.getThresholdStateNumber(label, confidence);
}

class _PreprocessImageRequest {
  const _PreprocessImageRequest({
    required this.imagePath,
    required this.expectsNormalizedInput,
  });

  final String imagePath;
  final bool expectsNormalizedInput;
}

class _HeatmapBuildData {
  const _HeatmapBuildData({
    required this.baseBuffer,
    required this.cam7x7,
  });

  final Float32List baseBuffer;
  final List<List<double>> cam7x7;
}

Float32List _preprocessImageFile(_PreprocessImageRequest request) {
  final bytes = File(request.imagePath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw Exception('Failed to decode image');
  }

  final minDim =
      decoded.width < decoded.height ? decoded.width : decoded.height;
  final cropX = (decoded.width - minDim) ~/ 2;
  final cropY = (decoded.height - minDim) ~/ 2;
  final cropped = img.copyCrop(
    decoded,
    x: cropX,
    y: cropY,
    width: minDim,
    height: minDim,
  );
  final resized = img.copyResize(
    cropped,
    width: 224,
    height: 224,
    interpolation: img.Interpolation.average,
  );

  final inputBuffer = Float32List(1 * 224 * 224 * 3);
  int idx = 0;
  for (int y = 0; y < 224; y++) {
    for (int x = 0; x < 224; x++) {
      final pixel = resized.getPixel(x, y);
      final r = pixel.r.toDouble();
      final g = pixel.g.toDouble();
      final b = pixel.b.toDouble();

      if (request.expectsNormalizedInput) {
        inputBuffer[idx++] = r / 127.5 - 1.0;
        inputBuffer[idx++] = g / 127.5 - 1.0;
        inputBuffer[idx++] = b / 127.5 - 1.0;
      } else {
        inputBuffer[idx++] = r;
        inputBuffer[idx++] = g;
        inputBuffer[idx++] = b;
      }
    }
  }
  return inputBuffer;
}

Uint8List _buildHeatmapPng(_HeatmapBuildData data) {
  const imgSize = 224;
  const camSize = 7;
  final image = img.Image(width: imgSize, height: imgSize);

  final lut = List<List<int>>.generate(256, (i) {
    final val = i / 255.0;
    final hue = 0.66 * (1.0 - val);
    return _hsvToRgbValue(hue, 1.0, 1.0);
  });

  for (int y = 0; y < imgSize; y++) {
    for (int x = 0; x < imgSize; x++) {
      final srcIdx = (y * imgSize + x) * 3;
      final gxCenter = (x + 0.5) * camSize / imgSize - 0.5;
      final gyCenter = (y + 0.5) * camSize / imgSize - 0.5;
      final gx0 = gxCenter.floor().clamp(0, camSize - 1);
      final gx1 = (gx0 + 1).clamp(0, camSize - 1);
      final gy0 = gyCenter.floor().clamp(0, camSize - 1);
      final gy1 = (gy0 + 1).clamp(0, camSize - 1);
      final fx = (gxCenter - gx0).clamp(0.0, 1.0);
      final fy = (gyCenter - gy0).clamp(0.0, 1.0);
      final val = data.cam7x7[gy0][gx0] * (1 - fx) * (1 - fy) +
          data.cam7x7[gy0][gx1] * fx * (1 - fy) +
          data.cam7x7[gy1][gx0] * (1 - fx) * fy +
          data.cam7x7[gy1][gx1] * fx * fy;

      final lutIdx = (val * 255).round().clamp(0, 255);
      final hsvColor = lut[lutIdx];
      final origR = data.baseBuffer[srcIdx].clamp(0, 255).round();
      final origG = data.baseBuffer[srcIdx + 1].clamp(0, 255).round();
      final origB = data.baseBuffer[srcIdx + 2].clamp(0, 255).round();

      image.setPixelRgb(
        x,
        y,
        ((origR * 0.6) + (hsvColor[0] * 0.4)).round().clamp(0, 255),
        ((origG * 0.6) + (hsvColor[1] * 0.4)).round().clamp(0, 255),
        ((origB * 0.6) + (hsvColor[2] * 0.4)).round().clamp(0, 255),
      );
    }
  }

  return Uint8List.fromList(img.encodePng(image));
}

List<int> _hsvToRgbValue(double h, double s, double v) {
  final i = (h * 6).floor();
  final f = h * 6 - i;
  final p = v * (1 - s);
  final q = v * (1 - f * s);
  final t = v * (1 - (1 - f) * s);
  double r;
  double g;
  double b;

  switch (i % 6) {
    case 0:
      r = v;
      g = t;
      b = p;
      break;
    case 1:
      r = q;
      g = v;
      b = p;
      break;
    case 2:
      r = p;
      g = v;
      b = t;
      break;
    case 3:
      r = p;
      g = q;
      b = v;
      break;
    case 4:
      r = t;
      g = p;
      b = v;
      break;
    default:
      r = v;
      g = p;
      b = q;
      break;
  }

  return [(r * 255).round(), (g * 255).round(), (b * 255).round()];
}
