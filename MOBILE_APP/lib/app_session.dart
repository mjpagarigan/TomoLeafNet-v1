import 'package:flutter/foundation.dart';

enum AppSessionMode { signedOut, guest, authenticated }

class AppSession extends ChangeNotifier {
  AppSession._();

  static final AppSession instance = AppSession._();

  AppSessionMode _mode = AppSessionMode.signedOut;

  AppSessionMode get mode => _mode;
  bool get isGuest => _mode == AppSessionMode.guest;
  bool get isAuthenticated => _mode == AppSessionMode.authenticated;
  bool get isSignedOut => _mode == AppSessionMode.signedOut;

  void continueAsGuest() {
    if (_mode == AppSessionMode.guest) return;
    _mode = AppSessionMode.guest;
    notifyListeners();
  }

  void setAuthenticated() {
    if (_mode == AppSessionMode.authenticated) return;
    _mode = AppSessionMode.authenticated;
    notifyListeners();
  }

  void setSignedOut() {
    if (_mode == AppSessionMode.signedOut) return;
    _mode = AppSessionMode.signedOut;
    notifyListeners();
  }
}
