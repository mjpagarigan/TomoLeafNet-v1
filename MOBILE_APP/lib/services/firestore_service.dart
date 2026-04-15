import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/contribution_stats.dart';
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

  /// Real-time stream of the user profile document.
  Stream<UserModel?> getUserProfileStream(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserModel.fromFirestore(doc);
    });
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
    String? disease2,
    GeoPoint? gpsCoordinates,
    double? secondConfidence,
    String? thresholdState,
    List<String>? treatmentSteps,
    String? userRating,
    String? contributionId,
    String? contributionPromptStatus,
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
      disease2: disease2,
      confidenceScore: confidenceScore,
      secondConfidence: secondConfidence,
      confidenceLabel: confidenceLabel,
      thresholdState: thresholdState,
      timestamp: DateTime.now(),
      gpsCoordinates: gpsCoordinates,
      scanType: scanType,
      treatmentSteps: treatmentSteps,
      userRating: userRating,
      contributionId: contributionId,
      contributionPromptStatus: contributionPromptStatus,
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

  /// Persist the user's accuracy feedback on a saved scan.
  Future<void> updateScanFeedback({
    required String uid,
    required String scanId,
    required String userRating,
    String? contributionId,
    String? contributionPromptStatus,
  }) async {
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('scans')
        .doc(scanId)
        .update({
      'userRating': userRating,
      if (contributionId != null) 'contributionId': contributionId,
      if (contributionPromptStatus != null)
        'contributionPromptStatus': contributionPromptStatus,
    });
  }

  /// Update only the scan's contribution prompt status.
  Future<void> updateScanContributionPromptStatus({
    required String uid,
    required String scanId,
    required String contributionPromptStatus,
  }) async {
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('scans')
        .doc(scanId)
        .update({'contributionPromptStatus': contributionPromptStatus});
  }

  /// Create the canonical contribution metadata document.
  Future<void> createCommunityContribution({
    required String contributionId,
    required String ownerUid,
    required String imageStoragePath,
    String? imageDownloadUrl,
    required String predictedDisease,
    String? disease2,
    required double topConfidence,
    double? secondConfidence,
    required String thresholdState,
    String? region,
    required String appVersion,
    required String modelVersion,
  }) async {
    await _firestore
        .collection('community_contributions')
        .doc(contributionId)
        .set({
      'contributionId': contributionId,
      'ownerUid': ownerUid,
      'imageStoragePath': imageStoragePath,
      'imageDownloadUrl': imageDownloadUrl,
      'predictedDisease': predictedDisease,
      'disease2': disease2,
      'topConfidence': topConfidence,
      'secondConfidence': secondConfidence,
      'thresholdState': thresholdState,
      'userRating': 'thumbs_up',
      'region': region,
      'contributedAt': FieldValue.serverTimestamp(),
      'appVersion': appVersion,
      'modelVersion': modelVersion,
      'isVerified': false,
      'isApprovedForTraining': false,
      'deletionRequested': false,
      'deletionRequestedAt': null,
    });
  }

  /// Mirror each contribution into the admin review queue.
  Future<void> createAdminReviewQueueEntry({
    required String contributionId,
    required String ownerUid,
    String? imageDownloadUrl,
    required String predictedDisease,
    required String thresholdState,
    required double topConfidence,
    String? region,
  }) async {
    await _firestore.collection('admin_review_queue').doc(contributionId).set({
      'contributionId': contributionId,
      'ownerUid': ownerUid,
      'imageDownloadUrl': imageDownloadUrl,
      'predictedDisease': predictedDisease,
      'thresholdState': thresholdState,
      'topConfidence': topConfidence,
      'region': region,
      'contributedAt': FieldValue.serverTimestamp(),
      'reviewStatus': 'pending',
      'reviewedAt': null,
      'deletionRequested': false,
      'deletionRequestedAt': null,
    });
  }

  /// Real-time contribution stats for the signed-in user.
  Stream<ContributionStats> getContributionStatsStream(String uid) {
    return _firestore
        .collection('community_contributions')
        .where('ownerUid', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
      var approved = 0;
      var pending = 0;
      var usedInTraining = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final isVerified = data['isVerified'] == true;
        final isApprovedForTraining = data['isApprovedForTraining'] == true;

        if (isVerified) {
          approved++;
        } else {
          pending++;
        }

        if (isApprovedForTraining) {
          usedInTraining++;
        }
      }

      return ContributionStats(
        total: snapshot.docs.length,
        approved: approved,
        pendingReview: pending,
        usedInTraining: usedInTraining,
      );
    });
  }

  /// Persist the user's permanent contribution opt-out preference.
  Future<void> setContributionOptOut(String uid, bool value) async {
    await _firestore.collection('users').doc(uid).update({
      'contributionOptOut': value,
    });
  }

  /// Mark all of the user's contributions for admin-side deletion review.
  Future<void> requestContributionDeletion(String uid) async {
    final snapshot = await _firestore
        .collection('community_contributions')
        .where('ownerUid', isEqualTo: uid)
        .get();

    if (snapshot.docs.isEmpty) return;

    final batch = _firestore.batch();
    final now = FieldValue.serverTimestamp();

    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {
        'deletionRequested': true,
        'deletionRequestedAt': now,
      });

      final queueRef = _firestore.collection('admin_review_queue').doc(doc.id);
      final queueDoc = await queueRef.get();
      if (queueDoc.exists) {
        batch.update(queueRef, {
          'deletionRequested': true,
          'deletionRequestedAt': now,
        });
      } else {
        batch.set(queueRef, {
          'contributionId': doc.id,
          'ownerUid': uid,
          'imageDownloadUrl': doc.data()['imageDownloadUrl'],
          'predictedDisease': doc.data()['predictedDisease'],
          'thresholdState': doc.data()['thresholdState'],
          'topConfidence': doc.data()['topConfidence'],
          'region': doc.data()['region'],
          'contributedAt':
              doc.data()['contributedAt'] ?? FieldValue.serverTimestamp(),
          'reviewStatus': doc.data()['isApprovedForTraining'] == true
              ? 'approved'
              : 'pending',
          'reviewedAt': null,
          'deletionRequested': true,
          'deletionRequestedAt': now,
        });
      }
    }

    await batch.commit();
  }
}
