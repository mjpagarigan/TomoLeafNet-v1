import 'package:cloud_firestore/cloud_firestore.dart';

class ScanModel {
  final String scanId;
  final String uid;
  final String? imageUrl;
  final String? thumbnailUrl;
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
  final String? originalPredictedDisease;
  final String? userValidatedDisease;
  final DateTime? validatedAt;
  final String? correctionRequestedDisease;
  final String? correctionRequestStatus;
  final DateTime? correctionRequestedAt;

  ScanModel({
    required this.scanId,
    required this.uid,
    this.imageUrl,
    this.thumbnailUrl,
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
    this.originalPredictedDisease,
    this.userValidatedDisease,
    this.validatedAt,
    this.correctionRequestedDisease,
    this.correctionRequestStatus,
    this.correctionRequestedAt,
  });

  factory ScanModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ScanModel(
      scanId: doc.id,
      uid: data['uid'] ?? '',
      imageUrl: data['imageUrl'],
      thumbnailUrl: data['thumbnailUrl'],
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
      originalPredictedDisease: data['originalPredictedDisease'],
      userValidatedDisease: data['userValidatedDisease'],
      validatedAt: (data['validatedAt'] as Timestamp?)?.toDate(),
      correctionRequestedDisease: data['correctionRequestedDisease'],
      correctionRequestStatus: data['correctionRequestStatus'],
      correctionRequestedAt:
          (data['correctionRequestedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'imageUrl': imageUrl,
      'thumbnailUrl': thumbnailUrl,
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
      'originalPredictedDisease': originalPredictedDisease,
      'userValidatedDisease': userValidatedDisease,
      'validatedAt':
          validatedAt == null ? null : Timestamp.fromDate(validatedAt!),
      'correctionRequestedDisease': correctionRequestedDisease,
      'correctionRequestStatus': correctionRequestStatus,
      'correctionRequestedAt': correctionRequestedAt == null
          ? null
          : Timestamp.fromDate(correctionRequestedAt!),
    };
  }

  static String getConfidenceLabel(double confidence) {
    if (confidence >= 0.80) return "High Confidence";
    if (confidence >= 0.60) return "Moderate Confidence";
    if (confidence >= 0.40) return "Low Confidence";
    return "Very Low Confidence";
  }

  String? get previewImageUrl {
    if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty) return thumbnailUrl;
    if (imageUrl != null && imageUrl!.isNotEmpty) return imageUrl;
    return null;
  }
}
