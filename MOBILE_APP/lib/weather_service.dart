import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'services/cloud_functions_service.dart';

class WeatherData {
  final String cityName;
  final double tempMin;
  final double tempMax;
  final String condition; // e.g. "Clouds", "Clear", "Rain"
  final String iconCode; // OpenWeatherMap icon code

  WeatherData({
    required this.cityName,
    required this.tempMin,
    required this.tempMax,
    required this.condition,
    required this.iconCode,
  });
}

class WeatherService {

  /// Check location permission status without requesting
  static Future<String> checkPermissionStatus() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return 'service_disabled';

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) return 'denied_forever';
    if (permission == LocationPermission.denied) return 'denied';
    return 'granted';
  }

  /// Request location permission and get current position
  /// Returns a record with position and status string
  static Future<({Position? position, String status})> requestLocationWithStatus() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return (position: null, status: 'service_disabled');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return (position: null, status: 'denied');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return (position: null, status: 'denied_forever');
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 15),
      );
      return (position: position, status: 'granted');
    } catch (e) {
      print('Location fetch error: $e');
      return (position: null, status: 'error');
    }
  }

  /// Request location permission and get current position (legacy)
  static Future<Position?> _getCurrentPosition() async {
    final result = await requestLocationWithStatus();
    return result.position;
  }

  /// Reverse geocode coordinates to city name
  static Future<String> _getCityName(double lat, double lon) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lon);
      if (placemarks.isNotEmpty) {
        return placemarks.first.locality ??
            placemarks.first.subAdministrativeArea ??
            placemarks.first.administrativeArea ??
            'Unknown';
      }
    } catch (e) {
      print('Geocoding error: $e');
    }
    return 'Unknown';
  }

  /// Fetch weather data via Firebase Cloud Function proxy.
  /// API keys are stored securely on the server — never in the app.
  static Future<WeatherData?> fetchWeather() async {
    try {
      final position = await _getCurrentPosition();
      if (position == null) return null;

      final cityName = await _getCityName(position.latitude, position.longitude);

      try {
        final functionsService = CloudFunctionsService();
        final data = await functionsService.fetchWeather(
          latitude: position.latitude,
          longitude: position.longitude,
          cityName: cityName,
        );

        return WeatherData(
          cityName: data['cityName'] as String? ?? cityName,
          tempMin: (data['tempMin'] as num?)?.toDouble() ?? 0,
          tempMax: (data['tempMax'] as num?)?.toDouble() ?? 0,
          condition: data['condition'] as String? ?? 'unavailable',
          iconCode: data['iconCode'] as String? ?? '',
        );
      } catch (e) {
        print('Cloud Function weather error: $e');
        // Fallback: return location-only data if Cloud Function is not deployed yet
        return WeatherData(
          cityName: cityName,
          tempMin: 0,
          tempMax: 0,
          condition: 'unavailable',
          iconCode: '',
        );
      }
    } catch (e) {
      print('Weather fetch error: $e');
      return null;
    }
  }
}
