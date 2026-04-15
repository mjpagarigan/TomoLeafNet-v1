import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Upload a scan image to Cloud Storage at scan_images/{uid}/{scanId}.jpg
  /// Returns the download URL on success.
  Future<String> uploadScanImage({
    required String uid,
    required String scanId,
    required String localImagePath,
  }) async {
    final file = File(localImagePath);
    final ref = _storage.ref().child('scan_images/$uid/$scanId.jpg');

    // Use putFile with metadata for resumable upload
    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      customMetadata: {'uploadedBy': uid},
    );

    final uploadTask = ref.putFile(file, metadata);

    // Wait for upload to complete
    final snapshot = await uploadTask;

    // Get and return the download URL
    final downloadUrl = await snapshot.ref.getDownloadURL();
    return downloadUrl;
  }

  /// Delete a scan image from Cloud Storage
  Future<void> deleteScanImage({
    required String uid,
    required String scanId,
  }) async {
    try {
      final ref = _storage.ref().child('scan_images/$uid/$scanId.jpg');
      await ref.delete();
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
