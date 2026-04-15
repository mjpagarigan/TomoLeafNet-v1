import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';

/// Service for calling the /diagnose endpoint on the Render-hosted backend.
///
/// Sends the detected disease name and confidence score, receives
/// AI-generated treatment steps from Groq Cloud (Llama 3.1 8B Instant).
class DiagnoseService {
  /// Request treatment steps for a detected disease.
  ///
  /// [disease] is the raw label from TFLite inference (e.g. "Early_Blight").
  /// [confidence] is the confidence score as a percentage (e.g. 68.7).
  ///
  /// Returns a list of numbered treatment step strings.
  /// Throws on network errors or server failures.
  Future<List<String>> getTreatmentSteps({
    required String disease,
    required double confidence,
  }) async {
    final uri = Uri.parse(AppConfig.diagnoseBackendUrl);

    final body = jsonEncode({
      'disease': disease,
      'confidence': confidence,
    });

    try {
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final steps = (data['steps'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList();
        if (steps != null && steps.isNotEmpty) {
          return steps;
        }
        throw Exception('No treatment steps returned from the server.');
      } else {
        final detail = _extractDetail(response.body);
        throw Exception(detail);
      }
    } on http.ClientException {
      throw Exception(
        'Treatment advice unavailable. Please check your connection and try again.',
      );
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception(
        'Treatment advice unavailable. Please check your connection and try again.',
      );
    }
  }

  String _extractDetail(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      return data['detail'] as String? ?? 'Server error ($data)';
    } catch (_) {
      return 'Server error: $body';
    }
  }
}
