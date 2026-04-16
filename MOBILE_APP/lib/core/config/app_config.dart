/// Application configuration constants for TomoLeafNet.
///
/// The Plant AI chat backend URL supports four modes. Change
/// [backendMode] below to switch between them:
///
///   - [BackendMode.render]    → Cloud-hosted FastAPI on Render (works anywhere, 24/7)
///   - [BackendMode.ngrok]     → Local FastAPI exposed via ngrok public tunnel
///   - [BackendMode.localWifi] → Local FastAPI on same WiFi as dev machine
///   - [BackendMode.emulator]  → Local FastAPI reached from Android emulator
///
/// Production builds should use [BackendMode.render].
enum BackendMode { render, ngrok, localWifi, emulator }

class AppConfig {
  AppConfig._();

  // ── Switch this to change chat backend target ──────────────────────
  static const BackendMode backendMode = BackendMode.render;

  // ── Mode-specific configuration ────────────────────────────────────

  /// Render-hosted FastAPI URL (used in [BackendMode.render]).
  /// Set this after deploying the backend to Render.
  /// Example: 'https://tomoleafnet-plant-ai.onrender.com'
  static const String renderUrl = 'https://tomoleafnet-plant-ai.onrender.com';

  /// Public ngrok tunnel URL (used in [BackendMode.ngrok]).
  /// Update this each time you restart `ngrok http 8000`.
  static const String ngrokUrl = 'https://custody-unwatched-portfolio.ngrok-free.dev';

  /// Dev machine's local IP address (used in [BackendMode.localWifi]).
  /// Both the phone and PC must be on the same WiFi network.
  static const String localWifiIp = '192.168.86.35';

  // ── Derived URLs (do not edit) ─────────────────────────────────────

  static String get _baseUrl {
    switch (backendMode) {
      case BackendMode.render:
        return renderUrl;
      case BackendMode.ngrok:
        return ngrokUrl;
      case BackendMode.localWifi:
        return 'http://$localWifiIp:8000';
      case BackendMode.emulator:
        return 'http://10.0.2.2:8000';
    }
  }

  /// Base URL for the Plant AI chat backend (FastAPI server).
  static String get chatBackendUrl => '$_baseUrl/chat';

  /// Health check endpoint for the Plant AI backend.
  static String get chatBackendHealthUrl => '$_baseUrl/health';

  // ── Reminder notification endpoints ───────────────────────────────
  static String get reminderScheduleUrl => '$_baseUrl/reminders/schedule';
  static String get reminderUpdateUrl => '$_baseUrl/reminders/update';
  static String get reminderCancelUrl => '$_baseUrl/reminders/cancel';

  // ── Translation endpoint (Improvement 3) ────────────────────────
  static String get translateUrl => '$_baseUrl/translate';
}
