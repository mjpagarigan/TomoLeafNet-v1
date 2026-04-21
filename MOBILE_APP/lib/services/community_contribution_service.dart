import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firestore_service.dart';
import 'storage_service.dart';

class ContributionUploadResult {
  final String contributionId;
  final bool uploaded;
  final bool queuedForRetry;

  const ContributionUploadResult({
    required this.contributionId,
    required this.uploaded,
    required this.queuedForRetry,
  });
}

class CommunityContributionService {
  CommunityContributionService._internal();

  static final CommunityContributionService instance =
      CommunityContributionService._internal();

  static const String _queueKey = 'communityContributionRetryQueue';
  static const String _modelVersion = 'tomoleafnet_v5';

  final _connectivity = Connectivity();
  final _firestoreService = FirestoreService();
  final _storageService = StorageService();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _initialized = false;
  bool _isProcessingQueue = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((results) {
      if (_hasConnection(results)) {
        unawaited(processPendingQueue());
      }
    });

    await processPendingQueue();
  }

  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _initialized = false;
  }

  Future<ContributionUploadResult> contributeScan({
    required String ownerUid,
    required String scanId,
    required String predictedDisease,
    String? disease2,
    required double topConfidence,
    double? secondConfidence,
    required String thresholdState,
    required String? localImagePath,
    String? remoteImageUrl,
    GeoPoint? gpsCoordinates,
    void Function(double progress)? onProgress,
  }) async {
    final contributionId = FirebaseFirestore.instance
        .collection('community_contributions')
        .doc()
        .id;

    final preparedImagePath = await _prepareContributionImage(
      contributionId: contributionId,
      localImagePath: localImagePath,
      remoteImageUrl: remoteImageUrl,
    );
    final region = await _resolveRegion(gpsCoordinates);
    final appVersion = await _getAppVersion();

    final payload = {
      'contributionId': contributionId,
      'ownerUid': ownerUid,
      'scanId': scanId,
      'preparedImagePath': preparedImagePath,
      'predictedDisease': predictedDisease,
      'disease2': disease2,
      'topConfidence': topConfidence,
      'secondConfidence': secondConfidence,
      'thresholdState': thresholdState,
      'region': region,
      'appVersion': appVersion,
      'modelVersion': _modelVersion,
    };

    try {
      await _uploadPayload(payload, onProgress: onProgress);
      return ContributionUploadResult(
        contributionId: contributionId,
        uploaded: true,
        queuedForRetry: false,
      );
    } catch (_) {
      await _enqueuePayload(payload);
      await _firestoreService.updateScanFeedback(
        uid: ownerUid,
        scanId: scanId,
        userRating: 'thumbs_up',
        contributionId: contributionId,
        contributionPromptStatus: 'accepted',
      );
      return ContributionUploadResult(
        contributionId: contributionId,
        uploaded: false,
        queuedForRetry: true,
      );
    }
  }

  Future<void> processPendingQueue() async {
    if (_isProcessingQueue) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _isProcessingQueue = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final queue = List<String>.from(prefs.getStringList(_queueKey) ?? const []);
      if (queue.isEmpty) return;

      final remaining = <String>[];
      for (final encoded in queue) {
        final payload = Map<String, dynamic>.from(jsonDecode(encoded));
        if (payload['ownerUid'] != user.uid) {
          remaining.add(encoded);
          continue;
        }

        try {
          await _uploadPayload(payload);
        } catch (_) {
          remaining.add(encoded);
        }
      }

      await prefs.setStringList(_queueKey, remaining);
    } finally {
      _isProcessingQueue = false;
    }
  }

  Future<void> _uploadPayload(
    Map<String, dynamic> payload, {
    void Function(double progress)? onProgress,
  }) async {
    final task = _storageService.uploadCommunityContributionImage(
      thresholdState: payload['thresholdState'],
      diseaseClass: payload['predictedDisease'],
      contributionId: payload['contributionId'],
      localImagePath: payload['preparedImagePath'],
    );

    StreamSubscription? subscription;
    if (onProgress != null) {
      subscription = task.snapshotEvents.listen((snapshot) {
        if (snapshot.totalBytes > 0) {
          onProgress(snapshot.bytesTransferred / snapshot.totalBytes);
        }
      });
    }

    final snapshot = await task;
    await subscription?.cancel();

    final imageStoragePath = snapshot.ref.fullPath;
    final downloadUrl = await _storageService.tryGetDownloadUrl(imageStoragePath);

    await _firestoreService.createCommunityContribution(
      contributionId: payload['contributionId'],
      ownerUid: payload['ownerUid'],
      imageStoragePath: imageStoragePath,
      imageDownloadUrl: downloadUrl,
      predictedDisease: payload['predictedDisease'],
      disease2: payload['disease2'],
      topConfidence: (payload['topConfidence'] as num).toDouble(),
      secondConfidence: (payload['secondConfidence'] as num?)?.toDouble(),
      thresholdState: payload['thresholdState'],
      region: payload['region'],
      appVersion: payload['appVersion'],
      modelVersion: payload['modelVersion'],
    );

    await _firestoreService.createAdminReviewQueueEntry(
      contributionId: payload['contributionId'],
      ownerUid: payload['ownerUid'],
      imageDownloadUrl: downloadUrl,
      predictedDisease: payload['predictedDisease'],
      thresholdState: payload['thresholdState'],
      topConfidence: (payload['topConfidence'] as num).toDouble(),
      region: payload['region'],
    );

    await _firestoreService.updateScanFeedback(
      uid: payload['ownerUid'],
      scanId: payload['scanId'],
      userRating: 'thumbs_up',
      contributionId: payload['contributionId'],
      contributionPromptStatus: 'accepted',
    );

    final queuedImage = File(payload['preparedImagePath']);
    if (await queuedImage.exists()) {
      await queuedImage.delete();
    }
  }

  Future<void> _enqueuePayload(Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = List<String>.from(prefs.getStringList(_queueKey) ?? const []);
    final contributionId = payload['contributionId'];

    final alreadyQueued = queue.any((item) {
      final decoded = Map<String, dynamic>.from(jsonDecode(item));
      return decoded['contributionId'] == contributionId;
    });
    if (alreadyQueued) return;

    queue.add(jsonEncode(payload));
    await prefs.setStringList(_queueKey, queue);
  }

  Future<String> _prepareContributionImage({
    required String contributionId,
    required String? localImagePath,
    String? remoteImageUrl,
  }) async {
    Uint8List sourceBytes;

    if (localImagePath != null && await File(localImagePath).exists()) {
      sourceBytes = await File(localImagePath).readAsBytes();
    } else if (remoteImageUrl != null && remoteImageUrl.isNotEmpty) {
      final response = await http.get(Uri.parse(remoteImageUrl));
      if (response.statusCode != 200) {
        throw Exception('Unable to download the saved scan image.');
      }
      sourceBytes = response.bodyBytes;
    } else {
      throw Exception('No image available for contribution upload.');
    }

    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) {
      throw Exception('Unable to prepare the contribution image.');
    }

    final encoded = img.encodeJpg(decoded, quality: 85);
    final directory = await _queueDirectory();
    final file = File('${directory.path}/$contributionId.jpg');
    await file.writeAsBytes(encoded, flush: true);
    return file.path;
  }

  Future<Directory> _queueDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}/community_contribution_queue');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<String?> _resolveRegion(GeoPoint? gpsCoordinates) async {
    if (gpsCoordinates == null) return null;

    try {
      final placemarks = await placemarkFromCoordinates(
        gpsCoordinates.latitude,
        gpsCoordinates.longitude,
      );
      if (placemarks.isEmpty) return null;

      final place = placemarks.first;
      final parts = <String>[
        if ((place.subAdministrativeArea ?? '').isNotEmpty)
          place.subAdministrativeArea!,
        if ((place.administrativeArea ?? '').isNotEmpty)
          place.administrativeArea!,
      ];

      final uniqueParts = <String>[];
      for (final part in parts) {
        if (!uniqueParts.contains(part)) {
          uniqueParts.add(part);
        }
      }

      return uniqueParts.isEmpty ? null : uniqueParts.join(', ');
    } catch (_) {
      return null;
    }
  }

  Future<String> _getAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }
}
