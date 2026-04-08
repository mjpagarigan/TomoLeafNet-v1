import 'package:cloud_functions/cloud_functions.dart';

/// Service for calling Firebase Cloud Functions.
///
/// Currently provides weather data via the `weatherProxy` Cloud Function.
/// Chat functionality has been moved to [ChatService] which communicates
/// directly with the local Ollama backend.
class CloudFunctionsService {
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  /// Fetch weather data via Cloud Function proxy.
  /// Returns a map with cityName, tempMin, tempMax, condition, iconCode.
  Future<Map<String, dynamic>> fetchWeather({
    required double latitude,
    required double longitude,
    required String cityName,
  }) async {
    final callable = _functions.httpsCallable('weatherProxy');
    final result = await callable.call<Map<String, dynamic>>({
      'latitude': latitude,
      'longitude': longitude,
      'cityName': cityName,
    });
    return Map<String, dynamic>.from(result.data);
  }
}
