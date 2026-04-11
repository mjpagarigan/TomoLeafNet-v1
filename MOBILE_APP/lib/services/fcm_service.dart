import 'package:firebase_messaging/firebase_messaging.dart';

/// Thin wrapper around Firebase Cloud Messaging that exposes the device
/// token and listens for refreshes. The token is sent to the Render backend
/// (via [RemindersBackend]) when reminders are created or updated.
class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  String? _cachedToken;
  String? get cachedToken => _cachedToken;

  /// Optional callback fired whenever the FCM token is refreshed by the OS.
  /// Use this to re-sync the token to any reminder records that need it.
  void Function(String token)? onTokenRefresh;

  Future<void> init() async {
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    try {
      _cachedToken = await _messaging.getToken();
    } catch (_) {
      _cachedToken = null;
    }

    _messaging.onTokenRefresh.listen((token) {
      _cachedToken = token;
      onTokenRefresh?.call(token);
    });
  }

  /// Force-refresh the cached token. Useful before scheduling a reminder if
  /// the token wasn't ready at app launch.
  Future<String?> ensureToken() async {
    if (_cachedToken != null) return _cachedToken;
    try {
      _cachedToken = await _messaging.getToken();
    } catch (_) {}
    return _cachedToken;
  }
}
