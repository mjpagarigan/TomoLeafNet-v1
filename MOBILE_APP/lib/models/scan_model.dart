import 'package:cloud_firestore/cloud_firestore.dart';

class ScanModel {
  final String scanId;
  final String uid;
  final String? imageUrl;
  final String predictedDisease;
  final String? disease2;
  final double confidenceScore;
  final double? secondConfidence;
  final String confidenceLabel;
  final String? thresholdState;
  final DateTime timestamp;
  final GeoPoint? gpsCoordinates;
  final String scanType; // "identify" or "diagnose"
  final List<String>? treatmentSteps; // only populated for "diagnose" scans
  final String? userRating;
  final String? contributionId;
  final String? contributionPromptStatus;

  ScanModel({
    required this.scanId,
    required this.uid,
    this.imageUrl,
    required this.predictedDisease,
    this.disease2,
    required this.confidenceScore,
    this.secondConfidence,
    required this.confidenceLabel,
    this.thresholdState,
    required this.timestamp,
    this.gpsCoordinates,
    this.scanType = 'identify',
    this.treatmentSteps,
    this.userRating,
    this.contributionId,
    this.contributionPromptStatus,
  });

  factory ScanModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ScanModel(
      scanId: doc.id,
      uid: data['uid'] ?? '',
      imageUrl: data['imageUrl'],
      predictedDisease: data['predictedDisease'] ?? '',
      disease2: data['disease2'],
      confidenceScore: (data['confidenceScore'] as num?)?.toDouble() ?? 0.0,
      secondConfidence: (data['secondConfidence'] as num?)?.toDouble(),
      confidenceLabel: data['confidenceLabel'] ?? '',
      thresholdState: data['thresholdState'],
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      gpsCoordinates: data['gpsCoordinates'] as GeoPoint?,
      scanType: data['scanType'] ?? 'identify', // backward compat
      treatmentSteps: (data['treatmentSteps'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      userRating: data['userRating'],
      contributionId: data['contributionId'],
      contributionPromptStatus: data['contributionPromptStatus'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'imageUrl': imageUrl,
      'predictedDisease': predictedDisease,
      'disease2': disease2,
      'confidenceScore': confidenceScore,
      'secondConfidence': secondConfidence,
      'confidenceLabel': confidenceLabel,
      'thresholdState': thresholdState,
      'timestamp': Timestamp.fromDate(timestamp),
      'gpsCoordinates': gpsCoordinates,
      'scanType': scanType,
      if (treatmentSteps != null) 'treatmentSteps': treatmentSteps,
      'userRating': userRating,
      'contributionId': contributionId,
      'contributionPromptStatus': contributionPromptStatus,
    };
  }

  static String getConfidenceLabel(double confidence) {
    if (confidence >= 0.80) return "High Confidence";
    if (confidence >= 0.60) return "Moderate Confidence";
    if (confidence >= 0.40) return "Low Confidence";
    return "Very Low Confidence";
  }
}
