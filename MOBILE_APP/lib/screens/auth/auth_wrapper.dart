import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../app_session.dart';
import '../../main.dart';
import 'login_screen.dart';

/// Listens to Firebase auth state and routes to either
/// the main app (MainScreen) or the login screen.
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppSession>(
      builder: (context, session, _) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: Color(0xFF309249)),
              ),
            );
          }

          if (snapshot.hasData) {
            if (!session.isAuthenticated) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                session.setAuthenticated();
              });
            }
            return const MainScreen();
          }

          if (session.isGuest) {
            return const MainScreen();
          }

          if (!session.isSignedOut) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              session.setSignedOut();
            });
          }
          return const LoginScreen();
        },
      ),
    );
  }
}
