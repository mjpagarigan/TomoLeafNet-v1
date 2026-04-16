import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class DetectionResult {
  const DetectionResult({
    required this.label,
    required this.confidence,
  });

  final String label;
  final double confidence;

  bool get isTomatoLeaf =>
      label == LeafDetectorService.tomatoLeafLabel &&
      confidence >= LeafDetectorService.tomatoLeafThreshold;
}

class LeafDetectorService {
  static const String notTomatoLeafLabel = 'not_tomato_leaf';
  static const String tomatoLeafLabel = 'tomato_leaf';
  static const List<String> labels = [notTomatoLeafLabel, tomatoLeafLabel];

  static const double tomatoLeafThreshold = 0.75;
  static const int inputSize = 224;
  static const double viewfinderFraction = 0.80;
  static const double viewfinderVerticalOffset = 40.0;

  Interpreter? _interpreter;

  bool get isReady => _interpreter != null;

  Future<void> loadModel() async {
    _interpreter = await Interpreter.fromAsset(
      'assets/tomoleafnet_detector.tflite',
    );
  }

  Future<DetectionResult> detect(CameraImage cameraImage) async {
    if (_interpreter == null) {
      throw StateError('Detector model not loaded. Call loadModel() first.');
    }

    // Build the detector tensor in a background isolate so the UI thread
    // avoids both full-frame color conversion and crop/resize work.
    final input = await compute(
      _cameraImageToTensor,
      _CameraImageData(
        planes: cameraImage.planes
            .map(
              (plane) => _PlaneData(
                bytes: plane.bytes,
                bytesPerRow: plane.bytesPerRow,
                bytesPerPixel: plane.bytesPerPixel,
              ),
            )
            .toList(),
        width: cameraImage.width,
        height: cameraImage.height,
        formatGroupRaw: cameraImage.format.group.index,
      ),
    );

    if (input == null) {
      return const DetectionResult(
        label: notTomatoLeafLabel,
        confidence: 0.0,
      );
    }

    final output = List.filled(labels.length, 0.0).reshape([1, labels.length]);
    _interpreter!.run(input, output);

    final probabilities = (output[0] as List<double>);
    int bestIndex = 0;
    double bestScore = probabilities[0];
    for (int i = 1; i < probabilities.length; i++) {
      if (probabilities[i] > bestScore) {
        bestIndex = i;
        bestScore = probabilities[i];
      }
    }

    return DetectionResult(
      label: labels[bestIndex],
      confidence: bestScore,
    );
  }
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}

Object? _cameraImageToTensor(_CameraImageData data) {
  final width = data.width;
  final height = data.height;
  final boxSize = (width * LeafDetectorService.viewfinderFraction).round();
  final cropX = (width - boxSize) ~/ 2;
  final cropY = (height - boxSize) ~/ 2 -
      (LeafDetectorService.viewfinderVerticalOffset * height ~/ 800);
  final safeX = cropX.clamp(0, width - 1);
  final safeY = cropY.clamp(0, height - 1);
  final safeW = boxSize.clamp(1, width - safeX);
  final safeH = boxSize.clamp(1, height - safeY);
  final buffer = Float32List(
    1 * LeafDetectorService.inputSize * LeafDetectorService.inputSize * 3,
  );

  try {
    if (data.formatGroupRaw == ImageFormatGroup.yuv420.index &&
        data.planes.length >= 3) {
      final yPlane = data.planes[0];
      final uPlane = data.planes[1];
      final vPlane = data.planes[2];
      int idx = 0;
      for (int y = 0; y < LeafDetectorService.inputSize; y++) {
        final srcY = safeY + (y * safeH ~/ LeafDetectorService.inputSize);
        for (int x = 0; x < LeafDetectorService.inputSize; x++) {
          final srcX = safeX + (x * safeW ~/ LeafDetectorService.inputSize);
          final yIndex = srcY * yPlane.bytesPerRow + srcX;
          final uvIndex = (srcY ~/ 2) * uPlane.bytesPerRow +
              (srcX ~/ 2) * (uPlane.bytesPerPixel ?? 1);

          final yValue = yPlane.bytes[yIndex];
          final uValue = uvIndex < uPlane.bytes.length ? uPlane.bytes[uvIndex] : 128;
          final vValue = uvIndex < vPlane.bytes.length ? vPlane.bytes[uvIndex] : 128;

          buffer[idx++] =
              ((yValue + 1.370705 * (vValue - 128)).clamp(0, 255) / 127.5) - 1.0;
          buffer[idx++] = ((yValue -
                      0.337633 * (uValue - 128) -
                      0.698001 * (vValue - 128))
                  .clamp(0, 255) /
              127.5) -
              1.0;
          buffer[idx++] =
              ((yValue + 1.732446 * (uValue - 128)).clamp(0, 255) / 127.5) - 1.0;
        }
      }
      return buffer.reshape([1, LeafDetectorService.inputSize, LeafDetectorService.inputSize, 3]);
    }

    if (data.planes.length == 1) {
      final plane = data.planes[0];
      int idx = 0;
      for (int y = 0; y < LeafDetectorService.inputSize; y++) {
        final srcY = safeY + (y * safeH ~/ LeafDetectorService.inputSize);
        for (int x = 0; x < LeafDetectorService.inputSize; x++) {
          final srcX = safeX + (x * safeW ~/ LeafDetectorService.inputSize);
          final srcIndex = srcY * plane.bytesPerRow + srcX * 4;

          if (srcIndex + 3 >= plane.bytes.length) {
            buffer[idx++] = 0.0;
            buffer[idx++] = 0.0;
            buffer[idx++] = 0.0;
            continue;
          }

          buffer[idx++] = (plane.bytes[srcIndex + 2] / 127.5) - 1.0;
          buffer[idx++] = (plane.bytes[srcIndex + 1] / 127.5) - 1.0;
          buffer[idx++] = (plane.bytes[srcIndex] / 127.5) - 1.0;
        }
      }
      return buffer.reshape([1, LeafDetectorService.inputSize, LeafDetectorService.inputSize, 3]);
    }
  } catch (_) {
    return null;
  }

  return null;
}

class _CameraImageData {
  const _CameraImageData({
    required this.planes,
    required this.width,
    required this.height,
    required this.formatGroupRaw,
  });

  final List<_PlaneData> planes;
  final int width;
  final int height;
  final int formatGroupRaw;
}

class _PlaneData {
  const _PlaneData({
    required this.bytes,
    required this.bytesPerRow,
    this.bytesPerPixel,
  });

  final Uint8List bytes;
  final int bytesPerRow;
  final int? bytesPerPixel;
}
