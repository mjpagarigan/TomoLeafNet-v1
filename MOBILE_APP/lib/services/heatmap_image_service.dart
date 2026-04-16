import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class HeatmapImageService {
  const HeatmapImageService._();

  static Future<String?> resolveImagePath({
    String? localImagePath,
    String? remoteImageUrl,
    String? cacheKey,
  }) async {
    if (localImagePath != null && localImagePath.isNotEmpty) {
      final file = File(localImagePath);
      if (await file.exists()) {
        return file.path;
      }
    }

    if (remoteImageUrl == null || remoteImageUrl.isEmpty) {
      return null;
    }

    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory('${tempDir.path}/gradcam_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    final uri = Uri.parse(remoteImageUrl);
    final extension = _extensionFor(uri);
    final fallbackKey =
        uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'scan';
    final safeKey = _safeCacheKey(cacheKey ?? fallbackKey);
    final cachedFile = File('${cacheDir.path}/$safeKey$extension');

    if (await cachedFile.exists() && await cachedFile.length() > 0) {
      return cachedFile.path;
    }

    final response = await http
        .get(uri)
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      throw Exception('Unable to load image for Grad-CAM.');
    }

    await cachedFile.writeAsBytes(response.bodyBytes, flush: true);
    return cachedFile.path;
  }

  static String _safeCacheKey(String raw) {
    final sanitized = raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return sanitized.isEmpty ? 'scan' : sanitized;
  }

  static String _extensionFor(Uri uri) {
    final path = uri.path.toLowerCase();
    if (path.endsWith('.png')) return '.png';
    if (path.endsWith('.webp')) return '.webp';
    return '.jpg';
  }
}
