import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'core/config/api_keys.dart';

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

  /// Fetch weather data from OpenWeatherMap
  static Future<WeatherData?> fetchWeather() async {
    try {
      final position = await _getCurrentPosition();
      if (position == null) return null;

      final cityName = await _getCityName(position.latitude, position.longitude);
      const apiKey = ApiKeys.openWeather;

      if (apiKey.isEmpty || apiKey == 'ADD_YOUR_OPENWEATHER_API_KEY_HERE') {
        // Return location-only data without weather
        return WeatherData(
          cityName: cityName,
          tempMin: 0,
          tempMax: 0,
          condition: 'unavailable',
          iconCode: '',
        );
      }

      final url = Uri.parse(
        'https://api.openweathermap.org/data/2.5/weather'
        '?lat=${position.latitude}'
        '&lon=${position.longitude}'
        '&appid=$apiKey'
        '&units=metric',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return WeatherData(
          cityName: cityName,
          tempMin: (data['main']['temp_min'] as num).toDouble(),
          tempMax: (data['main']['temp_max'] as num).toDouble(),
          condition: data['weather'][0]['main'] as String,
          iconCode: data['weather'][0]['icon'] as String,
        );
      } else {
        // API error — return location-only
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
