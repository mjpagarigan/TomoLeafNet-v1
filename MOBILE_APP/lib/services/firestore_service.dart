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
    required String scanType,
    String? imageUrl,
    GeoPoint? gpsCoordinates,
    List<String>? treatmentSteps,
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
      scanType: scanType,
      treatmentSteps: treatmentSteps,
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

  /// Upgrade an existing "identify" scan to "diagnose" after the user taps
  /// the Diagnose This Leaf button and treatment steps are retrieved.
  Future<void> upgradeScanToDiagnose({
    required String uid,
    required String scanId,
    required List<String> treatmentSteps,
  }) async {
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('scans')
        .doc(scanId)
        .update({
      'scanType': 'diagnose',
      'treatmentSteps': treatmentSteps,
    });
  }

  /// One-shot migration: rewrite any reminder whose plantName is
  /// "Solanum lycopersicum" to the user-friendly "Tomato" label.
  Future<void> migrateReminderPlantNameToTomato(String uid) async {
    final col = _firestore
        .collection('users')
        .doc(uid)
        .collection('reminders');
    final snap = await col
        .where('plantName', isEqualTo: 'Solanum lycopersicum')
        .get();
    if (snap.docs.isEmpty) return;
    final batch = _firestore.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'plantName': 'Tomato'});
    }
    await batch.commit();
  }

  /// One-shot fetch of the user's N most recent scans, ordered by timestamp
  /// descending. Used by the Plant AI chat to inject scan history context
  /// into each request.
  Future<List<ScanModel>> getRecentScans(String uid, {int limit = 5}) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(uid)
        .collection('scans')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs.map((doc) => ScanModel.fromFirestore(doc)).toList();
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
