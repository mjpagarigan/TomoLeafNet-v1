import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';
import '../models/reminder_model.dart';

/// Thrown when the backend explicitly rejects a reminder request (e.g. 400).
class ReminderBackendException implements Exception {
  final String message;
  const ReminderBackendException(this.message);
  @override
  String toString() => message;
}

/// HTTP client for the Render-hosted FastAPI reminder endpoints:
///   POST /reminders/schedule
///   POST /reminders/update
///   POST /reminders/cancel
///
/// All methods are best-effort: failures are caught and logged so the
/// local notification + Firestore write still succeed when the backend is
/// unavailable. 400 errors are surfaced as [ReminderBackendException].
class RemindersBackend {
  RemindersBackend._();
  static final RemindersBackend instance = RemindersBackend._();

  Future<bool> schedule({
    required String uid,
    required String fcmToken,
    required ReminderModel reminder,
  }) async {
    return _post(AppConfig.reminderScheduleUrl, {
      'reminderId': reminder.reminderId,
      'uid': uid,
      'fcmToken': fcmToken,
      'category': reminder.category.value,
      'plantName': reminder.plantName,
      'repeat': reminder.repeat.value,
      'startDate':
          '${reminder.startDate.year.toString().padLeft(4, '0')}-${reminder.startDate.month.toString().padLeft(2, '0')}-${reminder.startDate.day.toString().padLeft(2, '0')}',
      'notifyTime':
          '${reminder.notifyTime.hour.toString().padLeft(2, '0')}:${reminder.notifyTime.minute.toString().padLeft(2, '0')}',
      'waterAmount': reminder.waterAmount,
    });
  }

  Future<bool> update({
    required String uid,
    required String fcmToken,
    required ReminderModel reminder,
  }) async {
    return _post(AppConfig.reminderUpdateUrl, {
      'reminderId': reminder.reminderId,
      'uid': uid,
      'fcmToken': fcmToken,
      'category': reminder.category.value,
      'plantName': reminder.plantName,
      'repeat': reminder.repeat.value,
      'startDate':
          '${reminder.startDate.year.toString().padLeft(4, '0')}-${reminder.startDate.month.toString().padLeft(2, '0')}-${reminder.startDate.day.toString().padLeft(2, '0')}',
      'notifyTime':
          '${reminder.notifyTime.hour.toString().padLeft(2, '0')}:${reminder.notifyTime.minute.toString().padLeft(2, '0')}',
      'waterAmount': reminder.waterAmount,
    });
  }

  Future<bool> cancel({
    required String uid,
    required String reminderId,
  }) async {
    return _post(AppConfig.reminderCancelUrl, {
      'reminderId': reminderId,
      'uid': uid,
    });
  }

  Future<bool> _post(String url, Map<String, dynamic> body) async {
    try {
      final resp = await http
          .post(
            Uri.parse(url),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return true;
      }
      if (resp.statusCode == 400) {
        try {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          throw ReminderBackendException(
            data['error'] as String? ?? 'Invalid request.',
          );
        } catch (e) {
          if (e is ReminderBackendException) rethrow;
          throw const ReminderBackendException('Invalid request.');
        }
      }
      return false;
    } catch (e) {
      if (e is ReminderBackendException) rethrow;
      return false;
    }
  }
}
