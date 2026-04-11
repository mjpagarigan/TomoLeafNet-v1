import 'package:cloud_firestore/cloud_firestore.dart';

class ScanModel {
  final String scanId;
  final String uid;
  final String? imageUrl;
  final String predictedDisease;
  final double confidenceScore;
  final String confidenceLabel;
  final DateTime timestamp;
  final GeoPoint? gpsCoordinates;
  final String scanType; // "identify" or "diagnose"
  final List<String>? treatmentSteps; // only populated for "diagnose" scans

  ScanModel({
    required this.scanId,
    required this.uid,
    this.imageUrl,
    required this.predictedDisease,
    required this.confidenceScore,
    required this.confidenceLabel,
    required this.timestamp,
    this.gpsCoordinates,
    this.scanType = 'identify',
    this.treatmentSteps,
  });

  factory ScanModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ScanModel(
      scanId: doc.id,
      uid: data['uid'] ?? '',
      imageUrl: data['imageUrl'],
      predictedDisease: data['predictedDisease'] ?? '',
      confidenceScore: (data['confidenceScore'] as num?)?.toDouble() ?? 0.0,
      confidenceLabel: data['confidenceLabel'] ?? '',
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      gpsCoordinates: data['gpsCoordinates'] as GeoPoint?,
      scanType: data['scanType'] ?? 'identify', // backward compat
      treatmentSteps: (data['treatmentSteps'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'imageUrl': imageUrl,
      'predictedDisease': predictedDisease,
      'confidenceScore': confidenceScore,
      'confidenceLabel': confidenceLabel,
      'timestamp': Timestamp.fromDate(timestamp),
      'gpsCoordinates': gpsCoordinates,
      'scanType': scanType,
      if (treatmentSteps != null) 'treatmentSteps': treatmentSteps,
    };
  }

  static String getConfidenceLabel(double confidence) {
    if (confidence >= 0.80) return "High Confidence";
    if (confidence >= 0.60) return "Moderate Confidence";
    if (confidence >= 0.40) return "Low Confidence";
    return "Very Low Confidence";
  }
}
