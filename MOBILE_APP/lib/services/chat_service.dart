import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';

/// Service for communicating with the Plant AI chat backend.
///
/// Sends user messages, conversation history, and recent scan history
/// to the FastAPI server, which forwards them to Groq Cloud
/// (Llama 3.1 8B Instant) with Tomo's agronomist persona and returns
/// the AI response.
class ChatService {
  /// Send a chat message to the Plant AI backend.
  ///
  /// [message] is the user's current text.
  /// [history] is the full conversation so far (list of maps with
  /// `role` and `text` keys).
  /// [scanHistory] is the user's 5 most recent scans (disease,
  /// confidence, confidenceLabel, scanType, timestamp) injected into
  /// Tomo's system prompt for context-aware responses.
  ///
  /// Returns the AI assistant's reply text.
  Future<String> sendMessage({
    required String message,
    required List<Map<String, String>> history,
    List<Map<String, dynamic>> scanHistory = const [],
  }) async {
    final uri = Uri.parse(AppConfig.chatBackendUrl);

    final body = jsonEncode({
      'message': message,
      'history': history,
      'scanHistory': scanHistory,
    });

    try {
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              // Bypass ngrok free-tier browser warning page
              'ngrok-skip-browser-warning': 'true',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['reply'] as String? ??
            'Sorry, I could not generate a response.';
      } else {
        final detail = _extractDetail(response.body);
        throw Exception(detail);
      }
    } on http.ClientException {
      throw Exception(
        'Unable to reach Plant AI backend.\n'
        'Ensure the FastAPI server and Ollama are running on your development machine.',
      );
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception(
        'Unable to reach Plant AI backend.\n'
        'Ensure the FastAPI server and Ollama are running on your development machine.',
      );
    }
  }

  /// Try to extract a human-readable detail from an error response body.
  String _extractDetail(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      return data['detail'] as String? ?? 'Server error ($data)';
    } catch (_) {
      return 'Server error: $body';
    }
  }
}
