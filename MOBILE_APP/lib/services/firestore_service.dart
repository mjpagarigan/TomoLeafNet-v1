import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/scan_model.dart';
import '../models/user_model.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get user profile document
  Future<UserModel?> getUserProfile(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromFirestore(doc);
  }

  /// Update user profile fields
  Future<void> updateUserProfile(String uid, Map<String, dynamic> data) async {
    await _firestore.collection('users').doc(uid).update(data);
  }

  /// Save a new scan result under users/{uid}/scans/{scanId}
  Future<String> saveScan({
    required String uid,
    required String predictedDisease,
    required double confidenceScore,
    required String confidenceLabel,
    String? imageUrl,
    GeoPoint? gpsCoordinates,
  }) async {
    final docRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('scans')
        .doc();

    final scan = ScanModel(
      scanId: docRef.id,
      uid: uid,
      imageUrl: imageUrl,
      predictedDisease: predictedDisease,
      confidenceScore: confidenceScore,
      confidenceLabel: confidenceLabel,
      timestamp: DateTime.now(),
      gpsCoordinates: gpsCoordinates,
    );

    await docRef.set(scan.toFirestore());
    return docRef.id;
  }

  /// Update the imageUrl for a scan after upload completes
  Future<void> updateScanImageUrl(String uid, String scanId, String imageUrl) async {
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('scans')
        .doc(scanId)
        .update({'imageUrl': imageUrl});
  }

  /// Real-time stream of user's scans ordered by timestamp descending
  Stream<List<ScanModel>> getUserScansStream(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('scans')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => ScanModel.fromFirestore(doc)).toList());
  }

  /// Delete a scan document
  Future<void> deleteScan(String uid, String scanId) async {
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('scans')
        .doc(scanId)
        .delete();
  }
}
