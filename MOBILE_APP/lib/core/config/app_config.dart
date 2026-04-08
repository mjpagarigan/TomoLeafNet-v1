/// Application configuration constants for TomoLeafNet.
///
/// Update [chatBackendUrl] with your development machine's local network IP.
/// Both the mobile device and the dev machine must be on the same WiFi network.
///
/// To find your local IP:
///   - Windows:  ipconfig → look for "IPv4 Address"
///   - macOS:    ifconfig → look for "inet" on en0
///   - Linux:    ip addr → look for "inet" on eth0 or wlan0
class AppConfig {
  AppConfig._();

  /// Use '10.0.2.2' for Android emulator, or your local IP for physical devices.
  static const String _host = '192.168.86.35';

  /// Base URL for the Plant AI chat backend (FastAPI server).
  static const String chatBackendUrl = 'http://$_host:8000/chat';

  /// Health check endpoint for the Plant AI backend.
  static const String chatBackendHealthUrl = 'http://$_host:8000/health';
}
