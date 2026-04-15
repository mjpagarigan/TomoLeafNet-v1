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

    // Convert YUV → RGBA in a background isolate.
    // Pass plane byte views directly — compute() handles the transfer.
    final rgbaBytes = await compute(
      _convertCameraImage,
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

    if (rgbaBytes == null) {
      return const DetectionResult(
        label: notTomatoLeafLabel,
        confidence: 0.0,
      );
    }

    // Build a flat Float32List input tensor — avoids ~200K nested list objects
    // that the old List<List<List<List<double>>>> approach created per frame.
    final input = _buildInputTensor(rgbaBytes, cameraImage.width, cameraImage.height);

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

  /// Builds a [1, 224, 224, 3] Float32List tensor from the viewfinder region.
  /// Uses a single contiguous buffer instead of nested Lists to minimize
  /// GC pressure during real-time detection (~3 FPS).
  Object _buildInputTensor(
    Uint8List rgbaBytes,
    int width,
    int height,
  ) {
    final boxSize = (width * viewfinderFraction).round();
    final cropX = (width - boxSize) ~/ 2;
    final cropY =
        (height - boxSize) ~/ 2 - (viewfinderVerticalOffset * height ~/ 800);

    final safeX = cropX.clamp(0, width - 1);
    final safeY = cropY.clamp(0, height - 1);
    final safeW = boxSize.clamp(1, width - safeX);
    final safeH = boxSize.clamp(1, height - safeY);

    final buffer = Float32List(1 * inputSize * inputSize * 3);
    int idx = 0;
    final maxPixelIdx = rgbaBytes.length - 3;

    for (int y = 0; y < inputSize; y++) {
      final srcY = safeY + (y * safeH ~/ inputSize);
      for (int x = 0; x < inputSize; x++) {
        final srcX = safeX + (x * safeW ~/ inputSize);
        final pixelIdx = (srcY * width + srcX) * 4;

        if (pixelIdx >= 0 && pixelIdx < maxPixelIdx) {
          buffer[idx] = rgbaBytes[pixelIdx] / 127.5 - 1.0;
          buffer[idx + 1] = rgbaBytes[pixelIdx + 1] / 127.5 - 1.0;
          buffer[idx + 2] = rgbaBytes[pixelIdx + 2] / 127.5 - 1.0;
        }
        idx += 3;
      }
    }

    return buffer.reshape([1, inputSize, inputSize, 3]);
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}

Uint8List? _convertCameraImage(_CameraImageData data) {
  final width = data.width;
  final height = data.height;

  try {
    if (data.formatGroupRaw == ImageFormatGroup.yuv420.index &&
        data.planes.length >= 3) {
      final yPlane = data.planes[0];
      final uPlane = data.planes[1];
      final vPlane = data.planes[2];
      final rgba = Uint8List(width * height * 4);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final yIndex = y * yPlane.bytesPerRow + x;
          final uvIndex = (y ~/ 2) * uPlane.bytesPerRow +
              (x ~/ 2) * (uPlane.bytesPerPixel ?? 1);

          final yValue = yPlane.bytes[yIndex];
          final uValue =
              uvIndex < uPlane.bytes.length ? uPlane.bytes[uvIndex] : 128;
          final vValue =
              uvIndex < vPlane.bytes.length ? vPlane.bytes[uvIndex] : 128;

          final r = (yValue + 1.370705 * (vValue - 128))
              .round()
              .clamp(0, 255);
          final g = (yValue -
                  0.337633 * (uValue - 128) -
                  0.698001 * (vValue - 128))
              .round()
              .clamp(0, 255);
          final b = (yValue + 1.732446 * (uValue - 128))
              .round()
              .clamp(0, 255);

          final rgbaIndex = (y * width + x) * 4;
          rgba[rgbaIndex] = r;
          rgba[rgbaIndex + 1] = g;
          rgba[rgbaIndex + 2] = b;
          rgba[rgbaIndex + 3] = 255;
        }
      }

      return rgba;
    }

    if (data.planes.length == 1) {
      final plane = data.planes[0];
      final rgba = Uint8List(width * height * 4);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final srcIndex = y * plane.bytesPerRow + x * 4;
          final dstIndex = (y * width + x) * 4;

          if (srcIndex + 3 >= plane.bytes.length) {
            continue;
          }

          rgba[dstIndex] = plane.bytes[srcIndex + 2];
          rgba[dstIndex + 1] = plane.bytes[srcIndex + 1];
          rgba[dstIndex + 2] = plane.bytes[srcIndex];
          rgba[dstIndex + 3] = 255;
        }
      }

      return rgba;
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
