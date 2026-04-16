import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as img;

class UploadedScanImage {
  const UploadedScanImage({
    required this.imageUrl,
    required this.thumbnailUrl,
  });

  final String imageUrl;
  final String thumbnailUrl;
}

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Upload an optimized full image plus a lightweight thumbnail.
  Future<UploadedScanImage> uploadScanImage({
    required String uid,
    required String scanId,
    required String localImagePath,
  }) async {
    final prepared = await compute(_prepareScanUploadAssets, localImagePath);
    final imageRef = _storage.ref().child('scan_images/$uid/$scanId.jpg');
    final thumbnailRef = _storage.ref().child(
      'scan_images/$uid/thumbnails/$scanId.jpg',
    );
    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      customMetadata: {'uploadedBy': uid},
    );

    await Future.wait([
      imageRef.putData(prepared.fullImageBytes, metadata),
      thumbnailRef.putData(prepared.thumbnailBytes, metadata),
    ]);

    final urls = await Future.wait([
      imageRef.getDownloadURL(),
      thumbnailRef.getDownloadURL(),
    ]);

    return UploadedScanImage(
      imageUrl: urls[0],
      thumbnailUrl: urls[1],
    );
  }

  /// Delete a scan image from Cloud Storage
  Future<void> deleteScanImage({
    required String uid,
    required String scanId,
  }) async {
    try {
      await Future.wait([
        _storage.ref().child('scan_images/$uid/$scanId.jpg').delete(),
        _storage.ref().child('scan_images/$uid/thumbnails/$scanId.jpg').delete(),
      ]);
    } on FirebaseException catch (e) {
      // Ignore 'object-not-found' errors (image may not have been uploaded)
      if (e.code != 'object-not-found') rethrow;
    }
  }

  /// Upload a contributed dataset image to the shared community dataset path.
  UploadTask uploadCommunityContributionImage({
    required String thresholdState,
    required String diseaseClass,
    required String contributionId,
    required String localImagePath,
  }) {
    final file = File(localImagePath);
    final ref = _storage
        .ref()
        .child(
            'community_dataset/$thresholdState/$diseaseClass/$contributionId.jpg');

    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      customMetadata: {
        'thresholdState': thresholdState,
        'diseaseClass': diseaseClass,
        'contributionId': contributionId,
      },
    );

    return ref.putFile(file, metadata);
  }

  Future<String?> tryGetDownloadUrl(String storagePath) async {
    try {
      return await _storage.ref().child(storagePath).getDownloadURL();
    } on FirebaseException {
      return null;
    }
  }

  Future<void> deleteCommunityContributionImage(String imageStoragePath) async {
    try {
      await _storage.ref().child(imageStoragePath).delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
  }
}

class _PreparedScanUploadAssets {
  const _PreparedScanUploadAssets({
    required this.fullImageBytes,
    required this.thumbnailBytes,
  });

  final Uint8List fullImageBytes;
  final Uint8List thumbnailBytes;
}

_PreparedScanUploadAssets _prepareScanUploadAssets(String localImagePath) {
  final bytes = File(localImagePath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);

  if (decoded == null) {
    return _PreparedScanUploadAssets(
      fullImageBytes: Uint8List.fromList(bytes),
      thumbnailBytes: Uint8List.fromList(bytes),
    );
  }

  final optimized = img.copyResize(
    decoded,
    width: decoded.width >= decoded.height ? 1280 : null,
    height: decoded.height > decoded.width ? 1280 : null,
    interpolation: img.Interpolation.average,
  );

  final thumb = img.copyResize(
    decoded,
    width: decoded.width >= decoded.height ? 256 : null,
    height: decoded.height > decoded.width ? 256 : null,
    interpolation: img.Interpolation.average,
  );

  return _PreparedScanUploadAssets(
    fullImageBytes: Uint8List.fromList(img.encodeJpg(optimized, quality: 82)),
    thumbnailBytes: Uint8List.fromList(img.encodeJpg(thumb, quality: 72)),
  );
}
